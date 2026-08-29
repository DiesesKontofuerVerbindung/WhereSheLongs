extends Control

signal finished(result)

const VIEW_SIZE := Vector2(1280.0, 720.0)
const FIREFLY_COUNT := 5
const HAND_BOTTLE_PATH := "res://assets/scene/hand_bottle_lowpoly.jpg"

## Texture UV of jar center / interior (relative to the hand-bottle image).
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
var _hand_sprite: Sprite2D
var _hand_tex: Texture2D
var _layout_ready := false
var _was_dragging := false


func setup(_scene_def: Dictionary) -> void:
	pass


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 与跑酷/跳石头一样，模块在主舞台中使用固定 1280×720 逻辑坐标；
	# 外层 SubViewport + KEEP_ASPECT_CENTERED 负责窗口分辨率适配。
	custom_minimum_size = VIEW_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_hand_tex = load(HAND_BOTTLE_PATH)
	if _hand_tex == null:
		push_error("Missing hand bottle texture: %s" % HAND_BOTTLE_PATH)
	else:
		_hand_sprite = Sprite2D.new()
		_hand_sprite.texture = _hand_tex
		_hand_sprite.centered = false
		add_child(_hand_sprite)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hint.text = "把星光拖入瓶子内"
	add_child(_hint)

	for i in range(FIREFLY_COUNT):
		var firefly := _LowPolyStar.new()
		firefly.mouse_filter = Control.MOUSE_FILTER_STOP
		firefly.gui_input.connect(_on_firefly_gui_input.bind(i))
		add_child(firefly)
		_fireflies.append(firefly)
		_home_positions.append(Vector2.ZERO)

	# Defer first layout until Control has a real size.
	call_deferred("_apply_responsive_layout")


func _on_resized() -> void:
	if _layout_ready and _dragging_idx < 0 and not _busy:
		_apply_responsive_layout()


func _view_size() -> Vector2:
	return VIEW_SIZE


func _apply_responsive_layout() -> void:
	var view := _view_size()
	var scale_factor := minf(view.x / VIEW_SIZE.x, view.y / VIEW_SIZE.y)
	scale_factor = clampf(scale_factor, 0.45, 2.5)

	_layout_hint(view, scale_factor)
	_layout_hand_bottle(view)
	_layout_fireflies(view, scale_factor)
	_layout_ready = true


func _layout_hint(view: Vector2, scale_factor: float) -> void:
	if _hint == null:
		return
	_hint.offset_top = view.y * 0.035
	_hint.offset_bottom = view.y * 0.035 + maxf(28.0, 36.0 * scale_factor)
	_hint.add_theme_font_size_override("font_size", int(round(20.0 * scale_factor)))


func _layout_hand_bottle(view: Vector2) -> void:
	if _hand_sprite == null or _hand_tex == null:
		return

	var tex_size := Vector2(_hand_tex.get_width(), _hand_tex.get_height())
	# 保留原版 1280×720 下约 620px 的图片宽度，再按窗口等比缩放；
	# 不能按瓶内区域反推整张手部图，否则手部会被放大到铺满画面。
	var viewport_scale := minf(view.x / 1280.0, view.y / 720.0)
	var target_sprite_width := 620.0 * viewport_scale
	var scale := target_sprite_width / tex_size.x
	var jar_center_on_screen := Vector2(view.x * 0.5, view.y * 0.58)
	var sprite_pos := jar_center_on_screen - JAR_CENTER_NORM * tex_size * scale

	_hand_sprite.position = sprite_pos
	_hand_sprite.scale = Vector2(scale, scale)

	_bottle_interior = Rect2(
		sprite_pos + JAR_INTERIOR_NORM.position * tex_size * scale,
		JAR_INTERIOR_NORM.size * tex_size * scale
	)


func _layout_fireflies(view: Vector2, scale_factor: float) -> void:
	var star_size := clampf(64.0 * scale_factor, 36.0, 96.0)
	var margin_x := view.x * 0.08
	var spread := maxf(40.0, view.x - margin_x * 2.0)
	var base_y := view.y * 0.12

	for i in range(_fireflies.size()):
		var firefly := _fireflies[i]
		firefly.custom_minimum_size = Vector2(star_size, star_size)
		firefly.size = Vector2(star_size, star_size)
		firefly.set_star_scale(scale_factor)
		var t := 0.0 if FIREFLY_COUNT <= 1 else float(i) / float(FIREFLY_COUNT - 1)
		var home := Vector2(
			margin_x + spread * t,
			base_y + sin(float(i) * 1.35) * (view.y * 0.04)
		)
		var pos := home - firefly.size * 0.5
		firefly.position = pos
		_home_positions[i] = pos


func _on_firefly_gui_input(event: InputEvent, index: int) -> void:
	if _busy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging_idx = index
			_was_dragging = true
			_drag_offset = _fireflies[index].global_position - get_global_mouse_position()
			_fireflies[index].z_index = 10
		else:
			if _dragging_idx == index:
				_try_capture(index)
				_dragging_idx = -1
				_fireflies[index].z_index = 1
	elif event is InputEventScreenTouch:
		if event.pressed:
			_dragging_idx = index
			_was_dragging = true
			_drag_offset = _fireflies[index].global_position - event.position
			_fireflies[index].z_index = 10
		elif _dragging_idx == index:
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
		_bottle_interior.end.y - fly.size.y * 0.45
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
	var _draw_scale := 1.0

	func set_star_scale(scale_factor: float) -> void:
		_draw_scale = clampf(scale_factor, 0.45, 2.5)
		queue_redraw()

	func _ready() -> void:
		_phase = randf() * TAU
		queue_redraw()

	func _process(delta: float) -> void:
		_phase += delta * 2.6
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.52 + sin(_phase) * 0.38
		var center := size * 0.5
		var s := _draw_scale
		var glow := Color(1.0, 0.90, 0.42)

		# Circular halos — soft concentric rings that pulse with twinkle.
		for layer in [
			{"r": 40.0, "a": 0.04},
			{"r": 34.0, "a": 0.07},
			{"r": 28.0, "a": 0.11},
			{"r": 22.0, "a": 0.16},
			{"r": 16.0, "a": 0.22},
		]:
			draw_circle(center, layer.r * s, glow * Color(1, 1, 1, layer.a * pulse))

		for i in range(6):
			var a0 := TAU * float(i) / 6.0
			var a1 := TAU * float(i + 1) / 6.0
			var tri := PackedVector2Array([
				center,
				center + Vector2(cos(a0), sin(a0)) * 24.0 * s,
				center + Vector2(cos(a1), sin(a1)) * 24.0 * s,
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
				poly.append(center + p * s)
			draw_colored_polygon(poly, colors[i] * Color(1, 1, 1, pulse))
			draw_polyline(
				poly + PackedVector2Array([poly[0]]),
				Color(0.78, 0.62, 0.12, 0.40),
				1.0
			)

		draw_circle(center, 3.5 * s, Color(1.0, 0.96, 0.65, 0.85 * pulse))
