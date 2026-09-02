extends Node

signal changed

const SAVE_PATH := "user://river_jump.json"
const SECTION := "endings"
const StoryDB := preload("res://data/story.gd")
const VersionDB := preload("res://data/version.gd")

var current_scene_id: String = StoryDB.START_SCENE
var best_score: int = 0
var last_result: Dictionary = {}
var guide_present: bool = true
var unlocked_endings: Array[String] = []
var last_ending: String = ""
var best_ending: String = ""


## 既有缺陷：try_load() 之前没有任何调用者，每次启动都从空的开始，
## 结局解锁永远累积不起来（跑完 A 再跑 B，存档里只剩 B）。
## SaveStore 在 autoload 顺序里排在前面，这里读到的一定是已经载入的档。
func _ready() -> void:
	try_load()


func reset() -> void:
	current_scene_id = StoryDB.START_SCENE
	last_result = {}
	guide_present = true
	unlocked_endings = []
	last_ending = ""
	best_ending = ""
	changed.emit()


func record_run(result: Dictionary) -> void:
	last_result = result.duplicate(true)
	var score := int(result.get("score", 0))
	if score > best_score:
		best_score = score
	changed.emit()
	save_game()


func unlock_ending(ending_id: String, persist := true) -> void:
	last_ending = ending_id
	if not ending_id in unlocked_endings:
		unlocked_endings.append(ending_id)
	best_ending = _best_ending_id()
	changed.emit()
	if persist:
		save_game()


func is_unlocked(ending_id: String) -> bool:
	return ending_id in unlocked_endings


func ending_count() -> int:
	return unlocked_endings.size()


func _best_ending_id() -> String:
	for candidate in ["C", "A", "B"]:
		if candidate in unlocked_endings:
			return candidate
	return ""


func to_dict() -> Dictionary:
	return {
		"version": VersionDB.STRING,
		"best_score": best_score,
		"unlocked_endings": unlocked_endings.duplicate(),
		"last_ending": last_ending,
		"best_ending": best_ending,
	}


func from_dict(data: Dictionary) -> void:
	best_score = int(data.get("best_score", 0))
	var raw_endings: Variant = data.get("unlocked_endings", [])
	if raw_endings is Array:
		unlocked_endings.assign(raw_endings as Array)
	else:
		unlocked_endings.clear()
	last_ending = str(data.get("last_ending", ""))
	best_ending = str(data.get("best_ending", _best_ending_id()))
	changed.emit()


## 存档统一走 SaveStore：原子写、防抖、损坏恢复都在那一层。
## 这里只负责把自己的数据塞进对应的段，不再单独开一个文件——
## 之前 river_jump.json / chapter3_endings.json / save.json 三份并存，
## 结局写在旧文件里、进度写在新文件里，读出来必然对不上。
func save_game() -> void:
	SaveStore.set_section(SECTION, to_dict())


func try_load() -> bool:
	var section := SaveStore.get_section(SECTION)
	if section.is_empty():
		return false
	from_dict(section)
	return true
