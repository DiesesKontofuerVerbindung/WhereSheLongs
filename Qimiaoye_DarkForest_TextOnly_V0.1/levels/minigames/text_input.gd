extends Control

signal finished(result)
signal fan_cycle_completed(result)

const FanCameraBridgeScript := preload("res://levels/minigames/fan_camera_bridge.gd")

const VIEW_SIZE := Vector2(1280.0, 720.0)
const MAX_LENGTH := 120
const INTERFERENCE_ENTITY_COUNT := 72
const MAX_INTERFERENCE_WAVES := 1
const RESUME_DELAY := 0.18
const PROTOTYPE_FIELD_SIZE := Vector2(1000.0, 700.0)
const PROTOTYPE_FIELD_OFFSET := (VIEW_SIZE - PROTOTYPE_FIELD_SIZE) * 0.5
const PHYSICS_CLEAR_RATIO := 1.0
const MAX_INPUT_LATENCY_SECONDS := 3.2
const INPUT_LATENCY_CURVE_EXPONENT := 0.55
const UI_FONT_FAMILIES := [
	"Times New Roman",
	"SimSun",
	"Songti SC",
	"Noto Serif CJK SC",
]
const COLOR_BG := Color("020307")
const COLOR_PANEL := Color("070a10f8")
const COLOR_BORDER := Color("304154")
const COLOR_TEXT := Color("dbe4ef")
const COLOR_MUTED := Color("748294")
const COLOR_ACCENT := Color("8fc2e8")
const COLOR_ERROR := Color("f0a6a6")
const INTERFERENCE_PHRASES := [
	"这样不好吗",
	"别跑这么远",
	"恭喜你被录用了",
	"可是我们要结婚……",
	"留在这里不好吗？",
	"外面情况已经这么糟糕了",
	"别人都这么选……",
	"为什么非得是你？",
	"你确定这是你想要的吗？",
	"先想清楚了再做决定",
	"万一后悔了怎么办？",
	"要是做错了就再也回不去了",
	"你这么做别人会怎么看？",
	"What if you're wrong?",
	"Bleib doch hier.",
	"Was, wenn du es bereust?",
	"Perché proprio tu?",
	"E se fosse un errore?",
	"Cosa diranno gli altri?",
	"Non puoi tornare indietro.",
	"Stay where it's safe.",
	"Don't risk everything.",
	"Reste ici.",
	"Et si tu regrettes ?",
	"Que vont penser les autres ?",
	"Quédate aquí.",
	"¿Y si te equivocas?",
	"No hay vuelta atrás.",
	"Fica aqui.",
	"E se te arrependeres?",
	"Blijf toch hier.",
	"Wat als je spijt krijgt?",
	"Stanna här.",
	"Tänk om du ångrar dig?",
	"Zostań tutaj.",
	"A jeśli pożałujesz?",
]
const INTERFERENCE_COLORS := [
	Color("c65360"),
	Color("527fc4"),
	Color("955bb5"),
	Color("bd8745"),
	Color("4fa184"),
]
enum InterferenceState {
	DORMANT,
	BLOCKING,
	DISPERSING,
	CLEARED,
}

var _source := 0
var _input_panel: PanelContainer
var _instruction_label: Label
var _context_note: Label
var _input: LineEdit
var _submit_button: Button
var _feedback: Label
var _counter: Label
var _ui_font: SystemFont
var _interference_layer: Control
var _interference_labels: Array[Label] = []
var _fan_prompt: Label
var _camera_bridge
var _camera_bridge_state := "starting"
var _prototype_frame_received := false
var _last_physics_metrics: Dictionary = {}
var _interference_state := InterferenceState.DORMANT
var _wave_started_count := 0
var _wave_cleared_count := 0
var _fan_waiting := false
var _fan_animating := false
var _pending_character_count := 0
var _submitted := false
var _finish_emitted := false
var _input_resumed_after_fan := false
var _reset_key_was_down := false
var _displayed_input_text := ""
var _pending_text_changes: Array[Dictionary] = []
var _applying_delayed_text := false


func setup(scene_def: Dictionary) -> void:
	_source = int(scene_def.get("source", 0))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_camera_bridge = FanCameraBridgeScript.new()
	_camera_bridge.name = "FanCameraBridge"
	_camera_bridge.physics_frame_received.connect(ingest_prototype2_physics_frame)
	_camera_bridge.status_changed.connect(_on_camera_status_changed)
	add_child(_camera_bridge)
	_camera_bridge.start_bridge()
	call_deferred("_start_interference_wave")


