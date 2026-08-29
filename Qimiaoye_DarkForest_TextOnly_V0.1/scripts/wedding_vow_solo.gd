extends Control

## 婚礼交互模块1：小凌一个人把誓词念完。
##
## 原文只留下了模块名。按上下文补成独角戏：新郎没到，主持人问"后面的流程还过吗"，
## 小凌说"我自己来吧"。誓词的每一句都要玩家自己按下去——空场的分量得由玩家承担，
## 不能用一段自动播放的过场糊过去。

const VOW_LINES := [
	"我愿意在往后的每一天里，认真地喜欢你。",
	"我愿意在你疲惫的时候，先放下我自己的事。",
	"我愿意在很多年以后，还记得今天为什么站在这里。",
]

const COLOR_CARD := Color(0.10, 0.09, 0.12, 0.94)
const COLOR_TEXT := Color(0.92, 0.90, 0.86, 1.0)
const COLOR_MUTED := Color(0.60, 0.58, 0.64, 1.0)

var _spoken := 0
var _advance_requested := false
var _vow_label: Label
var _progress_label: Label
var _hint_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -320
	card.offset_right = 320
	card.offset_top = -110
	card.offset_bottom = 110
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_CARD
	card_style.corner_radius_top_left = 6
	card_style.corner_radius_top_right = 6
	card_style.corner_radius_bottom_left = 6
	card_style.corner_radius_bottom_right = 6
	card_style.content_margin_left = 28
	card_style.content_margin_right = 28
	card_style.content_margin_top = 22
	card_style.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", card_style)
	add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	card.add_child(column)

	var title := Label.new()
	title.text = "誓词卡"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(title)

	_vow_label = Label.new()
	_vow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vow_label.custom_minimum_size = Vector2(0, 92)
	_vow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vow_label.add_theme_font_size_override("font_size", 20)
	_vow_label.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(_vow_label)

	_progress_label = Label.new()
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", 13)
	_progress_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(_progress_label)

	_hint_label = Label.new()
	_hint_label.text = "按 Enter / Space 念下一句"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(_hint_label)

	_refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_advance_requested = true
		get_viewport().set_input_as_handled()


func run(verify_mode := false) -> void:
	while _spoken < VOW_LINES.size():
		if verify_mode:
			_advance_requested = true
		if _advance_requested:
			_advance_requested = false
			_spoken += 1
			_refresh()
			continue
		await get_tree().process_frame
	# 念完之后停一拍，让最后一句留在空场里。
	if not verify_mode:
		await get_tree().create_timer(1.2).timeout


func _refresh() -> void:
	var index := clampi(_spoken, 0, VOW_LINES.size() - 1)
	_vow_label.text = VOW_LINES[index]
	_progress_label.text = "%d / %d" % [mini(_spoken + 1, VOW_LINES.size()), VOW_LINES.size()]
	if _spoken >= VOW_LINES.size() - 1:
		_hint_label.text = "念完了。对面没有人接。"


func get_debug_snapshot() -> Dictionary:
	return {"vow_spoken": _spoken, "vow_total": VOW_LINES.size()}
