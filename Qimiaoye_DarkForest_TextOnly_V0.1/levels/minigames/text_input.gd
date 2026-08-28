extends Control

signal finished(result)
signal fan_cycle_completed(result)

const FanGestureDetectorScript := preload("res://levels/minigames/fan_gesture_detector.gd")

const VIEW_SIZE := Vector2(1280.0, 720.0)
const MAX_LENGTH := 120
const COLOR_BG := Color("05070c")
const COLOR_PANEL := Color("111827f2")
const COLOR_BORDER := Color("7598b8")
const COLOR_TEXT := Color("edf1f7")
const COLOR_MUTED := Color("9aa8ba")
const COLOR_ACCENT := Color("a8d8ff")
const COLOR_ERROR := Color("f0a6a6")
const FAN_OUT_DURATION := 0.52
const FAN_HOLD_DURATION := 0.28
const FAN_RETURN_DURATION := 0.64
const FAN_SETTLE_DURATION := 0.34

var _source := 0
var _input_panel: PanelContainer
var _input: LineEdit
var _submit_button: Button
var _feedback: Label
var _counter: Label
var _fan_stage: Control
var _fan_prompt: Label
var _fan_left: Label
var _fan_right: Label
var _fan_button: Button
var _fan_left_origin := Vector2.ZERO
var _fan_right_origin := Vector2.ZERO
var _fan_waiting := false
var _fan_animating := false
var _fan_return_error := INF
var _fan_live_spread := 0.0
var _pending_character_count := 0
var _submitted := false
var _finish_emitted := false
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
	title.offset_top = 92.0
	title.offset_bottom = 142.0
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
	_input_panel.offset_top = -150.0
	_input_panel.offset_bottom = 190.0
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
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 32)
	_input_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var prompt := Label.new()
	prompt.name = "Prompt"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_color", COLOR_TEXT)
	prompt.add_theme_font_size_override("font_size", 30)
	prompt.text = "把没说完的话写下来"
	column.add_child(prompt)

	var privacy := Label.new()
	privacy.name = "PrivacyNote"
	privacy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	privacy.add_theme_color_override("font_color", COLOR_MUTED)
	privacy.add_theme_font_size_override("font_size", 17)
	privacy.text = "这句话只属于此刻，不会被写入运行日志。"
	column.add_child(privacy)

	_input = LineEdit.new()
	_input.name = "ReasonInput"
	_input.custom_minimum_size = Vector2(0, 64)
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
	_feedback.text = "写下至少一个字后即可继续"
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
	_submit_button.custom_minimum_size = Vector2(210, 54)
	_submit_button.disabled = true
	_submit_button.add_theme_color_override("font_color", COLOR_TEXT)
	_submit_button.add_theme_color_override("font_hover_color", COLOR_ACCENT)
	_submit_button.add_theme_font_size_override("font_size", 20)
	_submit_button.text = "说出来"
	_submit_button.pressed.connect(_on_submit_pressed)
	button_center.add_child(_submit_button)

	_build_fan_stage()


