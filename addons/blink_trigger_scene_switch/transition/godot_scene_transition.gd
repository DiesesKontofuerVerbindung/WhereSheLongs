class_name GodotSceneTransition
extends SceneTransitionHandler

var fade_rect: ColorRect
var config: BlinkConfiguration


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 1)
	fade_rect.modulate.a = 0.0
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade_rect)


func switch_to(scene_id: String) -> void:
	_load_scene(scene_id)


func play(scene_id: String, p_config: BlinkConfiguration) -> void:
	config = p_config
	var mode := "Fade"
	if p_config:
		mode = p_config.transition
	match mode:
		"Instant":
			transition_started.emit(scene_id)
			_load_scene(scene_id)
			transition_finished.emit(scene_id)
		"Custom":
			transition_started.emit(scene_id)
		"FadeBlack":
			_fade_then_load(scene_id, true)
		_:
			_fade_then_load(scene_id, false)


func _fade_then_load(scene_id: String, hold_black: bool) -> void:
	transition_started.emit(scene_id)
	var fade_in: float = config.fade_seconds if config else 0.28
	var fade_out: float = fade_in
	var hold: float = config.black_hold_seconds if (config and hold_black) else 0.0
	var tween := create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, fade_in)
	tween.tween_callback(_load_scene.bind(scene_id))
	if hold > 0.0:
		tween.tween_interval(hold)
	tween.tween_property(fade_rect, "modulate:a", 0.0, fade_out)
	tween.tween_callback(func() -> void: transition_finished.emit(scene_id))


func _load_scene(scene_id: String) -> void:
	if scene_id.is_empty():
		push_error("Blink child scene is empty")
		return
	if has_node("/root/SceneManager") and not scene_id.begins_with("res://"):
		get_node("/root/SceneManager").go_to(scene_id)
		return
	get_tree().change_scene_to_file(scene_id)
