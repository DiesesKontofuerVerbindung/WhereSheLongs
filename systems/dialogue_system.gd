extends Control

const DialogueLayout := preload("res://systems/dialogue_layout.gd")
const PlaceholderAssets := preload("res://systems/placeholder_assets.gd")
const PortraitCatalog := preload("res://data/portrait_catalog.gd")

var _scene_id := ""
var _title: Label
var _speaker: Label
var _body: Label
var _portrait_tex: TextureRect
var _continue: Button
var _choices: VBoxContainer
var _input_panel: PanelContainer
var _input_prompt: Label
var _input_field: LineEdit
var _input_confirm: Button
var _lines: Array = []
var _choice_defs: Array = []
var _index := 0
var _typing := false
var _type_speed := 0.03
var _waiting_action := false


func _ready() -> void:
	_build_ui()


func play(scene_def: Dictionary) -> void:
	_scene_id = str(scene_def.get("id", ""))
	_lines = scene_def.get("lines", [])
	_choice_defs = scene_def.get("choices", [])
	_index = 0
	_title.text = str(scene_def.get("title", "对话"))
	_choices.visible = false
	_input_panel.visible = false
	_clear_choices()
	_continue.visible = true
	_continue.text = "继续"
	if _lines.is_empty() and not _choice_defs.is_empty():
		_show_choices()
		return
	if _lines.is_empty():
		SceneManager.complete_current_scene()
		return
	await _advance_line()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("0a0c10cc")
	add_child(bg)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", DialogueLayout.FONT_TITLE)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 16
	_title.offset_bottom = 52
	add_child(_title)

	_portrait_tex = TextureRect.new()
	_portrait_tex.custom_minimum_size = Vector2(120, 160)
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_tex.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_portrait_tex.offset_left = 24
	_portrait_tex.offset_top = -80
	_portrait_tex.offset_right = 144
	_portrait_tex.offset_bottom = 80
	_portrait_tex.visible = false
	add_child(_portrait_tex)

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
	_speaker.add_theme_color_override("font_color", Color("7eb8ff"))
	col.add_child(_speaker)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", DialogueLayout.FONT_BODY)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_body)

	_continue = Button.new()
	_continue.text = "继续"
	_continue.pressed.connect(_on_continue)
	col.add_child(_continue)

	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	_choices.visible = false
	col.add_child(_choices)

	_input_panel = PanelContainer.new()
	_input_panel.visible = false
	_input_panel.set_anchors_preset(Control.PRESET_CENTER)
	_input_panel.offset_left = -240
	_input_panel.offset_right = 240
	_input_panel.offset_top = -60
	_input_panel.offset_bottom = 60
	add_child(_input_panel)

	var input_col := VBoxContainer.new()
	input_col.add_theme_constant_override("separation", 8)
	_input_panel.add_child(input_col)

	_input_prompt = Label.new()
	_input_prompt.name = "PromptLabel"
	input_col.add_child(_input_prompt)

	_input_field = LineEdit.new()
	_input_field.placeholder_text = "输入..."
	input_col.add_child(_input_field)

	_input_confirm = Button.new()
	_input_confirm.text = "确认"
	_input_confirm.pressed.connect(_on_input_confirm)
	input_col.add_child(_input_confirm)


func _on_continue() -> void:
	if _typing:
		_body.text = _resolve_text(str(_lines[_index].get("text", "")))
		_typing = false
		return
	if _waiting_action:
		return
	_index += 1
	if _index >= _lines.size():
		if _choice_defs.is_empty():
			SceneManager.complete_current_scene()
			return
		_show_choices()
		return
	await _advance_line()


func _advance_line() -> void:
	if _index >= _lines.size():
		return
	var line: Dictionary = _lines[_index]
	if line.has("action"):
		await _run_action(line)
		_index += 1
		if _index >= _lines.size():
			if _choice_defs.is_empty():
				SceneManager.complete_current_scene()
			else:
				_show_choices()
			return
		await _advance_line()
		return
	if line.has("cg"):
		await CGManager.show_cg(str(line.get("cg", "")))
	_speaker.text = str(line.get("speaker", ""))
	var portrait_id := str(line.get("portrait", ""))
	if portrait_id.is_empty():
		_portrait_tex.visible = false
	else:
		_portrait_tex.texture = PortraitCatalog.get_texture(portrait_id)
		_portrait_tex.visible = true
	var full_text := _resolve_text(str(line.get("text", "")))
	await _type_text(full_text)


func _type_text(full_text: String) -> void:
	_typing = true
	_body.text = ""
	for i in range(full_text.length()):
		if not _typing:
			return
		_body.text = full_text.substr(0, i + 1)
		await get_tree().create_timer(_type_speed).timeout
	_typing = false


func _resolve_text(raw: String) -> String:
	var text := raw
	text = text.replace("{custom_player_text}", GameState.custom_player_text)
	text = text.replace("{affection_amai}", str(GameState.affection_amai))
	text = text.replace("{player_choice}", GameState.player_choice)
	return text


func _run_action(line: Dictionary) -> void:
	var action := str(line.get("action", ""))
	match action:
		"show_cg", "cg":
			await CGManager.show_cg(str(line.get("cg_id", line.get("cg", ""))))
		"set_var":
			GameState.set_var(str(line.get("key", "")), line.get("value", ""), str(line.get("op", "set")))
		"show_title":
			pass
		"text_input":
			await _show_text_input(line)
		_:
			push_warning("Unknown dialogue action: %s" % action)


func _show_text_input(line: Dictionary) -> void:
	_waiting_action = true
	_continue.visible = false
	_input_panel.visible = true
	_input_prompt.text = str(line.get("prompt", "请输入："))
	_input_field.placeholder_text = str(line.get("placeholder", ""))
	_input_field.text = ""
	_input_field.grab_focus()


func _on_input_confirm() -> void:
	var key := "custom_player_text"
	if _index < _lines.size():
		key = str(_lines[_index].get("var_key", "custom_player_text"))
	var text := _input_field.text.strip_edges()
	if text.is_empty():
		text = _input_field.placeholder_text
	GameState.set_var(key, text)
	_input_panel.visible = false
	_continue.visible = true
	_waiting_action = false


func _show_choices() -> void:
	_continue.visible = false
	_choices.visible = true
	_clear_choices()
	for raw in _choice_defs:
		var choice: Dictionary = raw
		var condition := str(choice.get("condition", ""))
		if not condition.is_empty() and not GameState.has_flag(condition):
			continue
		var btn := Button.new()
		btn.text = str(choice.get("text", ""))
		btn.pressed.connect(_on_choice.bind(choice))
		_choices.add_child(btn)


func _on_choice(choice: Dictionary) -> void:
	GameState.record_choice(_scene_id, str(choice.get("id", "")))
	GameState.apply_effects(choice.get("effects", {}))
	SceneManager.complete_current_scene({"next": choice.get("next", "")})


func _clear_choices() -> void:
	for child in _choices.get_children():
		child.queue_free()
