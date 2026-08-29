extends Node

signal changed

const SAVE_PATH := "user://save.json"
const AUTO_SAVE_PATH := "user://autosave.json"
const StoryFlow := preload("res://data/story_flow.gd")
const VersionDB := preload("res://data/version.gd")

var current_scene_id: String = StoryFlow.START_SCENE
var current_chapter: String = "chapter_1"
var current_part: String = "prologue"
var affection_amai: int = 0
var game_over_count: int = 0
var player_choice: String = ""
var custom_player_text: String = ""

var player: Dictionary = {
	"name": "小凌",
	"hp": 100,
	"max_hp": 100,
}
var inventory: Array = []
var flags: Dictionary = {}
var dialogue_choices: Dictionary = {}
var level_progress: Dictionary = {}
var quests: Dictionary = {}
var variables: Dictionary = {}

var checkpoint: Dictionary = {
	"scene_id": "",
	"map_id": "",
	"position": Vector2.ZERO,
	"part": "",
}


func reset() -> void:
	current_scene_id = StoryFlow.START_SCENE
	current_chapter = "chapter_1"
	current_part = "prologue"
	affection_amai = 0
	game_over_count = 0
	player_choice = ""
	custom_player_text = ""
	player = {"name": "小凌", "hp": 100, "max_hp": 100}
	inventory = []
	flags = {}
	dialogue_choices = {}
	level_progress = {}
	quests = {}
	variables = {}
	checkpoint = {"scene_id": "", "map_id": "", "position": Vector2.ZERO, "part": ""}
	changed.emit()


func has_flag(flag_name: String) -> bool:
	return bool(flags.get(flag_name, false))


func set_flag(flag_name: String, value: Variant = true) -> void:
	flags[flag_name] = value
	changed.emit()


func get_var(key: String, default: Variant = null) -> Variant:
	if key == "affection_amai":
		return affection_amai
	if key == "current_chapter":
		return current_chapter
	if key == "current_part":
		return current_part
	if key == "game_over_count":
		return game_over_count
	if key == "player_choice":
		return player_choice
	if key == "custom_player_text":
		return custom_player_text
	return variables.get(key, default)


func set_var(key: String, value: Variant, op: String = "set") -> void:
	match key:
		"affection_amai":
			affection_amai = _apply_op(affection_amai, value, op)
		"current_chapter":
			current_chapter = str(value)
		"current_part":
			current_part = str(value)
		"game_over_count":
			game_over_count = int(_apply_op(game_over_count, value, op))
		"player_choice":
			player_choice = str(value)
		"custom_player_text":
			custom_player_text = str(value)
		_:
			var current: Variant = variables.get(key, 0)
			variables[key] = _apply_op(current, value, op)
	changed.emit()


func _apply_op(current: Variant, value: Variant, op: String) -> Variant:
	match op:
		"add":
			return current + value
		"sub":
			return current - value
		_:
			return value


func apply_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	var flag_updates: Dictionary = effects.get("flags", {})
	for key in flag_updates.keys():
		flags[str(key)] = flag_updates[key]
	var var_updates: Dictionary = effects.get("vars", {})
	for key in var_updates.keys():
		var spec: Variant = var_updates[key]
		if typeof(spec) == TYPE_DICTIONARY:
			set_var(str(key), spec.get("value", 0), str(spec.get("op", "set")))
		else:
			set_var(str(key), spec)
	var adds: Array = effects.get("inventory_add", [])
	for item_id in adds:
		inventory.append(item_id)
	var quest_updates: Dictionary = effects.get("quests", {})
	for quest_id in quest_updates.keys():
		quests[str(quest_id)] = quest_updates[quest_id]
	changed.emit()


func record_choice(scene_id: String, choice_id: String) -> void:
	dialogue_choices[scene_id] = choice_id
	player_choice = choice_id
	changed.emit()


func record_level(level_id: String, result: Dictionary) -> void:
	var stored := result.duplicate(true)
	stored["completed"] = stored.get("result", "") == "success" or stored.get("completed", false)
	level_progress[level_id] = stored
	changed.emit()


func set_checkpoint(scene_id: String, map_id: String = "", position: Vector2 = Vector2.ZERO) -> void:
	checkpoint = {
		"scene_id": scene_id,
		"map_id": map_id,
		"position": position,
		"part": current_part,
	}
	changed.emit()


func to_dict() -> Dictionary:
	return {
		"version": VersionDB.STRING,
		"current_scene_id": current_scene_id,
		"current_chapter": current_chapter,
		"current_part": current_part,
		"affection_amai": affection_amai,
		"game_over_count": game_over_count,
		"player_choice": player_choice,
		"custom_player_text": custom_player_text,
		"player": player.duplicate(true),
		"inventory": inventory.duplicate(true),
		"flags": flags.duplicate(true),
		"dialogue_choices": dialogue_choices.duplicate(true),
		"level_progress": level_progress.duplicate(true),
		"quests": quests.duplicate(true),
		"variables": variables.duplicate(true),
		"checkpoint": {
			"scene_id": checkpoint.get("scene_id", ""),
			"map_id": checkpoint.get("map_id", ""),
			"position": {"x": checkpoint.get("position", Vector2.ZERO).x, "y": checkpoint.get("position", Vector2.ZERO).y},
			"part": checkpoint.get("part", ""),
		},
	}


func from_dict(data: Dictionary) -> void:
	current_scene_id = str(data.get("current_scene_id", StoryFlow.START_SCENE))
	current_chapter = str(data.get("current_chapter", "chapter_1"))
	current_part = str(data.get("current_part", "prologue"))
	affection_amai = int(data.get("affection_amai", 0))
	game_over_count = int(data.get("game_over_count", 0))
	player_choice = str(data.get("player_choice", ""))
	custom_player_text = str(data.get("custom_player_text", ""))
	player = data.get("player", player)
	inventory = data.get("inventory", [])
	flags = data.get("flags", {})
	dialogue_choices = data.get("dialogue_choices", {})
	level_progress = data.get("level_progress", {})
	quests = data.get("quests", {})
	variables = data.get("variables", {})
	var cp: Dictionary = data.get("checkpoint", {})
	var pos: Dictionary = cp.get("position", {})
	checkpoint = {
		"scene_id": str(cp.get("scene_id", "")),
		"map_id": str(cp.get("map_id", "")),
		"position": Vector2(float(pos.get("x", 0)), float(pos.get("y", 0))),
		"part": str(cp.get("part", "")),
	}
	changed.emit()


func save_game(path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


func auto_save() -> void:
	save_game(AUTO_SAVE_PATH)


func try_load(path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	from_dict(parsed)
	return StoryFlow.has_scene(current_scene_id)


func clear_save() -> void:
	for path in [SAVE_PATH, AUTO_SAVE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