func _build_fan_stage() -> void:
	_fan_stage = Control.new()
	_fan_stage.name = "FanStage"
	_fan_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fan_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_fan_stage.visible = false
	add_child(_fan_stage)

	_fan_prompt = Label.new()
	_fan_prompt.name = "FanPrompt"
	_fan_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fan_prompt.offset_left = -480.0
	_fan_prompt.offset_right = 480.0
	_fan_prompt.offset_top = 185.0
	_fan_prompt.offset_bottom = 235.0
	_fan_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fan_prompt.add_theme_color_override("font_color", COLOR_TEXT)
	_fan_prompt.add_theme_font_size_override("font_size", 25)
	_fan_prompt.text = "Fan：从中间向左右挥开"
	_fan_stage.add_child(_fan_prompt)

	_fan_left = Label.new()
	_fan_left.name = "FanTextLeft"
	_fan_left.add_theme_color_override("font_color", COLOR_ACCENT)
	_fan_left.add_theme_font_size_override("font_size", 36)
	_fan_stage.add_child(_fan_left)

	_fan_right = Label.new()
	_fan_right.name = "FanTextRight"
	_fan_right.add_theme_color_override("font_color", COLOR_ACCENT)
	_fan_right.add_theme_font_size_override("font_size", 36)
	_fan_stage.add_child(_fan_right)

	var hint := Label.new()
	hint.name = "FanHint"
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.offset_left = -440.0
	hint.offset_right = 440.0
	hint.offset_top = 420.0
	hint.offset_bottom = 458.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", COLOR_MUTED)
	hint.add_theme_font_size_override("font_size", 17)
	hint.text = "张开手掌稳定片刻，再水平往返两次 · F/按钮用于预览"
	_fan_stage.add_child(hint)

	_fan_button = Button.new()
	_fan_button.name = "FanPreviewButton"
	_fan_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_fan_button.offset_left = -130.0
	_fan_button.offset_right = 130.0
	_fan_button.offset_top = 478.0
	_fan_button.offset_bottom = 536.0
	_fan_button.add_theme_font_size_override("font_size", 19)
	_fan_button.text = "触发 Fan（F）"
	_fan_button.pressed.connect(func() -> void: trigger_fan("button"))
	_fan_stage.add_child(_fan_button)


func _focus_input() -> void:
	if _input != null and not _submitted:
		_input.grab_focus()


func _on_text_changed(next_text: String) -> void:
	if _submitted:
		return
	var normalized := next_text.strip_edges()
	_submit_button.disabled = normalized.is_empty()
	_counter.text = "%d / %d" % [next_text.length(), MAX_LENGTH]
	_feedback.add_theme_color_override("font_color", COLOR_MUTED)
	_feedback.text = "按 Enter 或点击“说出来”"


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

	_submitted = true
	_input.editable = false
	_submit_button.disabled = true
	_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
	_feedback.text = "已经说出来了。等待 Fan。"
	_pending_character_count = answer.length()
	_enter_fan_stage(answer)
	return true


func _enter_fan_stage(answer: String) -> void:
	_input_panel.visible = false
	_fan_stage.visible = true
	_fan_prompt.text = "Fan：从中间向左右挥开"
	var split_index := ceili(float(answer.length()) * 0.5)
	_fan_left.text = answer.substr(0, split_index)
	_fan_right.text = answer.substr(split_index)
	_fan_left.reset_size()
	_fan_right.reset_size()
	var left_width := maxf(_fan_left.get_combined_minimum_size().x, 1.0)
	var right_width := maxf(_fan_right.get_combined_minimum_size().x, 1.0)
	var total_width := left_width + right_width
	_fan_left_origin = Vector2((VIEW_SIZE.x - total_width) * 0.5, 310.0)
	_fan_right_origin = Vector2(_fan_left_origin.x + left_width, 310.0)
	_restore_fan_text_transform()
	_fan_detector.reset()
	_fan_waiting = true
	_fan_animating = false
	_fan_button.disabled = false
	_fan_button.grab_focus()


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
	_preview_fan_force(strength, sweep_count)

	# Prototype_2_Fan defines success as two confirmed direction reversals.
	if bool(fan_update.get("completed", false)) or sweep_count >= FanGestureDetectorScript.MIN_SWEEPS_FOR_SUCCESS:
		return trigger_fan("gesture")
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
			_fan_prompt.text = "Fan：从中间向左右挥开"


func _preview_fan_force(strength: float, sweep_count: int) -> void:
	var next_spread := clampf(22.0 + strength * 105.0 + float(sweep_count) * 34.0, 0.0, 220.0)
	_fan_live_spread = maxf(_fan_live_spread, next_spread)
	_fan_left.position = _fan_left_origin + Vector2(-_fan_live_spread, -_fan_live_spread * 0.07)
	_fan_right.position = _fan_right_origin + Vector2(_fan_live_spread, -_fan_live_spread * 0.07)


func trigger_fan(trigger_source := "preview") -> bool:
	if not _fan_waiting or _fan_animating:
		return false
	_fan_waiting = false
	_fan_animating = true
	_fan_button.disabled = true
	call_deferred("_play_fan_cycle", trigger_source)
	return true


