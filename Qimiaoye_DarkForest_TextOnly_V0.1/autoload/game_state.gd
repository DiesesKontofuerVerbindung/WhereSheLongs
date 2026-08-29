extends Node

signal changed

const SAVE_PATH := "user://river_jump.json"
const StoryDB := preload("res://data/story.gd")
const VersionDB := preload("res://data/version.gd")

var current_scene_id: String = StoryDB.START_SCENE
var best_score: int = 0
var last_result: Dictionary = {}
var guide_present: bool = true


func reset() -> void:
	current_scene_id = StoryDB.START_SCENE
	last_result = {}
	guide_present = true
	changed.emit()


func record_run(result: Dictionary) -> void:
	last_result = result.duplicate(true)
	var score := int(result.get("score", 0))
	if score > best_score:
		best_score = score
	changed.emit()
	save_game()


func to_dict() -> Dictionary:
	return {
		"version": VersionDB.STRING,
		"best_score": best_score,
	}


func from_dict(data: Dictionary) -> void:
	best_score = int(data.get("best_score", 0))
	changed.emit()


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


func try_load() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	return true
