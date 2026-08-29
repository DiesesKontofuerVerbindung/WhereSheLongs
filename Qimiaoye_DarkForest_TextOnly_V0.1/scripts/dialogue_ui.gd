class_name DarkForestDialogueUI
extends PanelContainer

signal advance_requested
signal choice_selected(choice_id: String)
signal line_presented(token: int)
signal queue_idle

const COLOR_TEXT := Color("252931")
const COLOR_ACCENT := Color("555b66")
const DIALOGUE_BOX_PATH := "res://assets/ui/dialogue/dialogue_left_reference.png"
const DIALOGUE_BOX_REGION := Rect2(104.0, 416.0, 1072.0, 262.0)
const DIALOGUE_TEXT_SHIFT := 96
const DIALOGUE_BODY_TOP_SHIFT := 12
const TextRevealProfile := preload("res://scripts/text_reveal_profile.gd")

var _speaker_panel: PanelContainer
var _speaker_label: Label
var _body_label: Label
var _continue_button: Button
var _choice_box: VBoxContainer
var _line_queue: Array[Dictionary] = []
var _completed: Dictionary = {}
var _next_token := 1
var _processing := false
var _waiting_for_advance := false
var _waiting_for_choice := false
var _max_queue_depth := 0
var _presented_line_count := 0
var _choice_layout_sample_count := 0
var _choice_layout_violation_count := 0
var _choice_layout_max_center_error := 0.0


func _ready() -> void:
	_build_ui()


func present_line(speaker: String, text: String, instant := false) -> void:
	var token := enqueue_line(speaker, text, instant)
	while not _completed.has(token):
		await line_presented


func enqueue_line(speaker: String, text: String, instant := false) -> int:
	var token := _next_token
	_next_token += 1
	_line_queue.append({"token": token, "speaker": speaker, "text": text, "instant": instant})
	_max_queue_depth = maxi(_max_queue_depth, _line_queue.size())
	if not _processing:
		_processing = true
		call_deferred("_drain_line_queue")
	return token


func wait_until_idle() -> void:
	while _processing or not _line_queue.is_empty():
		await queue_idle


func set_advance_waiting(enabled: bool) -> void:
	_waiting_for_advance = enabled
	_continue_button.visible = enabled
	_continue_button.disabled = not enabled


func request_advance() -> void:
	if not _waiting_for_advance:
		return
	_waiting_for_advance = false
	_continue_button.visible = false
	advance_requested.emit()


func show_choice(prompt: String, options: Array) -> void:
	visible = true
	_waiting_for_advance = false
	_continue_button.visible = false
	_clear_choices()
	_speaker_label.text = "玩家选择"
	_body_label.text = prompt
	_speaker_label.visible_ratio = 1.0
	_body_label.visible_ratio = 1.0
	_speaker_label.modulate.a = 1.0
	_body_label.modulate.a = 1.0
	_choice_box.visible = true
	_waiting_for_choice = true
	for raw in options:
		var option: Dictionary = raw
		var button := Button.new()
		button.text = str(option.get("text", ""))
		button.custom_minimum_size = Vector2(440, 42)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(_on_choice_pressed.bind(str(option.get("id", ""))))
		_choice_box.add_child(button)
	call_deferred("_record_choice_layout")


func hide_dialogue() -> void:
	visible = false
	_waiting_for_advance = false
	_waiting_for_choice = false
	_continue_button.visible = false
	_clear_choices()


func clear_immediately() -> void:
	_line_queue.clear()
	_completed.clear()
	_processing = false
	_presented_line_count = 0
	_choice_layout_sample_count = 0
	_choice_layout_violation_count = 0
	_choice_layout_max_center_error = 0.0
	hide_dialogue()


func get_max_queue_depth() -> int:
	return _max_queue_depth


func get_body_text() -> String:
	return _body_label.text


func is_queue_idle() -> bool:
	return not _processing and _line_queue.is_empty()


func get_presented_line_count() -> int:
	return _presented_line_count


func get_choice_layout_sample_count() -> int:
	return _choice_layout_sample_count


func get_choice_layout_violation_count() -> int:
	return _choice_layout_violation_count


func get_choice_layout_max_center_error() -> float:
	return _choice_layout_max_center_error


func is_panel_centered() -> bool:
	if not is_equal_approx(anchor_left + anchor_right, 1.0):
		return false
	if not is_equal_approx(offset_left + offset_right, 0.0):
		return false
	return true


func is_text_left_aligned() -> bool:
	if _speaker_label == null or _body_label == null or _continue_button == null:
		return false
	if _speaker_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		return false
	return _body_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_LEFT


func is_body_compact_at_top() -> bool:
	if _body_label == null:
		return false
	return (
		_body_label.vertical_alignment == VERTICAL_ALIGNMENT_TOP
		and _body_label.size_flags_vertical == Control.SIZE_SHRINK_BEGIN
		and _body_label.custom_minimum_size.y <= 64.0
	)


func is_continue_button_centered() -> bool:
	if _continue_button == null:
		return false
	return _continue_button.text == "继续" and _continue_button.size_flags_horizontal == Control.SIZE_SHRINK_CENTER


func uses_progressive_reveal() -> bool:
	return TextRevealProfile.is_valid()


func get_reveal_speed_multiplier() -> float:
	return TextRevealProfile.REVEAL_SPEED_MULTIPLIER


