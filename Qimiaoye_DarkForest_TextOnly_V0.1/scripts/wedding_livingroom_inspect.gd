extends Control

## 婚礼客厅「选中查看物品」（来自 Peking26082026 livingroom_memories）。
## 不依赖 SAPPHO 的 Dialogue / GameState / SceneManager；自带叠层对白。
## 宿主契约：run(verify_mode) 协程。

const PROP_LINES := {
	"game_console": {
		"speaker": "游戏机",
		"text": "小仓送给小凌的。他说以后下班可以一起玩。后来大部分时间都是小仓一个人在玩。",
	},
	"climbing_shoes": {
		"speaker": "攀岩鞋",
		"text": "小仓送给小凌。他说：“你不是一直想试试吗？”但是包装从来没有拆开。",
	},
	"movie_tickets": {
		"speaker": "电影票",
		"text": "两个人曾经一起看电影。小凌被电影感动，转头想和小仓说话。小仓睡着了。",
	},
}

const CLOSING_TEXT := "三件东西都看过了。这个房间里的回忆，到这里就够了。"
const BG_PATH := "res://assets/wedding/livingroom_base.jpg"
const PROP_TEXTURES := {
	"game_console": "res://assets/wedding/props/game_console.png",
	"climbing_shoes": "res://assets/wedding/props/climbing_shoes.png",
	"movie_tickets": "res://assets/wedding/props/movie_tickets.png",
}

## 相对 1280×720 设计的热点框。
const HOTSPOTS := {
	"game_console": Rect2(125, 295, 180, 105),
	"movie_tickets": Rect2(608, 468, 195, 105),
	"climbing_shoes": Rect2(1060, 220, 150, 120),
}

const COLOR_TEXT := Color(0.92, 0.90, 0.86, 1.0)
const COLOR_MUTED := Color(0.70, 0.68, 0.64, 1.0)

var _viewed: Dictionary = {}
var _ending := false
var _line_open := false
var _pending_prop := ""
var _finished := false
var _hint: Label
var _line_panel: PanelContainer
var _line_speaker: Label
var _line_body: Label
var _hotspot_root: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh_hint()


func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH) as Texture2D
	add_child(bg)

	var title := Label.new()
	title.text = "搬家前的客厅"
	title.offset_left = 36
	title.offset_top = 24
	title.offset_right = 520
	title.offset_bottom = 64
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.78, 0.92))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	_hint = Label.new()
	_hint.offset_left = 36
	_hint.offset_top = 64
	_hint.offset_right = 720
	_hint.offset_bottom = 100
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_color", COLOR_MUTED)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_hotspot_root = Control.new()
	_hotspot_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hotspot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hotspot_root)

	for prop_id in HOTSPOTS.keys():
		var rect: Rect2 = HOTSPOTS[prop_id]
		var button := Button.new()
		button.name = prop_id
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.position = rect.position
		button.size = rect.size
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var normal := StyleBoxEmpty.new()
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.96, 0.85, 0.68, 0.1)
		hover.set_border_width_all(1)
		hover.border_color = Color(0.96, 0.85, 0.68, 0.4)
		hover.set_corner_radius_all(8)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_hotspot_root.add_child(button)

		var tex_path := str(PROP_TEXTURES.get(prop_id, ""))
		if ResourceLoader.exists(tex_path):
			var icon := TextureRect.new()
			icon.name = "Icon"
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.texture = load(tex_path) as Texture2D
			icon.modulate = Color(0.92, 0.88, 0.82, 1.0)
			button.add_child(icon)

		button.pressed.connect(_on_prop_pressed.bind(prop_id))

	_line_panel = PanelContainer.new()
	_line_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_line_panel.offset_left = -420
	_line_panel.offset_right = 420
	_line_panel.offset_top = -190
	_line_panel.offset_bottom = -36
	_line_panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.09, 0.92)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	_line_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_line_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_line_panel.add_child(col)

	_line_speaker = Label.new()
	_line_speaker.add_theme_font_size_override("font_size", 14)
	_line_speaker.add_theme_color_override("font_color", COLOR_MUTED)
	col.add_child(_line_speaker)

	_line_body = Label.new()
	_line_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_body.add_theme_font_size_override("font_size", 18)
	_line_body.add_theme_color_override("font_color", COLOR_TEXT)
	_line_body.custom_minimum_size = Vector2(0, 72)
	col.add_child(_line_body)

	var continue_hint := Label.new()
	continue_hint.text = "点击 / Enter 继续"
	continue_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_hint.add_theme_font_size_override("font_size", 12)
	continue_hint.add_theme_color_override("font_color", COLOR_MUTED)
	col.add_child(continue_hint)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if _line_open:
			_close_line()
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _line_open:
			_close_line()
			accept_event()


func run(verify_mode := false) -> void:
	if verify_mode:
		for prop_id in PROP_LINES.keys():
			_viewed[prop_id] = true
		_finished = true
		return
	while not _finished:
		await get_tree().process_frame


func _on_prop_pressed(prop_id: String) -> void:
	if _ending or _line_open or _finished:
		return
	if _viewed.get(prop_id, false):
		_hint.text = "已经看过了"
		return
	var line: Dictionary = PROP_LINES.get(prop_id, {})
	if line.is_empty():
		return
	_pending_prop = prop_id
	_show_line(str(line.get("speaker", "")), str(line.get("text", "")))


func _show_line(speaker: String, text: String) -> void:
	_line_open = true
	_line_speaker.text = speaker
	_line_body.text = text
	_line_panel.visible = true


func _close_line() -> void:
	if not _line_open:
		return
	_line_open = false
	_line_panel.visible = false

	if _ending:
		_finished = true
		return

	if _pending_prop.is_empty():
		return

	var prop_id := _pending_prop
	_pending_prop = ""
	_viewed[prop_id] = true
	_mark_done(prop_id)
	_refresh_hint()
	if _viewed.size() >= PROP_LINES.size():
		_begin_ending()


func _begin_ending() -> void:
	_ending = true
	_hint.text = "回忆结束"
	for child in _hotspot_root.get_children():
		if child is Button:
			(child as Button).disabled = true
	_show_line("", CLOSING_TEXT)


func _mark_done(prop_id: String) -> void:
	var button := _hotspot_root.get_node_or_null(prop_id) as Button
	if button == null:
		return
	var icon := button.get_node_or_null("Icon") as CanvasItem
	if icon:
		icon.modulate = Color(0.55, 0.55, 0.55, 0.7)
	button.disabled = true


func _refresh_hint() -> void:
	var done := _viewed.size()
	var total := PROP_LINES.size()
	if done >= total:
		_hint.text = "回忆结束"
	elif done == 0:
		_hint.text = "点击角落里散落的物品（0/%d）" % total
	else:
		_hint.text = "已查看 %d/%d" % [done, total]


func get_debug_snapshot() -> Dictionary:
	return {"livingroom_viewed": _viewed.size(), "livingroom_done": _finished}
