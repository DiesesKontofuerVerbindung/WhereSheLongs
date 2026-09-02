extends Node

## 玩家走过哪些节点。回溯面板的锁 / `???` 全看它。
##
## 只存「去过哪儿」，不存世界状态快照——这个游戏是确定性的线性事件表，
## 回溯 = 从节点重放，重放本身就能重建状态（dev jump 现在就是这么干的）。
## 好处是改剧情之后旧存档不会废：认不出的节点忽略就行，不用写迁移。

signal progress_changed

const ChapterIndexScript := preload("res://scripts/chapter_index.gd")
const SECTION := "progress"

## chapter_id -> { source: true }
var _visited: Dictionary = {}
## chapter_id -> 最远到过的 source
var _furthest: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()


func _load() -> void:
	var section := SaveStore.get_section(SECTION)
	_visited = {}
	_furthest = {}
	var raw_visited: Variant = section.get("visited", {})
	if raw_visited is Dictionary:
		for chapter_id in (raw_visited as Dictionary):
			var sources: Variant = (raw_visited as Dictionary)[chapter_id]
			if not sources is Array:
				continue
			var set_for_chapter: Dictionary = {}
			for source in (sources as Array):
				set_for_chapter[int(source)] = true
			_visited[str(chapter_id)] = set_for_chapter
	var raw_furthest: Variant = section.get("furthest", {})
	if raw_furthest is Dictionary:
		for chapter_id in (raw_furthest as Dictionary):
			_furthest[str(chapter_id)] = int((raw_furthest as Dictionary)[chapter_id])


func _persist() -> void:
	var visited_out: Dictionary = {}
	for chapter_id in _visited:
		var sources: Array = (_visited[chapter_id] as Dictionary).keys()
		sources.sort()
		visited_out[chapter_id] = sources
	SaveStore.set_section(SECTION, {"visited": visited_out, "furthest": _furthest.duplicate()})


## 幂等。已经记过的节点不会重复写盘。
func visit(chapter_id: String, source: int) -> void:
	if chapter_id.is_empty() or source <= 0:
		return
	if not _visited.has(chapter_id):
		_visited[chapter_id] = {}
	var chapter_set: Dictionary = _visited[chapter_id]
	var furthest_changed := source > int(_furthest.get(chapter_id, 0))
	if chapter_set.has(source) and not furthest_changed:
		return
	chapter_set[source] = true
	if furthest_changed:
		_furthest[chapter_id] = source
	_persist()
	progress_changed.emit()


func is_visited(chapter_id: String, source: int) -> bool:
	if not _visited.has(chapter_id):
		return false
	return (_visited[chapter_id] as Dictionary).has(source)


func furthest(chapter_id: String) -> int:
	return int(_furthest.get(chapter_id, 0))


func visited_count(chapter_id: String) -> int:
	if not _visited.has(chapter_id):
		return 0
	return (_visited[chapter_id] as Dictionary).size()


func total_visited() -> int:
	var total := 0
	for chapter_id in _visited:
		total += (_visited[chapter_id] as Dictionary).size()
	return total


## 面板页脚的「已解锁 12 / 31」。分母来自事件表，分子来自存档，
## 存档里认不出的节点不计入——剧情删掉一段之后计数不会超出上限。
func stats() -> Dictionary:
	var total := ChapterIndexScript.total_node_count()
	var unlocked := 0
	for chapter in ChapterIndexScript.chapters_with_nodes():
		for node in (chapter["nodes"] as Array):
			if is_visited(str(node["chapter"]), int(node["source"])):
				unlocked += 1
	return {"unlocked": unlocked, "total": total}


func reset() -> void:
	_visited = {}
	_furthest = {}
	_persist()
	SaveStore.flush()
	progress_changed.emit()


## 测试用：不落盘地灌一份访问记录。
func debug_seed(visited: Dictionary) -> void:
	_visited = {}
	for chapter_id in visited:
		var chapter_set: Dictionary = {}
		for source in (visited[chapter_id] as Array):
			chapter_set[int(source)] = true
		_visited[str(chapter_id)] = chapter_set
	progress_changed.emit()
