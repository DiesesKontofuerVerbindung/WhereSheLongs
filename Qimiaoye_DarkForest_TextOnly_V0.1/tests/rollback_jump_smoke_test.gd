extends Node

## 把回溯面板里**每一个**节点都跳一遍，找出落地黑屏的点。
##
## 判据就一条：跳过去之后章节恢复出来的场景上下文不能是空的。
## 四章的 _restore_dev_jump_*context 都是「往回扫到最近的 scene/cg 事件」，
## 扫不到就直接 return —— 那种情况下舞台上一张背景都没有，玩家看到的就是黑屏。
##
## 每个节点独立实例化目标章节，读探针，立刻释放。不走 change_scene，
## 免得 44 次真实切场景把测试自己冲掉。

const ChapterIndexScript := preload("res://scripts/chapter_index.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")

## 本来就该是黑的节点。写理由是为了让后来人能判断这条还算不算数，
## 而不是看到一行白名单就当成「已知问题」放着。
## 白名单里的节点如果哪天不黑了，测试同样会报——防止这张表烂掉。
const EXPECTED_BLANK := {
	"mystic_night:1": "开场 scene，第一张 CG 在 source 16，在那之前本来就没有美术",
	"mystic_night:146": "事件本身是 name=黑屏 / asset=\"\" 的空 CG，黑屏是剧情要的",
	"forest:29": "环境背景图0 是闭眼状态，美术要到 source 49 的 EYE_OPEN 才睁眼显现",
}

const SETTLE_FRAMES := 4
const NODE_DEADLINE := 8.0

var _save_backup := ""
var _had_save := false


func _ready() -> void:
	_backup_save()
	var failures := PackedStringArray()
	var blank := PackedStringArray()
	var checked := 0

	for chapter in ChapterIndexScript.chapters_with_nodes():
		var chapter_id := str(chapter["id"])
		var scene_path := str(chapter["scene"])
		var packed := load(scene_path) as PackedScene
		if packed == null:
			failures.append("章节场景无法载入：%s" % scene_path)
			continue
		for node in (chapter["nodes"] as Array):
			var source := int(node["source"])
			var probe := await _probe_jump(packed, chapter_id, source)
			checked += 1
			if probe.is_empty():
				failures.append("%s:%d 跳转后拿不到探针（%s）" % [chapter_id, source, node["display_name"]])
				continue
			var scene_name := str(probe.get("scene", "")).strip_edges()
			var has_art := bool(probe.get("has_art", false))
			var node_key := "%s:%d" % [chapter_id, source]
			var is_blank := scene_name.is_empty() or not has_art
			var expected := EXPECTED_BLANK.has(node_key)
			if is_blank and not expected:
				blank.append("%s %-22s scene=%s art=%s" % [
					node_key, str(node["display_name"]),
					"(空)" if scene_name.is_empty() else scene_name,
					"有" if has_art else "无",
				])
			elif expected and not is_blank:
				failures.append("%s 现在不黑了，白名单该删：%s" % [node_key, EXPECTED_BLANK[node_key]])
			if bool(probe.get("dev_jump_active", true)):
				failures.append("%s:%d 回溯被当成了开发者跳转" % [chapter_id, source])

	_restore_save()

	for entry in blank:
		print("ROLLBACK_JUMP_BLANK %s" % entry)
	for failure in failures:
		print("ROLLBACK_JUMP_SMOKE_FAIL %s" % failure)
	if failures.is_empty() and blank.is_empty():
		print("ROLLBACK_JUMP_SMOKE_PASS nodes=%d unexpected_blank=0 by_design_blank=%d" % [checked, EXPECTED_BLANK.size()])
		get_tree().quit(0)
		return
	print("ROLLBACK_JUMP_SMOKE_FAIL_TOTAL nodes=%d blank=%d other=%d" % [checked, blank.size(), failures.size()])
	get_tree().quit(1)


func _probe_jump(packed: PackedScene, chapter_id: String, source: int) -> Dictionary:
	var events := ChapterIndexScript.events_of(chapter_id)
	var resolved := DevJumpPanelScript.resolve_source_line(events, source)
	if resolved.is_empty():
		return {}
	# 与 pause_menu._on_node_pressed 构造的 payload 保持一致。
	get_tree().root.set_meta(DevJumpPanelScript.META_KEY, {
		"chapter": chapter_id,
		"scene": ChapterIndexScript.scene_of(chapter_id),
		"requested_source": source,
		"actual_source": int(resolved.get("source", 0)),
		"target_index": int(resolved.get("index", -1)),
		"exact": bool(resolved.get("exact", false)),
		"from_chapter": chapter_id,
		"from_source": 0,
		"same_chapter": true,
		"requested_at": Time.get_datetime_string_from_system(),
		"rollback": true,
	})

	var instance := packed.instantiate()
	add_child(instance)
	var deadline := Time.get_ticks_msec() + int(NODE_DEADLINE * 1000.0)
	var probe: Dictionary = {}
	var frames := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		frames += 1
		if frames >= SETTLE_FRAMES and is_instance_valid(instance) and instance.has_method("rollback_probe"):
			probe = instance.call("rollback_probe")
			# 场景名设上了不代表画面上真有东西：再扫一遍节点树，
			# 确认确实存在一张可见、有贴图、不透明的美术层。
			probe["has_art"] = _has_visible_art(instance)
			break
	if is_instance_valid(instance):
		instance.queue_free()
	await get_tree().process_frame
	# 没消费掉的 meta 会污染下一个用例。
	if get_tree().root.has_meta(DevJumpPanelScript.META_KEY):
		get_tree().root.remove_meta(DevJumpPanelScript.META_KEY)
	return probe


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveStore.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SaveStore.SAVE_PATH)


func _restore_save() -> void:
	SaveStore.flush()
	if _had_save:
		var file := FileAccess.open(SaveStore.SAVE_PATH, FileAccess.WRITE)
		if file != null:
			file.store_string(_save_backup)
			file.close()
	SaveStore.load_from_disk()


## 递归找「屏幕上真的有图」的证据：可见 + 有贴图 + 不透明。
## 不可见的子树整棵跳过——玩家看不到的东西不算数。
func _has_visible_art(node: Node) -> bool:
	for child in node.get_children():
		if child is CanvasItem:
			var item := child as CanvasItem
			if not item.visible or item.modulate.a <= 0.01:
				continue
			if child is TextureRect and (child as TextureRect).texture != null:
				return true
			if child is Sprite2D and (child as Sprite2D).texture != null:
				return true
			if child is VideoStreamPlayer and (child as VideoStreamPlayer).stream != null:
				return true
		if _has_visible_art(child):
			return true
	return false
