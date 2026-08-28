extends Control

signal finished(result)
signal fan_cycle_completed(result)

const FanGestureDetectorScript := preload("res://levels/minigames/fan_gesture_detector.gd")

const VIEW_SIZE := Vector2(1280.0, 720.0)
const MAX_LENGTH := 120
const INTERFERENCE_ENTITY_COUNT := 12
const MAX_INTERFERENCE_WAVES := 2
const NEXT_WAVE_CHARACTER_STEP := 8
const GATHER_DURATION := 1.35
const DISPERSE_DURATION := 0.62
const RESUME_DELAY := 0.18
const COLOR_BG := Color("05070c")
const COLOR_PANEL := Color("111827f2")
const COLOR_BORDER := Color("7598b8")
const COLOR_TEXT := Color("edf1f7")
const COLOR_MUTED := Color("9aa8ba")
const COLOR_ACCENT := Color("a8d8ff")
const COLOR_ERROR := Color("f0a6a6")
const INTERFERENCE_PHRASES := [
	"这样不好吗",
	"别跑这么远",
	"恭喜你被录用了",
	"可是我们要结婚……",
]
const INTERFERENCE_COLORS := [
	Color("eb6873"),
	Color("70a8ff"),
	Color("ca7af5"),
	Color("f5b85c"),
	Color("74dab5"),
]
const INTERFERENCE_TARGETS := [
	Vector2(350.0, 178.0),
	Vector2(520.0, 205.0),
	Vector2(710.0, 182.0),
	Vector2(870.0, 218.0),
	Vector2(255.0, 310.0),
	Vector2(430.0, 285.0),
	Vector2(745.0, 300.0),
	Vector2(955.0, 326.0),
	Vector2(330.0, 455.0),
	Vector2(510.0, 430.0),
	Vector2(715.0, 450.0),
	Vector2(900.0, 420.0),
]

enum InterferenceState {
	DORMANT,
	GATHERING,
	BLOCKING,
	DISPERSING,
	CLEARED,
}

var _source := 0
var _input_panel: PanelContainer
var _input: LineEdit
var _submit_button: Button
var _feedback: Label
var _counter: Label
var _interference_layer: Control
var _interference_labels: Array[Label] = []
var _fan_prompt: Label
var _fan_button: Button
var _interference_state := InterferenceState.DORMANT
var _wave_started_count := 0
var _wave_cleared_count := 0
var _next_wave_trigger_length := 1
var _fan_waiting := false
var _fan_animating := false
var _fan_live_spread := 0.0
var _pending_character_count := 0
var _submitted := false
var _finish_emitted := false
var _input_resumed_after_fan := false
var _gather_tween: Tween
var _fan_detector = FanGestureDetectorScript.new()