func _play_fan_cycle(trigger_source: String) -> void:
	_fan_prompt.text = "把它挥出去。"
	var left_target := Vector2(-_fan_left.size.x - 120.0, _fan_left_origin.y - 42.0)
	var right_target := Vector2(VIEW_SIZE.x + 120.0, _fan_right_origin.y - 42.0)
	var fan_out := create_tween().set_parallel(true)
	fan_out.set_trans(Tween.TRANS_QUART)
	fan_out.set_ease(Tween.EASE_IN)
	fan_out.tween_property(_fan_left, "position", left_target, FAN_OUT_DURATION)
	fan_out.tween_property(_fan_right, "position", right_target, FAN_OUT_DURATION)
	fan_out.tween_property(_fan_left, "rotation", -0.13, FAN_OUT_DURATION)
	fan_out.tween_property(_fan_right, "rotation", 0.13, FAN_OUT_DURATION)
	fan_out.tween_property(_fan_left, "modulate:a", 0.10, FAN_OUT_DURATION)
	fan_out.tween_property(_fan_right, "modulate:a", 0.10, FAN_OUT_DURATION)
	await fan_out.finished

	_fan_prompt.text = "……"
	await get_tree().create_timer(FAN_HOLD_DURATION).timeout

	_fan_prompt.text = "它又回来了。"
	var fan_return := create_tween().set_parallel(true)
	fan_return.set_trans(Tween.TRANS_BACK)
	fan_return.set_ease(Tween.EASE_OUT)
	fan_return.tween_property(_fan_left, "position", _fan_left_origin, FAN_RETURN_DURATION)
	fan_return.tween_property(_fan_right, "position", _fan_right_origin, FAN_RETURN_DURATION)
	fan_return.tween_property(_fan_left, "rotation", 0.0, FAN_RETURN_DURATION)
	fan_return.tween_property(_fan_right, "rotation", 0.0, FAN_RETURN_DURATION)
	fan_return.tween_property(_fan_left, "modulate:a", 1.0, FAN_RETURN_DURATION)
	fan_return.tween_property(_fan_right, "modulate:a", 1.0, FAN_RETURN_DURATION)
	await fan_return.finished

	_fan_return_error = maxf(
		_fan_left.position.distance_to(_fan_left_origin),
		_fan_right.position.distance_to(_fan_right_origin)
	)
	_fan_animating = false
	var fan_result := {
		"gesture": "Fan",
		"trigger_source": trigger_source,
		"returned_to_origin": _fan_return_error <= 0.5,
		"return_error": _fan_return_error,
	}
	fan_cycle_completed.emit(fan_result)
	await get_tree().create_timer(FAN_SETTLE_DURATION).timeout
	_finish_submission(fan_result)


func _restore_fan_text_transform() -> void:
	_fan_left.position = _fan_left_origin
	_fan_right.position = _fan_right_origin
	_fan_left.rotation = 0.0
	_fan_right.rotation = 0.0
	_fan_left.modulate.a = 1.0
	_fan_right.modulate.a = 1.0
	_fan_live_spread = 0.0
	_fan_return_error = INF


func _finish_submission(fan_result: Dictionary) -> void:
	if _finish_emitted:
		return
	_finish_emitted = true
	# 玩家原文不进入 result，避免主流程把私人输入写入 runtime.log。
	finished.emit({
		"result": "success",
		"submitted": true,
		"character_count": _pending_character_count,
		"source": _source,
		"private_text_logged": false,
		"fan_cycle_completed": true,
		"fan_trigger_source": fan_result.get("trigger_source", "unknown"),
		"fan_returned_to_origin": fan_result.get("returned_to_origin", false),
	})


func verify_contract() -> bool:
	return (
		_input != null
		and _submit_button != null
		and _feedback != null
		and _counter != null
		and _fan_stage != null
		and _fan_prompt != null
		and _fan_left != null
		and _fan_right != null
		and _fan_button != null
		and _input.max_length == MAX_LENGTH
		and _submit_button.disabled
		and not _input.placeholder_text.is_empty()
		and not _fan_stage.visible
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


func get_fan_return_error() -> float:
	return _fan_return_error
