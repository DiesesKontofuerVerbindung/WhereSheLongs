extends Control

## 机制 7 · BlinkInteraction（眨眼互动）
##
## 位置：DOCX 第 360 行，入口场景《剧情图-两个手松开的特写》。
## 主题：梦境崩塌与失去连接。
##
## 交互：按住 Space / Enter / 鼠标左键 = 闭眼，松开 = 睁眼。
## 单次点击也会完整走完一次闭眼—睁眼，保证键盘、鼠标、触控都能继续。
##
## 边界（见 docs/handoffs/07_BLINK_INTERACTION_HANDOFF.md）：
## - 模块内部只做闭眼遮罩与轻微局部漂移，不创建第二套全局相机抖动，
##   也不在退出时复位主流程的 shake 状态。
## - 全程使用 1280x720 逻辑坐标与 anchors 布局，渲染像素密度由宿主控制。
## - 不使用高频白闪；所有明暗变化均走 >= 0.25 秒的缓动。
## - finished 只发射一次。

signal finished(result: Dictionary)

const VIEW_SIZE := Vector2(1280.0, 720.0)

enum Phase {
	ENTER,
	IDLE,
	CLOSING,
	CLOSED,
	OPENING,
	SETTLING,
	DONE,
}

const REQUIRED_BLINKS := 1
const ENTER_DURATION := 0.45
const CLOSE_DURATION := 0.40
const MIN_DARK_HOLD := 0.16
const OPEN_DURATION := 0.45
const SETTLE_DURATION := 0.32
const IDLE_FALLBACK_SEC := 25.0
const HINT_AFTER_CLOSED_SEC := 1.20

const GRIP_AFTER_ENTER := 0.58
const GRIP_WHILE_CLOSED := 0.14
const GRIP_RELEASED := 0.0

const COLOR_BG_TOP := Color("0b1019")
const COLOR_BG_BOTTOM := Color("03050a")
const COLOR_LID := Color("04060b")
const COLOR_LID_EDGE := Color("1d222b")
const COLOR_TEXT := Color("dfe6f0")
const COLOR_MUTED := Color("8d97a8")

const PROMPT_IDLE := "按住 Space 或鼠标左键 · 闭上眼睛"
const PROMPT_CLOSED := "……"
const HINT_IDLE := "按住不放，可以在黑里多停一会儿"
const HINT_RELEASE := "松开，睁开眼睛"
const CLOSED_TEXT := "梦境正在断裂"

var _phase := Phase.ENTER
var _source := 0
var _close_progress := 0.0
var _grip := 1.0
var _fade := 1.0
var _blinks := 0
var _finish_emitted := false
var _auto_blink := false
var _holding := false
var _release_requested := false
var _closed_elapsed := 0.0
var _idle_elapsed := 0.0
var _breath := 0.0

var _world: _WorldCanvas
var _lid: _LidCanvas
var _prompt_label: Label
var _closed_label: Label
var _hint_label: Label
var _active_tween: Tween