func setup(scene_def: Dictionary) -> void:
	_source = int(scene_def.get("source", 0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	call_deferred("_focus_input")


func _unhandled_input(event: InputEvent) -> void:
	if not _fan_waiting or _fan_animating:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		if trigger_fan("keyboard"):
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = COLOR_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var title := Label.new()
	title.name = "ContextLine"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -420.0
	title.offset_right = 420.0
	title.offset_top = 72.0
	title.offset_bottom = 122.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", COLOR_MUTED)
	title.add_theme_font_size_override("font_size", 24)
	title.text = "小凌：『因为……』"
	add_child(title)

	_input_panel = PanelContainer.new()
	_input_panel.name = "TextInputPanel"
	_input_panel.set_anchors_preset(Control.PRESET_CENTER)
	_input_panel.offset_left = -450.0
	_input_panel.offset_right = 450.0
	_input_panel.offset_top = -132.0
	_input_panel.offset_bottom = 172.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL
	panel_style.border_color = COLOR_BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(14)
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.shadow_size = 18
	_input_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_input_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 46)
	margin.add_theme_constant_override("margin_right", 46)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 26)
	_input_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 15)
	margin.add_child(column)

	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", COLOR_TEXT)
	prompt.add_theme_font_size_override("font_size", 29)
	prompt.text = "把没说完的话写下来"
	column.add_child(prompt)

	var privacy := Label.new()
	privacy.name = "PrivacyNote"
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	privacy.add_theme_color_override("font_color", COLOR_MUTED)
	privacy.add_theme_font_size_override("font_size", 16)
	privacy.text = "现实的声音会靠近。拨开它们，继续写自己的话。"
	column.add_child(privacy)

	_input = LineEdit.new()
	_input.name = "ReasonInput"
	_input.custom_minimum_size = Vector2(0, 62)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = MAX_LENGTH
	_input.placeholder_text = "例如：我害怕让所有人失望……"
	_input.add_theme_font_size_override("font_size", 22)
	_input.text_changed.connect(_on_text_changed)
	_input.text_submitted.connect(_on_text_submitted)
	column.add_child(_input)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	column.add_child(status_row)

	_feedback = Label.new()
	_feedback.name = "Feedback"
	_feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_feedback.add_theme_color_override("font_color", COLOR_MUTED)
	_feedback.add_theme_font_size_override("font_size", 16)
	_feedback.text = "开始输入后，杂念会从四周靠近"
	status_row.add_child(_feedback)

	_counter = Label.new()
	_counter.name = "CharacterCounter"
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.add_theme_color_override("font_color", COLOR_MUTED)
	_counter.add_theme_font_size_override("font_size", 16)
	_counter.text = "0 / %d" % MAX_LENGTH
	status_row.add_child(_counter)

	var button_center := CenterContainer.new()
	button_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(button_center)

	_submit_button = Button.new()
	_submit_button.name = "SubmitButton"
	_submit_button.custom_minimum_size = Vector2(210, 50)
	_submit_button.disabled = true
	_submit_button.add_theme_color_override("font_color", COLOR_TEXT)
	_submit_button.add_theme_color_override("font_hover_color", COLOR_ACCENT)
	_submit_button.add_theme_font_size_override("font_size", 20)
	_submit_button.text = "说出来"
	_submit_button.pressed.connect(_on_submit_pressed)
	button_center.add_child(_submit_button)

	_build_interference_layer()


func _build_interference_layer() -> void:
	_interference_layer = Control.new()
	_interference_layer.name = "InterferenceLayer"
	_interference_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_interference_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interference_layer.z_index = 20
	_interference_layer.visible = false
	add_child(_interference_layer)

	for index in range(INTERFERENCE_ENTITY_COUNT):
		var phrase := Label.new()
		phrase.name = "InterferencePhrase%02d" % (index + 1)
		phrase.text = INTERFERENCE_PHRASES[index % INTERFERENCE_PHRASES.size()]
		phrase.add_theme_color_override("font_color", INTERFERENCE_COLORS[index % INTERFERENCE_COLORS.size()])
		phrase.add_theme_font_size_override("font_size", 30 + (index * 7) % 13)
		phrase.mouse_filter = Control.MOUSE_FILTER_IGNORE
		phrase.modulate.a = 0.0
		_interference_layer.add_child(phrase)
		_interference_labels.append(phrase)

	_fan_prompt = Label.new()
	_fan_prompt.name = "FanPrompt"
	_fan_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fan_prompt.offset_left = -500.0
	_fan_prompt.offset_right = 500.0
	_fan_prompt.offset_top = 548.0
	_fan_prompt.offset_bottom = 588.0
	_fan_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fan_prompt.add_theme_color_override("font_color", COLOR_TEXT)
	_fan_prompt.add_theme_font_size_override("font_size", 21)
	_interference_layer.add_child(_fan_prompt)

	_fan_button = Button.new()
	_fan_button.name = "FanPreviewButton"
	_fan_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fan_button.offset_left = -130.0
	_fan_button.offset_right = 130.0
	_fan_button.offset_top = 605.0
	_fan_button.offset_bottom = 661.0
	_fan_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_fan_button.add_theme_font_size_override("font_size", 18)
	_fan_button.text = "预览 Fan（F）"
	_fan_button.pressed.connect(func() -> void: trigger_fan("button"))
	_interference_layer.add_child(_fan_button)


func _focus_input() -> void:
	if _input != null and not _submitted and _input.editable:
		_input.grab_focus()


func _on_text_changed(next_text: String) -> void:
	if _submitted:
		return
	_counter.text = "%d / %d" % [next_text.length(), MAX_LENGTH]
	var normalized := next_text.strip_edges()
	if (
		not normalized.is_empty()
		and _wave_started_count < MAX_INTERFERENCE_WAVES
		and next_text.length() >= _next_wave_trigger_length
		and _interference_state in [InterferenceState.DORMANT, InterferenceState.CLEARED]
	):
		_start_interference_wave()
	_refresh_input_status(normalized)


