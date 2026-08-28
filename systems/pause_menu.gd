extends CanvasLayer

signal save_pressed
signal restart_pressed
signal exit_pressed

var _status: Label


func _ready() -> void:
	layer = 200
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.06, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 0)
	center.add_child(panel)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 24)
	pad.add_theme_constant_override("margin_right", 24)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	var title := Label.new()
	title.text = "菜单（F5 关闭）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	col.add_child(title)

	var save_btn := Button.new()
	save_btn.text = "存档"
	save_btn.pressed.connect(func(): save_pressed.emit())
	col.add_child(save_btn)

	var restart_btn := Button.new()
	restart_btn.text = "从头开始"
	restart_btn.pressed.connect(func(): restart_pressed.emit())
	col.add_child(restart_btn)

	var exit_btn := Button.new()
	exit_btn.text = "退出游戏"
	exit_btn.pressed.connect(func(): exit_pressed.emit())
	col.add_child(exit_btn)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", Color("#9fd4ff"))
	col.add_child(_status)


func is_open() -> bool:
	return visible


func open_menu() -> void:
	_status.text = ""
	visible = true
	get_tree().paused = true


func close_menu() -> void:
	visible = false
	get_tree().paused = false


func toggle_menu() -> void:
	if visible:
		close_menu()
	else:
		open_menu()


func show_status(text: String) -> void:
	_status.text = text