func _process(_delta: float) -> void:
	var reset_down := Input.is_key_pressed(KEY_R)
	if reset_down and not _reset_key_was_down:
		reset_interaction()
	_reset_key_was_down = reset_down
	_drain_delayed_text_changes()


func _build_ui() -> void:
	_ui_font = SystemFont.new()
	_ui_font.font_names = PackedStringArray(UI_FONT_FAMILIES)
	_ui_font.allow_system_fallback = true
	_ui_font.font_weight = 400
	var ui_theme := Theme.new()
	ui_theme.default_font = _ui_font
	theme = ui_theme

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

	_instruction_label = Label.new()
	_instruction_label.name = "Prompt"
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.add_theme_color_override("font_color", COLOR_TEXT)
	_instruction_label.add_theme_font_size_override("font_size", 29)
	_instruction_label.text = "先为自己的声音清出空间"
	column.add_child(_instruction_label)

	_context_note = Label.new()
	_context_note.name = "ContextNote"
	_context_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_context_note.add_theme_color_override("font_color", COLOR_MUTED)
	_context_note.add_theme_font_size_override("font_size", 16)
	_context_note.text = "张开手掌，水平往返挥动"
	column.add_child(_context_note)

	_input = LineEdit.new()
	_input.name = "ReasonInput"
	_input.custom_minimum_size = Vector2(0, 62)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = MAX_LENGTH
	_input.editable = false
	_input.placeholder_text = "在这里写下自己的想法"
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
	_feedback.text = "张开手掌，水平往返挥扫"
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
		phrase.add_theme_font_size_override("font_size", 24 + (index * 7) % 12)
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


func _focus_input() -> void:
	if _input != null and not _submitted and _input.editable:
		_input.grab_focus()


func _on_text_changed(next_text: String) -> void:
	if _submitted or _applying_delayed_text:
		return
	if _input_latency_seconds() > 0.0:
		_queue_delayed_text_change(next_text)
		return
	_displayed_input_text = next_text
	_counter.text = "%d / %d" % [next_text.length(), MAX_LENGTH]
	_refresh_input_status(next_text.strip_edges())


func _input_latency_seconds() -> float:
	if _interference_state not in [InterferenceState.BLOCKING, InterferenceState.DISPERSING]:
		return 0.0
	var dispersed_ratio := clampf(float(_last_physics_metrics.get("dispersed_ratio", 0.0)), 0.0, 1.0)
	return MAX_INPUT_LATENCY_SECONDS * pow(1.0 - dispersed_ratio, INPUT_LATENCY_CURVE_EXPONENT)


func _queue_delayed_text_change(next_text: String) -> void:
	var displayed_text := _displayed_input_text
	var operation := {"kind": "replace", "text": next_text}
	if next_text.begins_with(displayed_text):
		var appended := next_text.substr(displayed_text.length())
		if not appended.is_empty():
			operation = {"kind": "append", "text": appended}
	elif displayed_text.begins_with(next_text):
		operation = {"kind": "delete", "count": displayed_text.length() - next_text.length()}
	_pending_text_changes.append({
		"due_at": Time.get_ticks_msec() * 0.001 + _input_latency_seconds(),
		"operation": operation,
	})
	_set_displayed_input_text(displayed_text)
	_feedback.add_theme_color_override("font_color", COLOR_MUTED)
	_feedback.text = "外部的声音还在拖住这些字……"


func _drain_delayed_text_changes() -> void:
	if _pending_text_changes.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	while not _pending_text_changes.is_empty() and float(_pending_text_changes[0].get("due_at", INF)) <= now:
		_apply_text_operation(_pending_text_changes.pop_front().get("operation", {}))


func _apply_text_operation(operation: Dictionary) -> void:
	match str(operation.get("kind", "replace")):
		"append":
			_displayed_input_text += str(operation.get("text", ""))
		"delete":
			var delete_count := maxi(0, int(operation.get("count", 0)))
			_displayed_input_text = _displayed_input_text.left(maxi(0, _displayed_input_text.length() - delete_count))
		_:
			_displayed_input_text = str(operation.get("text", _displayed_input_text))
	_set_displayed_input_text(_displayed_input_text)


func _set_displayed_input_text(next_text: String) -> void:
	if _input == null:
		return
	_applying_delayed_text = true
	_input.text = next_text
	_input.caret_column = next_text.length()
	_applying_delayed_text = false
	_counter.text = "%d / %d" % [next_text.length(), MAX_LENGTH]
	_refresh_input_status(next_text.strip_edges())