func _refresh_input_status(normalized_text := "") -> void:
	if _submitted:
		return
	var normalized := normalized_text if not normalized_text.is_empty() else _input.text.strip_edges()
	var interference_active := _interference_state in [
		InterferenceState.GATHERING,
		InterferenceState.BLOCKING,
		InterferenceState.DISPERSING,
	]
	_submit_button.disabled = normalized.is_empty() or interference_active or _wave_cleared_count == 0
	_feedback.add_theme_color_override("font_color", COLOR_MUTED)
	if normalized.is_empty():
		_feedback.text = "开始输入后，杂念会从四周靠近"
	elif _interference_state == InterferenceState.GATHERING:
		_feedback.text = "杂念正在靠近……可以继续写，也可以开始挥扫"
	elif _interference_state == InterferenceState.BLOCKING:
		_feedback.add_theme_color_override("font_color", COLOR_ERROR)
		_feedback.text = "杂念堵住了输入。先用 Fan 把它们拨开"
	elif _interference_state == InterferenceState.DISPERSING:
		_feedback.text = "正在把这些声音挥出去……"
	elif _wave_cleared_count > 0:
		_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
		_feedback.text = "杂念被拨开了。继续写，或按 Enter 说出来"
	else:
		_feedback.text = "继续写"


func _on_text_submitted(_value: String) -> void:
	_attempt_submit()


func _on_submit_pressed() -> void:
	_attempt_submit()


func _attempt_submit() -> bool:
	if _submitted or _input == null:
		return false
	var answer := _input.text.strip_edges()
	if answer.is_empty():
		_feedback.add_theme_color_override("font_color", COLOR_ERROR)
		_feedback.text = "这句还空着。至少写下一个字。"
		_input.grab_focus()
		return false
	if _interference_state in [InterferenceState.GATHERING, InterferenceState.BLOCKING, InterferenceState.DISPERSING]:
		_feedback.add_theme_color_override("font_color", COLOR_ERROR)
		_feedback.text = "这些声音还挡在这里。先把它们拨开。"
		return false
	if _wave_cleared_count == 0:
		_start_interference_wave()
		_refresh_input_status(answer)
		return false

	_submitted = true
	_input.editable = false
	_submit_button.disabled = true
	_pending_character_count = answer.length()
	_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
	_feedback.text = "你把自己的声音写完了。"
	call_deferred("_finish_submission_after_pause")
	return true


func _start_interference_wave() -> void:
	if _submitted or _wave_started_count >= MAX_INTERFERENCE_WAVES:
		return
	if _interference_state in [InterferenceState.GATHERING, InterferenceState.BLOCKING, InterferenceState.DISPERSING]:
		return
	_wave_started_count += 1
	_interference_state = InterferenceState.GATHERING
	_fan_waiting = true
	_fan_animating = false
	_fan_live_spread = 0.0
	_fan_detector.reset()
	_interference_layer.visible = true
	_fan_button.disabled = false
	_fan_prompt.text = "杂念正在靠近 · 张开手掌，水平往返挥扫"

	for index in range(_interference_labels.size()):
		var phrase := _interference_labels[index]
		phrase.visible = true
		phrase.reset_size()
		phrase.position = _interference_start_position(index, phrase.size)
		phrase.rotation = -0.10 if index % 2 == 0 else 0.10
		phrase.scale = Vector2(0.88, 0.88)
		phrase.modulate.a = 0.12

	_gather_tween = create_tween().set_parallel(true)
	_gather_tween.set_trans(Tween.TRANS_QUART)
	_gather_tween.set_ease(Tween.EASE_OUT)
	for index in range(_interference_labels.size()):
		var phrase := _interference_labels[index]
		_gather_tween.tween_property(phrase, "position", INTERFERENCE_TARGETS[index], GATHER_DURATION)
		_gather_tween.tween_property(phrase, "rotation", -0.025 if index % 2 == 0 else 0.025, GATHER_DURATION)
		_gather_tween.tween_property(phrase, "scale", Vector2.ONE, GATHER_DURATION)
		_gather_tween.tween_property(phrase, "modulate:a", 0.78 + float(index % 3) * 0.07, GATHER_DURATION)
	_gather_tween.finished.connect(_on_interference_gathered.bind(_wave_started_count))