func setup(event: Dictionary) -> void:
	_source = int(event.get("source", 0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layers()
	_start_enter()


func _build_layers() -> void:
	_world = _WorldCanvas.new()
	_world.name = "BlinkWorld"
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world.z_index = 0
	add_child(_world)

	_lid = _LidCanvas.new()
	_lid.name = "BlinkLids"
	_lid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lid.z_index = 5
	add_child(_lid)

	_prompt_label = _make_label(24, COLOR_TEXT)
	_prompt_label.name = "BlinkPrompt"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt_label.offset_left = -430.0
	_prompt_label.offset_right = 430.0
	_prompt_label.offset_top = 96.0
	_prompt_label.offset_bottom = 138.0
	_prompt_label.z_index = 10
	_prompt_label.text = PROMPT_IDLE
	add_child(_prompt_label)

	_closed_label = _make_label(30, COLOR_MUTED)
	_closed_label.name = "BlinkClosedText"
	_closed_label.set_anchors_preset(Control.PRESET_CENTER)
	_closed_label.offset_left = -430.0
	_closed_label.offset_right = 430.0
	_closed_label.offset_top = -26.0
	_closed_label.offset_bottom = 34.0
	_closed_label.z_index = 10
	_closed_label.text = CLOSED_TEXT
	add_child(_closed_label)

	_hint_label = _make_label(17, COLOR_MUTED)
	_hint_label.name = "BlinkHint"
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.offset_left = -430.0
	_hint_label.offset_right = 430.0
	_hint_label.offset_top = -96.0
	_hint_label.offset_bottom = -64.0
	_hint_label.z_index = 10
	_hint_label.text = HINT_IDLE
	add_child(_hint_label)

	_sync_layers()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _start_enter() -> void:
	_phase = Phase.ENTER
	_grip = 1.0
	_tween_grip(GRIP_AFTER_ENTER, ENTER_DURATION, Tween.TRANS_QUAD, Tween.EASE_OUT)
	(_active_tween as Tween).finished.connect(func() -> void:
		if _phase == Phase.ENTER:
			_phase = Phase.IDLE
	)


func _tween_grip(target: float, duration: float, trans: Tween.TransitionType, ease: Tween.EaseType) -> void:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.set_trans(trans)
	_active_tween.set_ease(ease)
	_active_tween.tween_method(_set_grip, _grip, target, duration)


func _set_grip(value: float) -> void:
	_grip = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	_breath += delta
	if _phase == Phase.ENTER or _phase == Phase.IDLE:
		_idle_elapsed += delta
		if _idle_elapsed >= IDLE_FALLBACK_SEC:
			_idle_elapsed = 0.0
			_auto_blink = true
			_begin_close()
	if _phase == Phase.CLOSED:
		_closed_elapsed += delta
	if _phase == Phase.CLOSING or _phase == Phase.CLOSED:
		_close_progress = clampf(_close_progress, 0.0, 1.0)
	_sync_layers()
	queue_redraw()


func _sync_layers() -> void:
	_world.grip = _grip
	_world.fade = _fade
	_world.breath = _breath
	_world.drift = _current_drift()
	_lid.close_progress = _close_progress
	_lid.queue_redraw()
	_world.queue_redraw()

	var closed_amount := clampf((_close_progress - 0.55) / 0.45, 0.0, 1.0)
	var open_amount := 1.0 - clampf(_close_progress / 0.45, 0.0, 1.0)
	_apply_label_alpha(_prompt_label, open_amount)
	_apply_label_alpha(_hint_label, open_amount)
	_apply_label_alpha(_closed_label, closed_amount * 0.62)

	match _phase:
		Phase.ENTER, Phase.IDLE:
			_prompt_label.text = PROMPT_IDLE
			_hint_label.text = HINT_IDLE
		Phase.CLOSING, Phase.CLOSED:
			_prompt_label.text = PROMPT_CLOSED
			_hint_label.text = HINT_RELEASE if _closed_elapsed >= HINT_AFTER_CLOSED_SEC else ""
		_:
			_prompt_label.text = ""
			_hint_label.text = ""


func _apply_label_alpha(label: Label, alpha: float) -> void:
	label.modulate.a = clampf(alpha, 0.0, 1.0)
	label.visible = label.modulate.a > 0.01


func _current_drift() -> Vector2:
	# 轻微局部漂移：低频、可预测，幅度不超过 4 逻辑像素，绝不与主流程的全局抖动叠加。
	var closing_weight := 0.35 + _close_progress * 0.4
	return Vector2(
		sin(_breath * 0.62) * 3.4 * closing_weight,
		cos(_breath * 0.47) * 2.6 * closing_weight
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_begin_close()
		else:
			_release_close()
		accept_event()
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin_close()
		else:
			_release_close()
		accept_event()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_SPACE and key_event.keycode != KEY_ENTER and key_event.keycode != KEY_KP_ENTER:
		return
	if key_event.echo:
		return
	if key_event.pressed:
		_begin_close()
	else:
		_release_close()
	get_viewport().set_input_as_handled()


func _begin_close() -> void:
	if _finish_emitted:
		return
	if _phase == Phase.ENTER:
		if _active_tween != null and _active_tween.is_valid():
			_active_tween.kill()
	elif _phase != Phase.IDLE:
		return
	if _holding:
		return
	_holding = true
	_release_requested = false
	_closed_elapsed = 0.0
	_phase = Phase.CLOSING
	_tween_grip(GRIP_WHILE_CLOSED, CLOSE_DURATION, Tween.TRANS_CUBIC, Tween.EASE_IN)
	var close_tween := create_tween()
	close_tween.set_trans(Tween.TRANS_CUBIC)
	close_tween.set_ease(Tween.EASE_IN)
	close_tween.tween_property(self, "_close_progress", 1.0, CLOSE_DURATION)
	close_tween.tween_callback(_on_fully_closed)


func _on_fully_closed() -> void:
	_close_progress = 1.0
	_phase = Phase.CLOSED
	_blinks += 1
	if _release_requested:
		_schedule_open()


func _release_close() -> void:
	if not _holding:
		return
	_holding = false
	_release_requested = true
	if _phase == Phase.CLOSED:
		_schedule_open()


func _schedule_open() -> void:
	_release_requested = false
	# 闭眼过短会让睁眼看起来像闪烁；不足 MIN_DARK_HOLD 时先补一段停顿。
	var wait := maxf(0.0, MIN_DARK_HOLD - _closed_elapsed)
	if wait <= 0.0:
		_open_start()
		return
	var timer := get_tree().create_timer(wait)
	timer.timeout.connect(_open_start, CONNECT_ONE_SHOT)


func _open_start() -> void:
	if _finish_emitted or _phase == Phase.OPENING or _phase == Phase.SETTLING:
		return
	_phase = Phase.OPENING
	_tween_grip(GRIP_RELEASED, OPEN_DURATION, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var open_tween := create_tween()
	open_tween.set_trans(Tween.TRANS_QUAD)
	open_tween.set_ease(Tween.EASE_OUT)
	open_tween.tween_property(self, "_close_progress", 0.0, OPEN_DURATION)
	open_tween.tween_callback(_on_fully_open)


func _on_fully_open() -> void:
	_close_progress = 0.0
	if _blinks >= REQUIRED_BLINKS:
		_fade = 0.0
		_phase = Phase.SETTLING
		var settle_timer := get_tree().create_timer(SETTLE_DURATION)
		settle_timer.timeout.connect(_emit_finished.bind(false), CONNECT_ONE_SHOT)
	else:
		_phase = Phase.IDLE
		_idle_elapsed = 0.0


func _emit_finished(auto: bool) -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	_phase = Phase.DONE
	_auto_blink = _auto_blink or auto
	finished.emit({
		"result": "success",
		"blinks": _blinks,
		"source": _source,
		"auto_blink": _auto_blink,
	})


# ---------------------------------------------------------------------------
# 测试与宿主契约接口
# ---------------------------------------------------------------------------

func verify_contract() -> bool:
	if not is_control_layout_ready():
		return false
	if not has_signal("finished") or not has_method("setup"):
		return false
	if _lid == null or _world == null or _prompt_label == null:
		return false
	if not _lid.size.is_equal_approx(VIEW_SIZE):
		return false
	if not _world.size.is_equal_approx(VIEW_SIZE):
		return false
	if not _prompt_label.get_rect().encloses(Rect2()) and _prompt_label.get_rect().size.x > VIEW_SIZE.x:
		return false
	if CLOSE_DURATION < 0.25 or CLOSE_DURATION > 0.5 or OPEN_DURATION < 0.25 or OPEN_DURATION > 0.5:
		return false
	if REQUIRED_BLINKS != 1:
		return false
	if _prompt_label.anchor_left != 0.5 or _prompt_label.anchor_right != 0.5:
		return false
	if _hint_label.anchor_left != 0.5 or _hint_label.anchor_right != 0.5:
		return false
	if _closed_label.anchor_left != 0.5 or _closed_label.anchor_right != 0.5:
		return false
	return true


func is_control_layout_ready() -> bool:
	if not is_equal_approx(anchor_right, 1.0) or not is_equal_approx(anchor_bottom, 1.0):
		return false
	return size.is_equal_approx(VIEW_SIZE)


func get_timing_profile() -> Dictionary:
	return {
		"enter": ENTER_DURATION,
		"close": CLOSE_DURATION,
		"min_dark_hold": MIN_DARK_HOLD,
		"open": OPEN_DURATION,
		"settle": SETTLE_DURATION,
		"idle_fallback": IDLE_FALLBACK_SEC,
		"required_blinks": REQUIRED_BLINKS,
	}


func get_phase_name() -> String:
	return Phase.keys()[_phase]


func get_phase() -> int:
	return _phase


func get_close_progress() -> float:
	return _close_progress


func get_blink_count() -> int:
	return _blinks


func get_grip() -> float:
	return _grip


func is_eyes_closed() -> bool:
	return _phase == Phase.CLOSED


func is_holding() -> bool:
	return _holding


func is_finished() -> bool:
	return _finish_emitted


func get_lid_rect() -> Rect2:
	return _lid.get_rect() if _lid != null else Rect2()


func get_world_rect() -> Rect2:
	return _world.get_rect() if _world != null else Rect2()


func get_prompt_rect() -> Rect2:
	return _prompt_label.get_rect() if _prompt_label != null else Rect2()


func get_hint_rect() -> Rect2:
	return _hint_label.get_rect() if _hint_label != null else Rect2()


func debug_begin_close() -> bool:
	if _finish_emitted or _holding:
		return false
	if _phase != Phase.ENTER and _phase != Phase.IDLE:
		return false
	_begin_close()
	return true


func debug_release_close() -> bool:
	if not _holding:
		return false
	_release_close()
	return true


class _WorldCanvas extends Control:
	var grip := 1.0
	var fade := 1.0
	var breath := 0.0
	var drift := Vector2.ZERO

	const REF_W := 1280.0
	const REF_H := 720.0
	const COLOR_SKIN := Color("6a5c50")
	const COLOR_SKIN_EDGE := Color("9d8b7a")
	const COLOR_WARM := Color("f0c07a")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		var scale_factor := minf(size.x / REF_W, size.y / REF_H)
		var offset := (size - Vector2(REF_W, REF_H) * scale_factor) * 0.5
		draw_set_transform(offset, 0.0, Vector2(scale_factor, scale_factor))
		_draw_background()
		var alpha := clampf(grip / 0.60, 0.0, 1.0) * clampf(fade, 0.0, 1.0)
		if alpha <= 0.002:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		_draw_warm_light(alpha)
		_draw_arms(alpha)
		_draw_hand(Vector2(0.0, 0.0), 1.0, alpha)
		_draw_hand(Vector2(0.0, 0.0), -1.0, alpha)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_background() -> void:
		var bands := 24
		var band_height := REF_H / float(bands)
		for i in range(bands):
			var t := float(i) / float(bands - 1)
			var color := COLOR_BG_TOP.lerp(COLOR_BG_BOTTOM, t)
			draw_rect(Rect2(0.0, float(i) * band_height, REF_W, band_height + 1.0), color)

	func _draw_warm_light(alpha: float) -> void:
		var center := Vector2(REF_W * 0.5, REF_H * 0.545) + drift
		var pulse := 0.86 + sin(breath * 1.15) * 0.14
		var strength := pow(clampf(grip, 0.0, 1.0), 1.6) * alpha * pulse
		if strength <= 0.002:
			return
		var layers := [
			{"r": 150.0, "a": 0.020},
			{"r": 112.0, "a": 0.030},
			{"r": 82.0, "a": 0.042},
			{"r": 54.0, "a": 0.055},
			{"r": 30.0, "a": 0.070},
		]
		for layer in layers:
			draw_circle(center, float(layer["r"]), Color(COLOR_WARM.r, COLOR_WARM.g, COLOR_WARM.b, float(layer["a"]) * strength))

	func _draw_arms(alpha: float) -> void:
		var drop := (1.0 - grip) * 42.0
		var body_alpha := alpha * 0.92
		var color := Color(COLOR_SKIN.r, COLOR_SKIN.g, COLOR_SKIN.b, body_alpha * 0.85)
		var edge := Color(COLOR_SKIN_EDGE.r, COLOR_SKIN_EDGE.g, COLOR_SKIN_EDGE.b, body_alpha * 0.30)
		var gap := (1.0 - grip) * 46.0
		# 左臂：自画面外伸向左手腕
		var left_wrist := Vector2(REF_W * 0.5 - 118.0 - gap, REF_H * 0.575 + drop) + drift
		_draw_limb(Vector2(-60.0, REF_H * 0.60), left_wrist, 46.0, 34.0, color, edge)
		# 右臂
		var right_wrist := Vector2(REF_W * 0.5 + 118.0 + gap, REF_H * 0.575 + drop) + drift
		_draw_limb(Vector2(REF_W + 60.0, REF_H * 0.60), right_wrist, 46.0, 34.0, color, edge)

	func _draw_limb(from: Vector2, to: Vector2, width_from: float, width_to: float, color: Color, edge: Color) -> void:
		var direction := (to - from).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var polygon := PackedVector2Array([
			from + normal * width_from * 0.5,
			to + normal * width_to * 0.5,
			to - normal * width_to * 0.5,
			from - normal * width_from * 0.5,
		])
		draw_colored_polygon(polygon, color)
		draw_polyline(polygon + PackedVector2Array([polygon[0]]), edge, 1.5, true)

	func _draw_hand(_anchor: Vector2, facing: float, alpha: float) -> void:
		var spread := clampf(1.0 - grip, 0.0, 1.0)
		var drop := (1.0 - grip) * 42.0
		var gap := (1.0 - grip) * 46.0
		var palm := Vector2(REF_W * 0.5 - facing * (118.0 + gap), REF_H * 0.545 + drop) + drift
		var color := Color(COLOR_SKIN.r, COLOR_SKIN.g, COLOR_SKIN.b, alpha * 0.92)
		var edge := Color(COLOR_SKIN_EDGE.r, COLOR_SKIN_EDGE.g, COLOR_SKIN_EDGE.b, alpha * 0.34)

		draw_circle(palm, 47.0, color)
		draw_arc(palm, 47.0, 0.0, TAU, 30, edge, 1.6, true)

		var inward := facing
		for i in range(4):
			var lane := (float(i) - 1.5) / 1.5
			var vertical := lane * 15.0
			var start := palm + Vector2(inward * 16.0, vertical)
			var length := lerpf(104.0, 84.0, spread)
			var tilt := (-0.20 + lane * 0.30) * (1.0 + spread * 0.55)
			var direction := Vector2(inward, tilt).normalized()
			var end := start + direction * length
			draw_line(start, end, color, 19.0 - absf(lane) * 3.2, true)
			draw_circle(end, 9.4 - absf(lane) * 1.5, color)

		var thumb_start := palm + Vector2(inward * 6.0, 32.0)
		var thumb_dir := Vector2(inward, lerpf(0.55, 1.05, spread)).normalized()
		var thumb_end := thumb_start + thumb_dir * 62.0
		draw_line(thumb_start, thumb_end, color, 22.0, true)
		draw_circle(thumb_end, 11.0, color)


class _LidCanvas extends Control:
	var close_progress := 0.0

	const COLOR_LID := Color("04060b")
	const COLOR_LID_EDGE := Color("1d222b")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		if close_progress <= 0.001:
			return
		var width := size.x
		var height := size.y
		var overshoot := height * 0.06
		var lid_height := height * 0.5 * clampf(close_progress, 0.0, 1.0) + overshoot

		var top_polygon := _lid_polygon(lid_height, height, width, true)
		draw_colored_polygon(top_polygon, COLOR_LID)
		draw_polyline(_edge_points(lid_height, height, width, true), Color(COLOR_LID_EDGE.r, COLOR_LID_EDGE.g, COLOR_LID_EDGE.b, 0.45 * close_progress), 2.0, true)

		var bottom_polygon := _lid_polygon(lid_height, height, width, false)
		draw_colored_polygon(bottom_polygon, COLOR_LID)
		draw_polyline(_edge_points(lid_height, height, width, false), Color(COLOR_LID_EDGE.r, COLOR_LID_EDGE.g, COLOR_LID_EDGE.b, 0.45 * close_progress), 2.0, true)

		if close_progress >= 0.86:
			_draw_dream_residue(width, height)

	func _lid_polygon(lid_height: float, height: float, width: float, from_top: bool) -> PackedVector2Array:
		var points := PackedVector2Array()
		var samples := 26
		if from_top:
			points.append(Vector2(0.0, -4.0))
			points.append(Vector2(width, -4.0))
		else:
			points.append(Vector2(0.0, height + 4.0))
			points.append(Vector2(width, height + 4.0))
		for i in range(samples, -1, -1):
			var t := float(i) / float(samples)
			var x := width * t
			var bow := height * 0.055 * (1.0 - 0.35 * close_progress)
			var y := lid_height - bow * sin(PI * t) if from_top else height - lid_height + bow * sin(PI * t)
			points.append(Vector2(x, y))
		return points

	func _edge_points(lid_height: float, height: float, width: float, from_top: bool) -> PackedVector2Array:
		var points := PackedVector2Array()
		var samples := 26
		for i in range(samples + 1):
			var t := float(i) / float(samples)
			var x := width * t
			var bow := height * 0.055 * (1.0 - 0.35 * close_progress)
			var y := lid_height - bow * sin(PI * t) if from_top else height - lid_height + bow * sin(PI * t)
			points.append(Vector2(x, y))
		return points

	func _draw_dream_residue(width: float, height: float) -> void:
		var strength := clampf((close_progress - 0.86) / 0.14, 0.0, 1.0)
		var center := Vector2(width * 0.5, height * 0.5)
		for i in range(5):
			var angle := float(i) * 1.9 + 0.6
			var radius := height * (0.13 + float(i) * 0.045)
			var point := center + Vector2(cos(angle), sin(angle) * 0.62) * radius
			draw_circle(point, height * 0.052, Color(0.42, 0.48, 0.62, 0.030 * strength))
		draw_circle(center, height * 0.30, Color(0.10, 0.12, 0.18, 0.30 * strength))