func is_choice_group_centered() -> bool:
	if _choice_box == null or _choice_box.size.x <= 0.0:
		return false
	var button_count := 0
	for child in _choice_box.get_children():
		if child is Button:
			var button := child as Button
			if button.is_queued_for_deletion():
				continue
			button_count += 1
			if button.size_flags_horizontal != Control.SIZE_SHRINK_CENTER:
				return false
			var child_center := button.position.x + button.size.x * 0.5
			if absf(child_center - _choice_box.size.x * 0.5) > 0.75:
				return false
	return button_count > 0


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 72
	offset_right = -72
	offset_top = -328
	offset_bottom = -28
	var panel_style := _make_texture_style(DIALOGUE_BOX_PATH, DIALOGUE_BOX_REGION, 76.0, 96.0, 76.0, 62.0)
	add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var speaker_margin := MarginContainer.new()
	speaker_margin.add_theme_constant_override("margin_left", 64)
	col.add_child(speaker_margin)

	_speaker_panel = PanelContainer.new()
	_speaker_panel.custom_minimum_size = Vector2(191.0, 44.0)
	_speaker_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_speaker_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	speaker_margin.add_child(_speaker_panel)

	_speaker_label = Label.new()
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speaker_label.add_theme_font_size_override("font_size", 22)
	_speaker_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_speaker_panel.add_child(_speaker_label)

	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", DIALOGUE_TEXT_SHIFT)
	body_margin.add_theme_constant_override("margin_top", DIALOGUE_BODY_TOP_SHIFT)
	col.add_child(body_margin)

	_body_label = Label.new()
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_body_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_body_label.add_theme_font_size_override("font_size", 22)
	_body_label.add_theme_color_override("font_color", COLOR_TEXT)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_body_label.custom_minimum_size.y = 64
	_body_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body_margin.add_child(_body_label)

	_choice_box = VBoxContainer.new()
	_choice_box.add_theme_constant_override("separation", 8)
	_choice_box.visible = false
	col.add_child(_choice_box)

	var spacer := Control.new()
	spacer.name = "DialogueBottomSpacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	_continue_button = Button.new()
	_continue_button.text = "继续"
	_continue_button.custom_minimum_size = Vector2(320, 40)
	_continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_continue_button.visible = false
	_continue_button.pressed.connect(request_advance)
	col.add_child(_continue_button)
	hide_dialogue()


func _make_texture_style(path: String, region: Rect2, left: float, top: float, right: float, bottom: float) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path) as Texture2D
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.texture_margin_left = left
	style.texture_margin_top = top
	style.texture_margin_right = right
	style.texture_margin_bottom = bottom
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style


func _drain_line_queue() -> void:
	while not _line_queue.is_empty():
		var request: Dictionary = _line_queue.pop_front()
		visible = true
		_clear_choices()
		var speaker := str(request.get("speaker", ""))
		var body_text := str(request.get("text", ""))
		var instant := bool(request.get("instant", false))
		_speaker_label.text = speaker
		_body_label.text = body_text
		if instant:
			_set_line_fully_visible()
		else:
			await _animate_progressive_reveal(speaker, body_text)
		_presented_line_count += 1
		var token := int(request.get("token", 0))
		_completed[token] = true
		line_presented.emit(token)
	_processing = false
	queue_idle.emit()


func _set_line_fully_visible() -> void:
	_speaker_label.visible_ratio = 1.0
	_body_label.visible_ratio = 1.0
	_speaker_label.modulate.a = 1.0
	_body_label.modulate.a = 1.0


func _animate_progressive_reveal(speaker: String, body_text: String) -> void:
	_speaker_label.visible_ratio = 0.0
	_body_label.visible_ratio = 0.0
	_speaker_label.modulate.a = 0.28
	_body_label.modulate.a = TextRevealProfile.START_ALPHA

	if not speaker.is_empty():
		var speaker_duration := TextRevealProfile.speaker_duration_for(speaker)
		var speaker_tween := create_tween()
		speaker_tween.set_parallel(true)
		speaker_tween.tween_property(_speaker_label, "visible_ratio", 1.0, speaker_duration).set_trans(Tween.TRANS_LINEAR)
		speaker_tween.tween_property(_speaker_label, "modulate:a", 1.0, speaker_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await speaker_tween.finished
	else:
		_speaker_label.visible_ratio = 1.0
		_speaker_label.modulate.a = 1.0

	var body_duration := TextRevealProfile.duration_for(body_text)
	var body_tween := create_tween()
	body_tween.set_parallel(true)
	body_tween.tween_property(_body_label, "visible_ratio", 1.0, body_duration).set_trans(Tween.TRANS_LINEAR)
	body_tween.tween_property(_body_label, "modulate:a", 1.0, body_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await body_tween.finished
	_set_line_fully_visible()


func _on_choice_pressed(choice_id: String) -> void:
	if not _waiting_for_choice:
		return
	_waiting_for_choice = false
	choice_selected.emit(choice_id)


func _record_choice_layout() -> void:
	if not is_instance_valid(_choice_box) or not _choice_box.visible:
		return
	_choice_layout_sample_count += 1
	var violation := false
	var button_count := 0
	for child in _choice_box.get_children():
		if child is Button:
			var button := child as Button
			if button.is_queued_for_deletion():
				continue
			button_count += 1
			var child_center := button.position.x + button.size.x * 0.5
			var center_error := absf(child_center - _choice_box.size.x * 0.5)
			_choice_layout_max_center_error = maxf(_choice_layout_max_center_error, center_error)
			if button.size_flags_horizontal != Control.SIZE_SHRINK_CENTER or center_error > 0.75:
				violation = true
	if button_count == 0:
		violation = true
	if violation:
		_choice_layout_violation_count += 1


func _clear_choices() -> void:
	_choice_box.visible = false
	for child in _choice_box.get_children():
		child.queue_free()