func _flush_delayed_text_changes() -> void:
	while not _pending_text_changes.is_empty():
		_apply_text_operation(_pending_text_changes.pop_front().get("operation", {}))


func _refresh_input_status(normalized_text := "") -> void:
	if _submitted:
		return
	var normalized := normalized_text if not normalized_text.is_empty() else _input.text.strip_edges()
	var has_input := not normalized.is_empty() or not _pending_text_changes.is_empty()
	_submit_button.disabled = not has_input
	_feedback.add_theme_color_override("font_color", COLOR_MUTED)
	if not has_input:
		_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
		_feedback.text = "在这里写下自己的想法"
	else:
		_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
		_feedback.text = "按 Enter 或点击“说出来”"


func _on_text_submitted(_value: String) -> void:
	_attempt_submit()


func _on_submit_pressed() -> void:
	_attempt_submit()


func _attempt_submit() -> bool:
	if _submitted or _input == null:
		return false
	_flush_delayed_text_changes()
	var answer := _input.text.strip_edges()
	if answer.is_empty():
		_feedback.add_theme_color_override("font_color", COLOR_ERROR)
		_feedback.text = "这句还空着。至少写下一个字。"
		_input.grab_focus()
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
	if _interference_state in [InterferenceState.BLOCKING, InterferenceState.DISPERSING]:
		return
	_wave_started_count += 1
	_interference_state = InterferenceState.BLOCKING
	_fan_waiting = true
	_fan_animating = false
	_prototype_frame_received = false
	_last_physics_metrics.clear()
	_interference_layer.visible = true
	match _camera_bridge_state:
		"ready":
			_fan_prompt.text = "摄像头已连接 · 张开手掌，水平往返挥扫"
		"error":
			_fan_prompt.text = "摄像头未连接，请检查设备"
		_:
			_fan_prompt.text = "正在连接摄像头……"
	_show_initial_interference_field()

	_input.editable = true
	call_deferred("_focus_input")
	_refresh_input_status()


func _show_initial_interference_field() -> void:
	for index in range(_interference_labels.size()):
		var phrase := _interference_labels[index]
		var column := index % 9
		var row := int(index / 9) % 8
		var field_center := Vector2(
			55.0 + float(column) * 111.0,
			92.0 + float(row) * 80.0
		) + Vector2(
			float((index * 13) % 49) - 24.0,
			float((index * 7) % 31) - 15.0
		)
		phrase.reset_size()
		phrase.visible = true
		phrase.position = PROTOTYPE_FIELD_OFFSET + field_center - phrase.size * 0.5
		phrase.rotation = 0.0
		phrase.scale = Vector2.ONE
		phrase.modulate.a = 0.82


func reset_interaction() -> bool:
	if _submitted or _finish_emitted:
		return false
	_pending_character_count = 0
	_pending_text_changes.clear()
	_displayed_input_text = ""
	_set_displayed_input_text("")
	_instruction_label.text = "先为自己的声音清出空间"
	_context_note.text = "张开手掌，水平往返挥动"
	_input.placeholder_text = "在这里写下自己的想法"
	_interference_state = InterferenceState.DORMANT
	_wave_started_count = 0
	_wave_cleared_count = 0
	_fan_waiting = false
	_fan_animating = false
	_prototype_frame_received = false
	_last_physics_metrics.clear()
	_input_resumed_after_fan = false
	_input.editable = true
	_submit_button.disabled = true
	_interference_layer.visible = false
	for phrase in _interference_labels:
		phrase.visible = false
		phrase.modulate.a = 0.0
	if _camera_bridge != null:
		_camera_bridge.request_reset()
	_start_interference_wave()
	_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
	_feedback.text = "已重置 · 张开手掌，水平往返挥扫"
	return true


func ingest_prototype2_physics_frame(frame: Dictionary) -> bool:
	if str(frame.get("event", "")) != "prototype2_physics_frame":
		return false
	if not _fan_waiting or _fan_animating:
		return false
	var entities: Variant = frame.get("entities", [])
	if not entities is Array or entities.size() != INTERFERENCE_ENTITY_COUNT:
		return false
	_prototype_frame_received = true
	_apply_prototype_entities(entities)
	var metrics: Variant = frame.get("metrics", {})
	_last_physics_metrics = metrics.duplicate(true) if metrics is Dictionary else {}
	_update_prototype_prompt(frame, _last_physics_metrics)
	var dispersed_ratio := float(_last_physics_metrics.get("dispersed_ratio", 0.0))
	if dispersed_ratio >= PHYSICS_CLEAR_RATIO:
		return _complete_prototype2_physics()
	return true


