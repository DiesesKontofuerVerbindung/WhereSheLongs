extends Node2D
class_name BaseExplorationMap

## Base class for exploration maps. Subclass for part-specific event logic.

signal finished(result)

const PlayerScene := preload("res://characters/player.tscn")
const PlaceholderAssets := preload("res://systems/placeholder_assets.gd")
const DialogueLayout := preload("res://systems/dialogue_layout.gd")
const PLAYER_BOUNDS_PADDING := 14.0

var _scene_def: Dictionary = {}
var _player: CharacterBody2D
var _dialogue_overlay: Control
var _ui_layer: CanvasLayer
var _ui_root: Control
var _dialogue_active := false
var _camera: Camera2D
var _camera_bounds := Rect2(0, 0, 960, 540)


func setup(scene_def: Dictionary) -> void:
	_scene_def = scene_def
	GameState.set_checkpoint(str(scene_def.get("id", "")), name, Vector2.ZERO)


func _ready() -> void:
	_ui_layer = CanvasLayer.new()
	add_child(_ui_layer)
	_ui_root = Control.new()
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.custom_minimum_size = DialogueLayout.VIEWPORT
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)
	_spawn_player()
	_build_environment()
	_setup_camera()


func _setup_camera() -> void:
	_camera = get_node_or_null("Camera2D") as Camera2D
	if _camera == null:
		_camera = Camera2D.new()
		_camera.name = "Camera2D"
		add_child(_camera)
	_camera.enabled = true
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	_update_camera_limits()
	_follow_player_with_camera(true)


func _physics_process(_delta: float) -> void:
	if _camera == null or _player == null:
		return
	_clamp_player_to_bounds()
	_follow_player_with_camera()


func _follow_player_with_camera(reset_smoothing := false) -> void:
	var view_size := _get_camera_view_size()
	var target := _player.global_position
	var half_w := view_size.x * 0.5
	var half_h := view_size.y * 0.5
	if _camera_bounds.size.x > view_size.x:
		target.x = clampf(target.x, _camera_bounds.position.x + half_w, _camera_bounds.end.x - half_w)
	else:
		target.x = _camera_bounds.get_center().x
	if _camera_bounds.size.y > view_size.y:
		target.y = clampf(target.y, _camera_bounds.position.y + half_h, _camera_bounds.end.y - half_h)
	else:
		target.y = _camera_bounds.get_center().y
	_camera.global_position = target
	if reset_smoothing:
		_camera.reset_smoothing()


func _get_camera_view_size() -> Vector2:
	var viewport_size := get_viewport_rect().size
	var zoom := _camera.zoom.abs()
	return Vector2(
		viewport_size.x / maxf(zoom.x, 0.001),
		viewport_size.y / maxf(zoom.y, 0.001)
	)


func _clamp_player_to_bounds() -> void:
	var min_pos := _camera_bounds.position + Vector2.ONE * PLAYER_BOUNDS_PADDING
	var max_pos := _camera_bounds.end - Vector2.ONE * PLAYER_BOUNDS_PADDING
	var clamped_position := _player.global_position
	clamped_position.x = _clamp_axis(clamped_position.x, min_pos.x, max_pos.x, _camera_bounds.get_center().x)
	clamped_position.y = _clamp_axis(clamped_position.y, min_pos.y, max_pos.y, _camera_bounds.get_center().y)
	_player.global_position = clamped_position


func _clamp_axis(value: float, minimum: float, maximum: float, fallback: float) -> float:
	if minimum > maximum:
		return fallback
	return clampf(value, minimum, maximum)


func _update_camera_limits() -> void:
	if _camera == null:
		return
	_camera.limit_left = floori(_camera_bounds.position.x)
	_camera.limit_top = floori(_camera_bounds.position.y)
	_camera.limit_right = ceili(_camera_bounds.end.x)
	_camera.limit_bottom = ceili(_camera_bounds.end.y)


func set_camera_bounds(bounds: Rect2) -> void:
	_camera_bounds = bounds
	_update_camera_limits()
	if _camera and _player:
		_clamp_player_to_bounds()
		_follow_player_with_camera(true)


func _spawn_player() -> void:
	_player = PlayerScene.instantiate()
	var spawn := get_node_or_null("SpawnPoint") as Marker2D
	_player.global_position = spawn.global_position if spawn else Vector2(480, 400)
	add_child(_player)


func _build_environment() -> void:
	pass


func _add_fill_background(base: Color, accent: Color) -> Sprite2D:
	return PlaceholderAssets.create_fill_background(self, _camera_bounds, base, accent)


func _show_inline_dialogue(lines: Array, on_done: Callable = Callable()) -> void:
	if _dialogue_overlay:
		_dialogue_overlay.queue_free()
	_player.set_can_move(false)
	_dialogue_overlay = _make_dialogue_box(lines, on_done)
	_ui_root.add_child(_dialogue_overlay)
	_dialogue_active = true


func _unhandled_input(event: InputEvent) -> void:
	_try_advance_dialogue(event)


func _try_advance_dialogue(event: InputEvent) -> void:
	if not _dialogue_active or _dialogue_overlay == null:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if _dialogue_overlay.has_method("advance"):
			_dialogue_overlay.advance()
		get_viewport().set_input_as_handled()


func _make_dialogue_box(lines: Array, on_done: Callable) -> Control:
	var box := _DialogueBox.new()
	box.closed.connect(_on_dialogue_box_closed)
	box.setup(lines, on_done)
	return box


func _on_dialogue_box_closed(box: Control) -> void:
	if _dialogue_overlay == box:
		_dialogue_active = false
		_dialogue_overlay = null



class _DialogueBox extends Control:
	signal closed(box: Control)

	var _speaker: Label
	var _body: Label
	var _btn: Button
	var _lines: Array = []
	var _idx := 0
	var _on_done: Callable

	func setup(lines: Array, on_done: Callable) -> void:
		_lines = lines
		_on_done = on_done
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		custom_minimum_size = DialogueLayout.VIEWPORT
		mouse_filter = Control.MOUSE_FILTER_STOP

		var panel := PanelContainer.new()
		DialogueLayout.apply_panel_offsets(panel)
		add_child(panel)

		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", DialogueLayout.PANEL_MARGIN)
		pad.add_theme_constant_override("margin_right", DialogueLayout.PANEL_MARGIN)
		pad.add_theme_constant_override("margin_top", DialogueLayout.PANEL_MARGIN - 4)
		pad.add_theme_constant_override("margin_bottom", DialogueLayout.PANEL_MARGIN - 4)
		panel.add_child(pad)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", DialogueLayout.PANEL_SEPARATION)
		pad.add_child(col)
		_speaker = Label.new()
		_speaker.add_theme_font_size_override("font_size", DialogueLayout.FONT_SPEAKER)
		_speaker.add_theme_color_override("font_color", Color("#7eb8ff"))
		col.add_child(_speaker)
		_body = Label.new()
		_body.add_theme_font_size_override("font_size", DialogueLayout.FONT_BODY)
		_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(_body)
		_btn = Button.new()
		_btn.text = "继续 (空格/点击)"
		col.add_child(_btn)
		_btn.pressed.connect(advance)
		_show_current_line()

	func advance() -> void:
		_idx += 1
		_show_current_line()

	func _show_current_line() -> void:
		if _idx >= _lines.size():
			closed.emit(self)
			if _on_done.is_valid():
				_on_done.call()
			queue_free()
			return
		var line: Dictionary = _lines[_idx]
		_speaker.text = str(line.get("speaker", ""))
		_body.text = str(line.get("text", ""))


func _complete(result: Dictionary = {}) -> void:
	finished.emit(result)