func _interference_start_position(index: int, phrase_size: Vector2) -> Vector2:
	var lane := index / 4
	match index % 4:
		0:
			return Vector2(-phrase_size.x - 90.0, 150.0 + float(lane) * 165.0)
		1:
			return Vector2(VIEW_SIZE.x + 90.0, 170.0 + float(lane) * 150.0)
		2:
			return Vector2(260.0 + float(lane) * 315.0, -phrase_size.y - 70.0)
		_:
			return Vector2(300.0 + float(lane) * 300.0, VIEW_SIZE.y + 70.0)


func _on_interference_gathered(wave_number: int) -> void:
	if wave_number != _wave_started_count or _interference_state != InterferenceState.GATHERING:
		return
	_interference_state = InterferenceState.BLOCKING
	_input.editable = false
	_input.release_focus()
	_fan_prompt.text = "杂念堵住了输入 · 用 Fan 把它们拨开"
	_refresh_input_status()


func ingest_hand_sample(palm_position: Variant, open_palm: bool, timestamp: float) -> Dictionary:
	var fan_update: Dictionary = _fan_detector.update(palm_position, open_palm, timestamp)
	ingest_fan_update(fan_update)
	return fan_update


func ingest_gesture(gesture_name: String) -> bool:
	if gesture_name.strip_edges().to_lower() != "fan":
		return false
	return trigger_fan("gesture")


func ingest_fan_update(fan_update: Dictionary) -> bool:
	if str(fan_update.get("event", "")).to_lower() != "fan_update":
		return false
	if not _fan_waiting or _fan_animating:
		return false

	var state := str(fan_update.get("state", "TRACKING"))
	var direction := str(fan_update.get("direction", "center"))
	var sweep_count := maxi(0, int(fan_update.get("sweep_count", 0)))
	var strength := clampf(float(fan_update.get("strength", 0.0)), 0.0, 1.0)
	_update_fan_prompt(state, direction, sweep_count)
	_preview_interference_force(strength, sweep_count)

	if bool(fan_update.get("completed", false)) or sweep_count >= FanGestureDetectorScript.MIN_SWEEPS_FOR_SUCCESS:
		return trigger_fan("opencv")
	return true


func _update_fan_prompt(state: String, direction: String, sweep_count: int) -> void:
	match state:
		"PALM_ARMING":
			_fan_prompt.text = "张开手掌，稳住……"
		"FAN_READY":
			_fan_prompt.text = "开始水平挥扫。"
		"FANNING":
			var direction_text := "向右" if direction == "right" else "向左"
			_fan_prompt.text = "%s · 有效换向 %d / %d" % [direction_text, sweep_count, FanGestureDetectorScript.MIN_SWEEPS_FOR_SUCCESS]
		_:
			_fan_prompt.text = "张开手掌，水平往返挥扫"


func _preview_interference_force(strength: float, sweep_count: int) -> void:
	if _interference_state != InterferenceState.BLOCKING:
		return
	var next_spread := clampf(18.0 + strength * 92.0 + float(sweep_count) * 38.0, 0.0, 190.0)
	_fan_live_spread = maxf(_fan_live_spread, next_spread)
	var center: Vector2 = VIEW_SIZE * 0.5
	for index in range(_interference_labels.size()):
		var target_origin: Vector2 = INTERFERENCE_TARGETS[index]
		var outward: Vector2 = (target_origin - center).normalized()
		if outward.length_squared() <= 0.001:
			outward = Vector2.LEFT if index % 2 == 0 else Vector2.RIGHT
		_interference_labels[index].position = target_origin + outward * _fan_live_spread


func trigger_fan(trigger_source := "preview") -> bool:
	if not _fan_waiting or _fan_animating:
		return false
	_fan_waiting = false
	_fan_animating = true
	_interference_state = InterferenceState.DISPERSING
	_fan_button.disabled = true
	if _gather_tween != null and _gather_tween.is_valid():
		_gather_tween.kill()
	call_deferred("_play_interference_dispersion", trigger_source)
	return true


