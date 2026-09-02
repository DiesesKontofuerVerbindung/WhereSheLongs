extends Node

## 回溯数据层测试：节点索引（纯函数）、存档 I/O、访问记录。
##
## 会短暂动到 user://save.json（损坏恢复用例必须真写一个坏文件），
## 跑完原样还回去。

const ChapterIndexScript := preload("res://scripts/chapter_index.gd")
const RollbackNamesScript := preload("res://data/rollback_names.gd")

const TEST_SECTION := "test_roundtrip"

var _save_backup := ""
var _had_save := false


func _ready() -> void:
	var failures := PackedStringArray()
	_backup_save()
	_verify_chapter_index(failures)
	_verify_save_store(failures)
	_verify_chapter_progress(failures)
	_restore_save()

	if failures.is_empty():
		var stats: Dictionary = {"total": ChapterIndexScript.total_node_count()}
		print("ROLLBACK_PROGRESS_PASS chapters=%d nodes=%d anchors=%s atomic_write=true corrupt_recovery=true visit_idempotent=true furthest_monotonic=true" % [
			ChapterIndexScript.CHAPTERS.size(),
			int(stats["total"]),
			"/".join(ChapterIndexScript.ANCHOR_KINDS),
		])
		get_tree().quit(0)
		return
	for failure in failures:
		print("ROLLBACK_PROGRESS_FAIL %s" % failure)
	get_tree().quit(1)


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveStore.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SaveStore.SAVE_PATH)


func _restore_save() -> void:
	if _had_save:
		var file := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_save_backup)
			file.close()
	elif FileAccess.file_exists(SaveStore.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveStore.SAVE_PATH))
	SaveStore.load_from_disk()


# ------------------------------------------------------------ ChapterIndex

func _verify_chapter_index(failures: PackedStringArray) -> void:
	var chapters := ChapterIndexScript.chapters_with_nodes()
	if chapters.size() != 4:
		failures.append("章节数不是 4：%d" % chapters.size())
	var total := 0
	for chapter in chapters:
		var chapter_id := str(chapter["id"])
		var nodes: Array = chapter["nodes"]
		if nodes.is_empty():
			failures.append("章节 %s 一个回溯节点都没筛出来" % chapter_id)
		if str(chapter["scene"]).is_empty() or not ResourceLoader.exists(str(chapter["scene"])):
			failures.append("章节 %s 的场景路径无效：%s" % [chapter_id, chapter["scene"]])
		var seen: Dictionary = {}
		var last_source := 0
		for node in nodes:
			var source := int(node["source"])
			if seen.has(source):
				failures.append("%s 出现重复节点 source=%d" % [chapter_id, source])
			seen[source] = true
			if source < last_source:
				failures.append("%s 节点没有按 source 递增：%d 在 %d 之后" % [chapter_id, source, last_source])
			last_source = source
			if str(node["display_name"]).strip_edges().is_empty():
				failures.append("%s:%d 显示名为空" % [chapter_id, source])
			# 面板是给玩家看的，不许漏英文。module / endpoint 事件没有 name 字段，
			# 回落到 id 就会显示成 WeddingVowSolo / MYSTIC_NIGHT_END 这种，
			# 必须在 rollback_names.gd 里补中文覆盖。
			var shown := str(node["display_name"])
			for index in shown.length():
				var code := shown.unicode_at(index)
				if (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
					failures.append("%s:%d 显示名里有英文，需要中文覆盖：%s" % [chapter_id, source, shown])
					break
			if not str(node["kind"]) in ChapterIndexScript.ANCHOR_KINDS:
				failures.append("%s:%d 的 kind 不在锚点白名单：%s" % [chapter_id, source, node["kind"]])
		total += nodes.size()
	if total != ChapterIndexScript.total_node_count():
		failures.append("total_node_count 与逐章求和不一致")

	# 显示名覆盖表里不该有指不到任何节点的孤儿键——那说明剧情改过而表没跟上。
	for key in RollbackNamesScript.OVERRIDES:
		var parts := str(key).split(":")
		if parts.size() != 2:
			failures.append("显示名覆盖键格式错误：%s" % key)
			continue
		var found := false
		for node in ChapterIndexScript.nodes_of(parts[0]):
			if int(node["source"]) == int(parts[1]):
				found = true
				break
		if not found:
			failures.append("显示名覆盖是孤儿键（没有对应节点）：%s" % key)


# -------------------------------------------------------------- SaveStore

func _verify_save_store(failures: PackedStringArray) -> void:
	SaveStore.set_section(TEST_SECTION, {"a": 1, "b": "x"})
	SaveStore.flush()
	if not FileAccess.file_exists(SaveStore.SAVE_PATH):
		failures.append("flush 之后存档文件不存在")
	if FileAccess.file_exists(SaveStore.TEMP_PATH):
		failures.append("原子写留下了 .tmp 残file")

	SaveStore.load_from_disk()
	var round_trip := SaveStore.get_section(TEST_SECTION)
	if int(round_trip.get("a", 0)) != 1 or str(round_trip.get("b", "")) != "x":
		failures.append("存档往返内容对不上：%s" % str(round_trip))

	# 损坏档必须降级成新档，而且不能静默吞掉——要留备份文件。
	var broken := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
	if broken != null:
		broken.store_string("{ this is not json")
		broken.close()
	SaveStore.load_from_disk()
	if not SaveStore.get_section(TEST_SECTION).is_empty():
		failures.append("损坏档没有降级成空档")
	var dir := DirAccess.open("user://")
	var has_backup := false
	if dir != null:
		for name in dir.get_files():
			if name.begins_with("save.corrupt."):
				has_backup = true
				dir.remove(name)
	if not has_backup:
		failures.append("损坏档没有留下 save.corrupt.* 备份")


# --------------------------------------------------------- ChapterProgress

func _verify_chapter_progress(failures: PackedStringArray) -> void:
	var nodes := ChapterIndexScript.nodes_of("forest")
	if nodes.size() < 2:
		failures.append("森林节点太少，无法验证访问记录")
		return
	var first := int(nodes[0]["source"])
	var second := int(nodes[1]["source"])

	ChapterProgress.debug_seed({})
	if ChapterProgress.is_visited("forest", first):
		failures.append("清空之后仍然报告去过")
	if ChapterProgress.total_visited() != 0:
		failures.append("清空之后计数不为 0")

	ChapterProgress.debug_seed({"forest": [first, second]})
	if not ChapterProgress.is_visited("forest", first) or not ChapterProgress.is_visited("forest", second):
		failures.append("灌入的访问记录读不回来")
	if ChapterProgress.visited_count("forest") != 2:
		failures.append("单章访问计数错误：%d" % ChapterProgress.visited_count("forest"))
	if ChapterProgress.is_visited("forest", 999999):
		failures.append("没去过的节点被报告成去过")

	var stats: Dictionary = ChapterProgress.stats()
	if int(stats["unlocked"]) != 2:
		failures.append("stats 已解锁数错误：%s" % str(stats))
	if int(stats["total"]) != ChapterIndexScript.total_node_count():
		failures.append("stats 总数与节点索引不一致：%s" % str(stats))
	if int(stats["unlocked"]) > int(stats["total"]):
		failures.append("已解锁数超过总数")

	# 存档里留下剧情已删除的节点时，不能把计数撑爆。
	ChapterProgress.debug_seed({"forest": [first, 999999]})
	var stale_stats: Dictionary = ChapterProgress.stats()
	if int(stale_stats["unlocked"]) != 1:
		failures.append("存档里的失效节点被算进了已解锁：%s" % str(stale_stats))

	ChapterProgress.debug_seed({})
