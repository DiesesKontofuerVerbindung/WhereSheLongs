extends Control

const CGCatalog := preload("res://data/cg_catalog.gd")
const DialogueLayout := preload("res://systems/dialogue_layout.gd")

var _bg: ColorRect
var _tex: TextureRect
var _title: Label
var _overlay: ColorRect
var _dialogue_label: Label
var _continue_hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color.BLACK
	add_child(_overlay)

	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_tex = TextureRect.new()
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_tex)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 40
	add_child(_title)

	_dialogue_label = Label.new()
	_dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue_label.add_theme_font_size_override("font_size", DialogueLayout.FONT_CG)
	DialogueLayout.apply_cg_dialogue_offsets(_dialogue_label)
	_dialogue_label.visible = false
	add_child(_dialogue_label)

	_continue_hint = Label.new()
	_continue_hint.text = "点击继续"
	_continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_continue_hint.offset_top = -36
	_continue_hint.modulate.a = 0.0
	add_child(_continue_hint)


func play(cg_id: String, payload: Dictionary = {}) -> void:
	var entry: Dictionary = CGCatalog.get_entry(cg_id)
	_title.text = str(entry.get("title", cg_id))
	var tex_path := str(entry.get("texture", ""))
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		_tex.texture = load(tex_path)
		_tex.visible = true
		_bg.visible = false
	else:
		_tex.visible = false
		_bg.visible = true
		_bg.color = entry.get("color", Color.BLACK)
	var pan: Vector2 = entry.get("pan", Vector2.ZERO)
	_tex.position = pan
	var dialogue_text := str(payload.get("dialogue", ""))
	if dialogue_text.is_empty():
		_dialogue_label.visible = false
	else:
		_dialogue_label.text = dialogue_text
		_dialogue_label.visible = true
	_overlay.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 0.0, 0.6)
	await tween.finished
	if payload.get("auto_advance", false):
		await get_tree().create_timer(float(payload.get("duration", 2.0))).timeout
	else:
		await _wait_click()
	var tween_out := create_tween()
	tween_out.tween_property(_overlay, "modulate:a", 1.0, 0.5)
	await tween_out.finished


func _wait_click() -> void:
	_continue_hint.modulate.a = 0.6
	var mouse_was_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	while true:
		await get_tree().process_frame
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("interact"):
			break
		var mouse_is_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if mouse_is_pressed and not mouse_was_pressed:
			break
		mouse_was_pressed = mouse_is_pressed
	_continue_hint.modulate.a = 0.0
