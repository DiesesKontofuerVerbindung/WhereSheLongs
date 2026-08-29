extends Control

var _label: Label
var _retry: Button
var _continue_story: Button
var _title: Button
var _payload: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.02, 0.08, 0.92)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.offset_left = -200
	col.offset_right = 200
	col.offset_top = -100
	col.offset_bottom = 100
	col.add_theme_constant_override("separation", 12)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)

	var title := Label.new()
	title.text = "GAME OVER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	col.add_child(title)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_label)

	_retry = Button.new()
	_retry.text = "重试"
	_retry.pressed.connect(_on_retry)
	col.add_child(_retry)

	_continue_story = Button.new()
	_continue_story.text = "继续剧情"
	_continue_story.pressed.connect(_on_continue_story)
	col.add_child(_continue_story)

	_title = Button.new()
	_title.text = "返回标题"
	_title.pressed.connect(_on_title)
	col.add_child(_title)

	visible = false


func show_game_over(payload: Dictionary) -> void:
	_payload = payload
	_label.text = str(payload.get("reason", "小凌失去了意识……"))
	visible = true


func _on_retry() -> void:
	visible = false
	EventBus.game_over_retry.emit()


func _on_continue_story() -> void:
	visible = false
	SceneManager.go_to("part4_mystery_girl")


func _on_title() -> void:
	visible = false
	SceneManager.present_title.emit()