func _apply_prototype_entities(entities: Array) -> void:
	for entity_value in entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		var index := int(entity.get("index", -1))
		if index < 0 or index >= _interference_labels.size():
			continue
		var phrase := _interference_labels[index]
		phrase.text = str(entity.get("text", phrase.text))
		phrase.add_theme_font_size_override("font_size", int(entity.get("font_size", 32)))
		var color_value: Variant = entity.get("color", [])
		if color_value is Array and color_value.size() >= 3:
			phrase.add_theme_color_override("font_color", Color8(
				int(color_value[0]),
				int(color_value[1]),
				int(color_value[2])
			))
		phrase.reset_size()
		var center := PROTOTYPE_FIELD_OFFSET + Vector2(
			float(entity.get("x", PROTOTYPE_FIELD_SIZE.x * 0.5)),
			float(entity.get("y", PROTOTYPE_FIELD_SIZE.y * 0.5))
		)
		phrase.position = center - phrase.size * 0.5
		phrase.rotation = 0.0
		phrase.scale = Vector2.ONE
		var dispersed := bool(entity.get("dispersed", false))
		phrase.visible = not dispersed
		phrase.modulate.a = 0.0 if dispersed else clampf(float(entity.get("opacity", 1.0)), 0.0, 1.0)


func _update_prototype_prompt(frame: Dictionary, metrics: Dictionary) -> void:
	var clear_percent := int(round(float(metrics.get("dispersed_ratio", 0.0)) * 100.0))
	if not bool(frame.get("hand_detected", false)):
		_fan_prompt.text = "把张开的手放进镜头"
	elif not bool(frame.get("open_palm", false)):
		_fan_prompt.text = "请张开手掌，再水平往返挥动"
	else:
		var state := str(frame.get("state", "TRACKING"))
		match state:
			"PALM_ARMING":
				_fan_prompt.text = "张开手掌，稳住……"
			"FAN_READY":
				_fan_prompt.text = "开始水平挥扫"
			"FANNING":
				var direction_text := "向右" if str(frame.get("direction", "center")) == "right" else "向左"
				_fan_prompt.text = "%s · 有效换向 %d · 清出 %d%%" % [
					direction_text,
					int(frame.get("sweep_count", 0)),
					clear_percent,
				]
			_:
				_fan_prompt.text = "张开手掌，水平往返挥扫"
	_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
	_feedback.text = "已清出 %d%%" % clear_percent


func _on_camera_status_changed(state: String, detail: String) -> void:
	_camera_bridge_state = state
	match state:
		"starting":
			_fan_prompt.text = "正在连接摄像头……"
		"ready":
			_fan_prompt.text = "Prototype_2_Fan 已连接 · 张开手掌，水平往返挥扫"
			print("TEXT_INPUT_PROTOTYPE2_RUNTIME_READY %s" % detail)
		"reset":
			_fan_prompt.text = "物理场已重置 · 张开手掌，水平往返挥扫"
			print("TEXT_INPUT_PROTOTYPE2_RUNTIME_RESET %s" % detail)
		"error":
			_fan_prompt.text = "摄像头无法启动：%s" % detail
			_feedback.add_theme_color_override("font_color", COLOR_ERROR)
			_feedback.text = "请关闭占用摄像头的程序后重开玩法3"
			push_warning("TEXT_INPUT_PROTOTYPE2_RUNTIME_ERROR %s" % detail)


func _complete_prototype2_physics() -> bool:
	if not _fan_waiting or _fan_animating:
		return false
	_fan_waiting = false
	_fan_animating = true
	_interference_state = InterferenceState.DISPERSING
	call_deferred("_finish_prototype2_clear")
	return true


