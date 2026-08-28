extends Node

const StoryDB := preload("res://data/story.gd")

signal present_menu(scene_def)
signal present_level(scene_def)


func go_to(scene_id: String) -> void:
	if not StoryDB.has_scene(scene_id):
		push_error("Scene not found: %s" % scene_id)
		return
	var scene_def: Dictionary = StoryDB.get_scene(scene_id)
	if scene_id == "title":
		GameState.guide_present = true
	GameState.current_scene_id = scene_id
	match str(scene_def.get("type", "")):
		"menu":
			present_menu.emit(scene_def)
		"level":
			present_level.emit(scene_def)
		_:
			push_error("Unknown scene type for %s" % scene_id)


func start_new_game() -> void:
	GameState.reset()
	go_to(StoryDB.START_SCENE)


func continue_or_start() -> void:
	GameState.try_load()
	go_to(StoryDB.START_SCENE)


func complete_current_scene(result: Dictionary = {}) -> void:
	var scene_id := GameState.current_scene_id
	if not StoryDB.has_scene(scene_id):
		push_error("Cannot complete unknown scene: %s" % scene_id)
		return
	var scene_def: Dictionary = StoryDB.get_scene(scene_id)
	if str(scene_def.get("type", "")) == "level":
		GameState.record_run(result)
	var next_id := str(result.get("next", scene_def.get("on_complete", "")))
	if next_id.is_empty():
		push_error("No next scene after %s" % scene_id)
		return
	go_to(next_id)
