extends Control

signal finished(result)

const DialogueLayout := preload("res://systems/dialogue_layout.gd")
const VIEW_SIZE := DialogueLayout.VIEWPORT
const FIREFLY_COUNT := 5
const HAND_BOTTLE_PATH := "res://assets/scene/hand_bottle_lowpoly.jpg"

const SPRITE_WIDTH := 620.0
const JAR_CENTER_NORM := Vector2(0.30, 0.46)
const JAR_INTERIOR_NORM := Rect2(0.22, 0.24, 0.17, 0.38)

var _fireflies: Array[Control] = []
var _home_positions: Array[Vector2] = []
var _dragging_idx := -1
var _drag_offset := Vector2.ZERO
var _captured_total := 0
var _busy := false
var _hint: Label
var _bottle_interior := Rect2()


func setup(_scene_def: Dictionary) -> void:
	GameState.set_checkpoint("dev_firefly_bottle", "firefly_bottle", Vector2.ZERO)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_add_hand_bottle_sprite()
	_spawn_fireflies()
	_create_hint()


func _add_hand_bottle_sprite() -> void:
	var tex: Texture2D = load(HAND_BOTTLE_PATH)
	if tex == null:
		push_error("Missing hand bottle texture: %s" % HAND_BOTTLE_PATH)
		return

	var tex_size := Vector2(tex.get_width(), tex.get_height())
	var scale := SPRITE_WIDTH / tex_size.x
	var jar_center_on_screen := Vector2(VIEW_SIZE.x * 0.5, VIEW_SIZE.y * 0.56)
	var sprite_pos := jar_center_on_screen - JAR_CENTER_NORM * tex_size * scale

	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = false
	sprite.position = sprite_pos
	sprite.scale = Vector2(scale, scale)
	add_child(sprite)

	_bottle_interior = Rect2(
		sprite_pos + JAR_INTERIOR_NORM.position * tex_size * scale,
		JAR_INTERIOR_NORM.size * tex_size * scale
	)


func _create_hint() -> void:
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 20.0
	_hint.offset_bottom = 56.0
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.text = "把星光拖入瓶子内"
	add_child(_hint)


func _spawn_fireflies() -> void:
	var spread := VIEW_SIZE.x - 180.0
	for i in range(FIREFLY_COUNT):
		var firefly := _LowPolyStar.new()
		firefly.custom_minimum_size = Vector2(64, 64)
		firefly.size = Vector2(64, 64)
		firefly.mouse_filter = Control.MOUSE_FILTER_STOP
		var home := Vector2(
			90.0 + spread * float(i) / float(FIREFLY_COUNT - 1),
			72.0 + sin(float(i) * 1.35) * 22.0
		)
		firefly.position = home - firefly.size * 0.5
		firefly.gui_input.connect(_on_firefly_gui_input.bind(i))
		add_child(firefly)
		move_child(firefly, -1)
		_fireflies.append(firefly)
		_home_positions.append(firefly.position)


func _on_firefly_gui_input(event: InputEvent, index: int) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging_idx = index
			_drag_offset = _fireflies[index].global_position - get_global_mouse_position()
			_fireflies[index].z_index = 10
		else:
			if _dragging_idx == index:
				_try_capture(index)
				_dragging_idx = -1
				_fireflies[index].z_index = 1


func _process(_delta: float) -> void:
	if _dragging_idx >= 0 and not _busy:
		var fly := _fireflies[_dragging_idx]
		fly.global_position = get_global_mouse_position() + _drag_offset
		if _is_inside_bottle(fly):
			_try_capture(_dragging_idx)


func _is_inside_bottle(fly: Control) -> bool:
	var center := fly.position + fly.size * 0.5
	return _bottle_interior.has_point(center)


func _try_capture(index: int) -> void:
	if _busy or index < 0:
		return
	var fly := _fireflies[index]
	if not _is_inside_bottle(fly):
		return
	_busy = true
	_dragging_idx = -1
	fly.z_index = 2
	var target := Vector2(
		_bottle_interior.position.x + _bottle_interior.size.x * 0.5,
		_bottle_interior.end.y - 30.0
	) - fly.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(fly, "position", target, 0.22)
	tween.tween_property(fly, "modulate:a", 0.35, 0.12)
	tween.tween_property(fly, "modulate:a", 1.0, 0.12)
	tween.tween_property(fly, "position", _home_positions[index], 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.finished.connect(func() -> void:
		fly.z_index = 1
		_busy = false
		_captured_total += 1
		if _captured_total >= FIREFLY_COUNT:
			await get_tree().create_timer(0.35).timeout
			finished.emit({"result": "success"})
	)


class _LowPolyStar extends Control:
	var _phase := randf() * TAU

	func _ready() -> void:
		_phase = randf() * TAU
		queue_redraw()

	func _process(delta: float) -> void:
		_phase += delta * 2.6
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.52 + sin(_phase) * 0.38
		var center := size * 0.5
		var glow := Color(1.0, 0.90, 0.42)

		# Circular halos — soft concentric rings that pulse with twinkle.
		for layer in [
			{"r": 40.0, "a": 0.04},
			{"r": 34.0, "a": 0.07},
			{"r": 28.0, "a": 0.11},
			{"r": 22.0, "a": 0.16},
			{"r": 16.0, "a": 0.22},
		]:
			draw_circle(center, layer.r, glow * Color(1, 1, 1, layer.a * pulse))

		for i in range(6):
			var a0 := TAU * float(i) / 6.0
			var a1 := TAU * float(i + 1) / 6.0
			var tri := PackedVector2Array([
				center,
				center + Vector2(cos(a0), sin(a0)) * 24.0,
				center + Vector2(cos(a1), sin(a1)) * 24.0,
			])
			draw_colored_polygon(tri, glow * Color(1, 1, 1, 0.14 * pulse))

		var facets := [
			[Vector2(0, -20), Vector2(-14, -4), Vector2(0, 8)],
			[Vector2(0, -20), Vector2(14, -4), Vector2(0, 8)],
			[Vector2(-14, -4), Vector2(-18, 12), Vector2(0, 8)],
			[Vector2(14, -4), Vector2(18, 12), Vector2(0, 8)],
			[Vector2(-18, 12), Vector2(0, 22), Vector2(18, 12)],
		]
		var colors := [
			Color(1.0, 0.94, 0.52, 0.92),
			Color(0.98, 0.86, 0.38, 0.88),
			Color(0.95, 0.80, 0.32, 0.84),
			Color(1.0, 0.90, 0.45, 0.90),
			Color(0.92, 0.78, 0.28, 0.86),
		]
		for i in range(facets.size()):
			var poly := PackedVector2Array()
			for p in facets[i]:
				poly.append(center + p)
			draw_colored_polygon(poly, colors[i] * Color(1, 1, 1, pulse))
			draw_polyline(
				poly + PackedVector2Array([poly[0]]),
				Color(0.78, 0.62, 0.12, 0.40),
				1.0
			)

		draw_circle(center, 3.5, Color(1.0, 0.96, 0.65, 0.85 * pulse))
