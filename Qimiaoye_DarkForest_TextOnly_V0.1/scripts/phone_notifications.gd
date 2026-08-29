extends Control

## 婚礼交互模块2：思雨的手机不停跳消息。
##
## 对应原文"手机屏幕上不断跳出新的消息"。玩家可以一条条划掉，
## 但下一条马上就来——划不完是设计，不是 bug。划到第 DISMISS_TARGET 条时
## 思雨抬头说"我可能得先走了"，交互才结束。

const DISMISS_TARGET := 6
const NEXT_MESSAGE_SECONDS := 0.85

const MESSAGES := [
	["#线上告警", "支付回调超时，5 分钟内 12 次"],
	["组长", "在吗？生产环境有点问题"],
	["#线上告警", "错误率还在涨"],
	["组长", "你今天 on call 吧"],
	["#值班群", "有人能看一下吗"],
	["组长", "方便的话现在回公司一趟"],
	["#线上告警", "又来了"],
	["组长", "？"],
]

const COLOR_PHONE := Color(0.08, 0.08, 0.10, 0.96)
const COLOR_CARD := Color(0.16, 0.16, 0.19, 1.0)
const COLOR_TEXT := Color(0.90, 0.89, 0.92, 1.0)
const COLOR_MUTED := Color(0.58, 0.57, 0.62, 1.0)

var _dismissed := 0
var _next_message := 0
var _message_column: VBoxContainer
var _counter_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var phone := PanelContainer.new()
	phone.set_anchors_preset(Control.PRESET_CENTER)
	phone.offset_left = -190
	phone.offset_right = 190
	phone.offset_top = -240
	phone.offset_bottom = 240
	var phone_style := StyleBoxFlat.new()
	phone_style.bg_color = COLOR_PHONE
	phone_style.corner_radius_top_left = 22
	phone_style.corner_radius_top_right = 22
	phone_style.corner_radius_bottom_left = 22
	phone_style.corner_radius_bottom_right = 22
	phone_style.content_margin_left = 16
	phone_style.content_margin_right = 16
	phone_style.content_margin_top = 20
	phone_style.content_margin_bottom = 20
	phone.add_theme_stylebox_override("panel", phone_style)
	add_child(phone)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	phone.add_child(column)

	var header := Label.new()
	header.text = "思雨的手机"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(header)

	_message_column = VBoxContainer.new()
	_message_column.add_theme_constant_override("separation", 10)
	_message_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_message_column)

	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", 12)
	_counter_label.add_theme_color_override("font_color", COLOR_MUTED)
	column.add_child(_counter_label)

	_refresh_counter()


func run(verify_mode := false) -> void:
	_push_message()
	while _dismissed < DISMISS_TARGET:
		if verify_mode:
			_dismiss_oldest()
			continue
		await get_tree().create_timer(NEXT_MESSAGE_SECONDS).timeout
		# 玩家划得再快也追不上：只要还没到目标，新消息就继续来。
		if _dismissed < DISMISS_TARGET:
			_push_message()
	if not verify_mode:
		await get_tree().create_timer(0.9).timeout


func _push_message() -> void:
	var payload: Array = MESSAGES[_next_message % MESSAGES.size()]
	_next_message += 1

	var card := PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_CARD
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 9
	card_style.content_margin_bottom = 9
	card.add_theme_stylebox_override("panel", card_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_column)

	var sender := Label.new()
	sender.text = str(payload[0])
	sender.add_theme_font_size_override("font_size", 12)
	sender.add_theme_color_override("font_color", COLOR_MUTED)
	text_column.add_child(sender)

	var body := Label.new()
	body.text = str(payload[1])
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", COLOR_TEXT)
	text_column.add_child(body)

	var dismiss := Button.new()
	dismiss.text = "×"
	dismiss.custom_minimum_size = Vector2(30, 30)
	dismiss.pressed.connect(_on_dismiss_pressed.bind(card))
	row.add_child(dismiss)

	_message_column.add_child(card)


func _on_dismiss_pressed(card: Control) -> void:
	if not is_instance_valid(card):
		return
	card.queue_free()
	_dismissed += 1
	_refresh_counter()


func _dismiss_oldest() -> void:
	for child in _message_column.get_children():
		if is_instance_valid(child):
			child.queue_free()
			_dismissed += 1
			_refresh_counter()
			return
	# 没有可划的就先补一条，verify 模式下才不会空转。
	_push_message()


func _refresh_counter() -> void:
	_counter_label.text = "已划掉 %d 条" % _dismissed


func get_debug_snapshot() -> Dictionary:
	return {"phone_dismissed": _dismissed, "phone_target": DISMISS_TARGET}