func _finish_prototype2_clear() -> void:
	for phrase in _interference_labels:
		phrase.visible = false
	_wave_cleared_count += 1
	_interference_state = InterferenceState.CLEARED
	_fan_animating = false
	_interference_layer.visible = false
	_flush_delayed_text_changes()
	_input_resumed_after_fan = true
	_instruction_label.text = "把没说完的话写下来"
	_context_note.text = "现在轮到你的声音"
	_input.placeholder_text = "在这里写下自己的想法"
	var fan_result := {
		"gesture": "Fan",
		"trigger_source": "Prototype_2_Fan",
		"wave": _wave_cleared_count,
		"interference_entity_count": INTERFERENCE_ENTITY_COUNT,
		"physics_runtime": "Prototype_2_Fan",
		"dispersed_ratio": float(_last_physics_metrics.get("dispersed_ratio", 0.0)),
		"last_impulse_stroke_id": int(_last_physics_metrics.get("last_impulse_stroke_id", 0)),
		"player_text_included": false,
	}
	fan_cycle_completed.emit(fan_result)
	await get_tree().create_timer(RESUME_DELAY).timeout
	_resume_input_after_fan()


func _resume_input_after_fan() -> void:
	if _submitted:
		return
	_input.editable = true
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
		"physics_runtime": "Prototype_2_Fan",
		"prototype_physics_received": _prototype_frame_received,
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
		and _ui_font != null
		and _ui_font.font_names == PackedStringArray(UI_FONT_FAMILIES)
		and _ui_font.allow_system_fallback
		and _instruction_label != null
		and _context_note != null
		and _interference_layer != null
		and _fan_prompt != null
		and _camera_bridge != null
		and _interference_labels.size() == INTERFERENCE_ENTITY_COUNT
		and phrase_counts.size() == INTERFERENCE_PHRASES.size()
		and COLOR_BG.get_luminance() < 0.02
		and COLOR_PANEL.get_luminance() < 0.04
		and _input.max_length == MAX_LENGTH
		and _input.editable
		and _submit_button.disabled
		and not _input.placeholder_text.is_empty()
		and _interference_layer.visible
		and _fan_waiting
		and _wave_started_count == 1
	)


func debug_submit_for_verification(text: String) -> bool:
	if _input == null:
		return false
	_input.text = text
	_on_text_changed(text)
	return _attempt_submit()


func debug_reset_for_verification() -> bool:
	return reset_interaction()


func debug_set_text_for_verification(text: String) -> int:
	if _input == null:
		return -1
	_pending_text_changes.clear()
	_displayed_input_text = text
	_set_displayed_input_text(text)
	return _input.text.length()


func debug_type_for_verification(text: String) -> bool:
	if _input == null:
		return false
	_queue_delayed_text_change(_displayed_input_text + text)
	return true


func get_pending_text_change_count() -> int:
	return _pending_text_changes.size()


func get_displayed_input_text() -> String:
	return "" if _input == null else _input.text


func get_input_latency_seconds() -> float:
	return _input_latency_seconds()


func is_waiting_for_fan() -> bool:
	return _fan_waiting


func is_interference_active() -> bool:
	return _interference_state in [InterferenceState.BLOCKING, InterferenceState.DISPERSING]


func is_input_editable() -> bool:
	return _input != null and _input.editable


func is_submit_enabled() -> bool:
	return _submit_button != null and not _submit_button.disabled


func is_camera_bridge_attached() -> bool:
	return _camera_bridge != null


func has_prototype_physics_frame() -> bool:
	return _prototype_frame_received


func get_last_physics_metrics() -> Dictionary:
	return _last_physics_metrics.duplicate(true)


func get_interference_entity_position(index: int) -> Vector2:
	if index < 0 or index >= _interference_labels.size():
		return Vector2.INF
	return _interference_labels[index].position


func get_wave_started_count() -> int:
	return _wave_started_count


func get_wave_cleared_count() -> int:
	return _wave_cleared_count


func get_interference_phrases() -> PackedStringArray:
	var phrases := PackedStringArray()
	for phrase in _interference_labels:
		phrases.append(phrase.text)
	return phrases


func get_ui_font_families() -> PackedStringArray:
	return _ui_font.font_names.duplicate() if _ui_font != null else PackedStringArray()


func does_interference_cover_screen() -> bool:
	if not is_interference_active() or _interference_labels.is_empty():
		return false
	var min_center := Vector2(INF, INF)
	var max_center := Vector2(-INF, -INF)
	for phrase in _interference_labels:
		if not phrase.visible:
			return false
		var phrase_center := phrase.position + phrase.size * 0.5
		min_center.x = minf(min_center.x, phrase_center.x)
		min_center.y = minf(min_center.y, phrase_center.y)
		max_center.x = maxf(max_center.x, phrase_center.x)
		max_center.y = maxf(max_center.y, phrase_center.y)
	var coverage := max_center - min_center
	return coverage.x >= 700.0 and coverage.y >= 400.0
