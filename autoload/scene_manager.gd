extends Node

const StoryFlow := preload("res://data/story_flow.gd")
const DialogueLoader := preload("res://data/dialogue_loader.gd")

signal present_dialogue(scene_def)
signal present_level(scene_def)
signal present_cg(scene_def)
signal present_title
signal present_game_over(payload: Dictionary)
signal fade_requested(fade_in: bool)

var _transition: CanvasLayer
var _retry_scene_id := ""


func _ready() -> void:
	EventBus.game_over.connect(_on_game_over)
	EventBus.game_over_retry.connect(_on_game_over_retry)


func bind_transition(layer: CanvasLayer) -> void:
	_transition = layer


func go_to(scene_id: String) -> void:
	if scene_id == "quit_game":
		GameState.save_game()
		get_tree().quit()
		return
	if not StoryFlow.has_scene(scene_id):
		push_error("Scene not found: %s" % scene_id)
		return
	var scene_def: Dictionary = StoryFlow.get_scene(scene_id)
	scene_def["lines"] = DialogueLoader.resolve_lines(scene_def)
	if scene_def.get("choices", []).is_empty():
		scene_def["choices"] = DialogueLoader.resolve_choices(scene_def)
	GameState.current_scene_id = scene_id
	GameState.auto_save()
	match str(scene_def.get("type", "")):
		"title":
			present_title.emit()
		"dialogue":
			present_dialogue.emit(scene_def)
		"level":
			present_level.emit(scene_def)
		"cg":
			present_cg.emit(scene_def)
		_:
			push_error("Unknown scene type for %s" % scene_id)


func start_new_game() -> void:
	GameState.clear_save()
	GameState.reset()
	go_to("chapter1_prologue")


func continue_or_start() -> void:
	if GameState.try_load(GameState.AUTO_SAVE_PATH):
		go_to(GameState.current_scene_id)
	elif GameState.try_load():
		go_to(GameState.current_scene_id)
	else:
		present_title.emit()


func complete_current_scene(result: Dictionary = {}) -> void:
	var scene_id := GameState.current_scene_id
	if not StoryFlow.has_scene(scene_id):
		push_error("Cannot complete unknown scene: %s" % scene_id)
		return
	var scene_def: Dictionary = StoryFlow.get_scene(scene_id)
	if str(scene_def.get("type", "")) == "level":
		GameState.record_level(str(scene_def.get("level_id", scene_id)), result)
	var effects: Dictionary = scene_def.get("effects", {})
	if not effects.is_empty():
		GameState.apply_effects(effects)
	var next_spec: Variant = result.get("next", scene_def.get("on_complete", scene_def.get("next", "")))
	var next_id := _resolve_next(next_spec)
	if next_id.is_empty():
		push_error("No next scene after %s" % scene_id)
		return
	await fade_transition(true)
	go_to(next_id)
	await fade_transition(false)


func fade_transition(fade_out: bool, duration: float = 0.4) -> void:
	if _transition and _transition.has_method("fade"):
		await _transition.fade(fade_out, duration)
	else:
		await get_tree().create_timer(duration).timeout


func retry_from_checkpoint() -> void:
	var cp: Dictionary = GameState.checkpoint
	var scene_id := str(cp.get("scene_id", GameState.current_scene_id))
	if scene_id.is_empty():
		scene_id = _retry_scene_id
	if scene_id.is_empty():
		start_new_game()
		return
	go_to(scene_id)


func _on_game_over(reason: String, payload: Dictionary) -> void:
	GameState.set_var("game_over_count", 1, "add")
	_retry_scene_id = str(payload.get("retry_scene", GameState.current_scene_id))
	present_game_over.emit({"reason": reason, "payload": payload})


func _on_game_over_retry() -> void:
	retry_from_checkpoint()


func _resolve_next(spec: Variant) -> String:
	if typeof(spec) == TYPE_STRING:
		return str(spec)
	if typeof(spec) == TYPE_DICTIONARY:
		var condition := str(spec.get("condition", spec.get("flag", "")))
		if condition.is_empty():
			return ""
		if GameState.has_flag(condition):
			return str(spec.get("true", ""))
		return str(spec.get("false", ""))
	return ""
