extends RefCounted

## 回溯节点索引。纯函数、无状态。
##
## 节点是从**现有事件表里筛出来的**，不另写一张表。另写一张，剧情一改它就悄悄
## 错位，和 DOCX source lock 要防的是同一类问题；筛出来的表永远和剧情同步。
##
## 锚点白名单挑的是天然幕界：换场景、进玩法、CG、章节收尾。
## line / action / audio / effect 这些太细，不当节点。

const StoryDataScript := preload("res://scripts/story_data.gd")
const WeddingDataScript := preload("res://scripts/wedding_data.gd")
const MysticNightDataScript := preload("res://scripts/mystic_night_data.gd")
const Chapter3DataScript := preload("res://scripts/chapter3_data.gd")
const RollbackNamesScript := preload("res://data/rollback_names.gd")

const ANCHOR_KINDS := [
	"scene",           # 换幕 / 换背景
	"module",          # 进玩法：ForestRun / TextInput / LakeJump / StarJar
	"module_skip",
	"cg",              # 奇妙夜几乎全靠 CG 推进，不收它这一章只剩两个节点
	"endpoint",
	"blink_endpoint",
	"ending",
]

## 顺序即剧情顺序，回溯面板按这个顺序排。
const CHAPTERS := [
	{"id": "wedding", "title": "婚礼前夜", "scene": "res://scenes/wedding/wedding_prologue.tscn"},
	{"id": "mystic_night", "title": "奇妙夜", "scene": "res://scenes/mystic_night/mystic_night.tscn"},
	{"id": "forest", "title": "黑暗森林", "scene": "res://main.tscn"},
	{"id": "chapter3", "title": "典礼上的选择", "scene": "res://scenes/chapter3/chapter3.tscn"},
]


static func chapter_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for chapter in CHAPTERS:
		ids.append(str(chapter["id"]))
	return ids


static func events_of(chapter_id: String) -> Array:
	match chapter_id:
		"wedding":
			return WeddingDataScript.build_events()
		"mystic_night":
			return MysticNightDataScript.build_events()
		"forest":
			return StoryDataScript.get_events()
		"chapter3":
			return Chapter3DataScript.build_events()
		_:
			return []


## 单章的节点列表。NodeDesc = {chapter, source, kind, raw_name, display_name, index}
static func nodes_of(chapter_id: String) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var seen_sources: Dictionary = {}
	for event in events_of(chapter_id):
		if not event is Dictionary:
			continue
		var kind := str((event as Dictionary).get("type", ""))
		if not kind in ANCHOR_KINDS:
			continue
		var source := int((event as Dictionary).get("source", 0))
		if source <= 0 or seen_sources.has(source):
			continue
		seen_sources[source] = true
		var raw_name := _raw_name(event as Dictionary)
		nodes.append({
			"chapter": chapter_id,
			"source": source,
			"kind": kind,
			"raw_name": raw_name,
			"display_name": _display_name(chapter_id, source, raw_name, nodes.size()),
			"index": nodes.size(),
		})
	return nodes


static func _raw_name(event: Dictionary) -> String:
	for key in ["name", "id"]:
		var value := str(event.get(key, ""))
		if not value.is_empty():
			return value
	return ""


static func _display_name(chapter_id: String, source: int, raw_name: String, index: int) -> String:
	var override_name := RollbackNamesScript.lookup(chapter_id, source)
	if not override_name.is_empty():
		return override_name
	if not raw_name.is_empty():
		return raw_name
	return "第 %d 段" % (index + 1)


## 全部章节，带节点。回溯面板直接吃这个结构。
static func chapters_with_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for chapter in CHAPTERS:
		var entry := (chapter as Dictionary).duplicate(true)
		entry["nodes"] = nodes_of(str(chapter["id"]))
		result.append(entry)
	return result


static func total_node_count() -> int:
	var total := 0
	for chapter in CHAPTERS:
		total += nodes_of(str(chapter["id"])).size()
	return total


static func scene_of(chapter_id: String) -> String:
	for chapter in CHAPTERS:
		if str(chapter["id"]) == chapter_id:
			return str(chapter["scene"])
	return ""


static func title_of(chapter_id: String) -> String:
	for chapter in CHAPTERS:
		if str(chapter["id"]) == chapter_id:
			return str(chapter["title"])
	return chapter_id


## 事件是不是回溯锚点。四个章节脚本用它决定要不要打点。
static func is_anchor(event: Dictionary) -> bool:
	return str(event.get("type", "")) in ANCHOR_KINDS and int(event.get("source", 0)) > 0
