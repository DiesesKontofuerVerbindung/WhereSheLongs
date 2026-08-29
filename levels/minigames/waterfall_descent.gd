extends Control

signal finished(result)

const DialogueLayout := preload("res://systems/dialogue_layout.gd")
const VIEW_SIZE := DialogueLayout.VIEWPORT

var _hint: Label


func setup(_scene_def: Dictionary) -> void:
	pass


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	clip_contents = true

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("#102b46")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.offset_left = -300.0
	_hint.offset_right = 300.0
	_hint.offset_top = -40.0
	_hint.offset_bottom = 40.0
	_hint.text = "瀑降（玩法占位）\n按空格继续"
	add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		finished.emit({"result": "success"})
		get_viewport().set_input_as_handled()