func _play_interference_dispersion(trigger_source: String) -> void:
	_fan_prompt.text = "把这些声音挥出去。"
	var center: Vector2 = VIEW_SIZE * 0.5
	var fan_out := create_tween().set_parallel(true)
	fan_out.set_trans(Tween.TRANS_QUART)
	fan_out.set_ease(Tween.EASE_IN)
	for index in range(_interference_labels.size()):
		var phrase := _interference_labels[index]
		var outward: Vector2 = (phrase.position - center).normalized()
		if outward.length_squared() <= 0.001:
			outward = Vector2.LEFT if index % 2 == 0 else Vector2.RIGHT
		var target: Vector2 = phrase.position + outward * (900.0 + float(index % 4) * 70.0)
		fan_out.tween_property(phrase, "position", target, DISPERSE_DURATION)
		fan_out.tween_property(phrase, "rotation", outward.x * 0.22, DISPERSE_DURATION)
		fan_out.tween_property(phrase, "scale", Vector2(1.10, 1.10), DISPERSE_DURATION)
		fan_out.tween_property(phrase, "modulate:a", 0.0, DISPERSE_DURATION)
	await fan_out.finished

	for phrase in _interference_labels:
		phrase.visible = false
	_wave_cleared_count += 1
	_interference_state = InterferenceState.CLEARED
	_fan_animating = false
	_interference_layer.visible = false
	_input_resumed_after_fan = true
	var fan_result := {
		"gesture": "Fan",
		"trigger_source": trigger_source,
		"wave": _wave_cleared_count,
		"interference_entity_count": INTERFERENCE_ENTITY_COUNT,
		"player_text_included": false,
	}
	fan_cycle_completed.emit(fan_result)
	await get_tree().create_timer(RESUME_DELAY).timeout
	_resume_input_after_fan()


func _resume_input_after_fan() -> void:
	if _submitted:
		return
	_input.editable = true
	_next_wave_trigger_length = _input.text.length() + NEXT_WAVE_CHARACTER_STEP
	_refresh_input_status()
	call_deferred("_focus_input")


func _finish_submission_after_pause() -> void:
	await get_tree().create_timer(0.24).timeout
	if _finish_emitted:
		return
	_finish_emitted = true
	# 玩家原文与杂念均不进入 result，避免宿主把私人输入写入 runtime.log。
	finished.emit({
		"result": "success",
		"submitted": true,
		"character_count": _pending_character_count,
		"source": _source,
		"private_text_logged": false,
		"intrusive_text_logged": false,
		"fan_cycle_completed": _wave_cleared_count > 0,
		"interference_waves_cleared": _wave_cleared_count,
		"interference_entity_count": INTERFERENCE_ENTITY_COUNT,
		"input_resumed_after_fan": _input_resumed_after_fan,
	})


func verify_contract() -> bool:
	var phrase_counts: Dictionary = {}
	for phrase in _interference_labels:
		phrase_counts[phrase.text] = int(phrase_counts.get(phrase.text, 0)) + 1
	return (
		_input != null
		and _submit_button != null
		and _feedback != null
		and _counter != null
		and _interference_layer != null
		and _fan_prompt != null
		and _fan_button != null
		and _interference_labels.size() == INTERFERENCE_ENTITY_COUNT
		and phrase_counts.size() == INTERFERENCE_PHRASES.size()
		and _input.max_length == MAX_LENGTH
		and _input.editable
		and _submit_button.disabled
		and not _input.placeholder_text.is_empty()
		and not _interference_layer.visible
	)


func debug_submit_for_verification(text: String) -> bool:
	if _input == null:
		return false
	_input.text = text
	_on_text_changed(text)
	return _attempt_submit()


func debug_set_text_for_verification(text: String) -> int:
	if _input == null:
		return -1
	_input.text = text
	_on_text_changed(_input.text)
	return _input.text.length()


func is_waiting_for_fan() -> bool:
	return _fan_waiting


func is_interference_active() -> bool:
	return _interference_state in [InterferenceState.GATHERING, InterferenceState.BLOCKING, InterferenceState.DISPERSING]


func is_input_editable() -> bool:
	return _input != null and _input.editable


func get_wave_started_count() -> int:
	return _wave_started_count


func get_wave_cleared_count() -> int:
	return _wave_cleared_count


func get_interference_phrases() -> PackedStringArray:
	var phrases := PackedStringArray()
	for phrase in _interference_labels:
		phrases.append(phrase.text)
	return phrases


func are_interference_entities_entering_from_edges() -> bool:
	if not is_interference_active() or _interference_labels.is_empty():
		return false
	for phrase in _interference_labels:
		if (
			phrase.position.x < 0.0
			or phrase.position.x > VIEW_SIZE.x
			or phrase.position.y < 0.0
			or phrase.position.y > VIEW_SIZE.y
		):
			return true
	return false
