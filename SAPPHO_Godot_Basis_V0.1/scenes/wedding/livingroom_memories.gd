extends Control
## Night living-room memory inspect: click scattered props for story lines.
## Ends after all three props have been viewed.

const PROP_LINES := {
	"game_console": {
		"speaker": "游戏机",
		"text": "小仓送给小凌的。他说以后下班可以一起玩。后来大部分时间都是小仓一个人在玩。",
	},
	"climbing_shoes": {
		"speaker": "攀岩鞋",
		"text": "小仓送给小凌。他说；“你不是一直想试试吗？”但是包装从来没有拆开。",
	},
	"movie_tickets": {
		"speaker": "电影票",
		"text": "两个人曾经一起看电影。小凌被电影感动，转头想和小仓说话。小仓睡着了。",
	},
}

const CLOSING_TEXT := "三件东西都看过了。这个房间里的回忆，到这里就够了。"
const NEXT_SCENE := "res://scenes/wedding/wedding.tscn"

@onready var hint_label: Label = $Hint
@onready var back_button: Button = $BackButton

var _viewed: Dictionary = {} # prop_id -> true
var _pending_prop: String = ""
var _ending := false
var _awaiting_close := false


func _ready() -> void:
	for prop_id in PROP_LINES.keys():
		var button := get_node_or_null("Hotspots/%s" % prop_id) as Button
		if button == null:
			continue
		_style_hotspot(button)
		button.pressed.connect(_on_prop_pressed.bind(prop_id))
		button.mouse_entered.connect(_on_prop_hover.bind(prop_id, true))
		button.mouse_exited.connect(_on_prop_hover.bind(prop_id, false))
	back_button.pressed.connect(_on_back_pressed)
	if not Dialogue.dialogue_closed.is_connected(_on_dialogue_closed):
		Dialogue.dialogue_closed.connect(_on_dialogue_closed)
	_refresh_hint()


func _exit_tree() -> void:
	if Dialogue.dialogue_closed.is_connected(_on_dialogue_closed):
		Dialogue.dialogue_closed.disconnect(_on_dialogue_closed)


func _style_hotspot(button: Button) -> void:
	button.flat = true
	button.modulate = Color.WHITE
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
	button.add_theme_stylebox_override("disabled", normal)


func _on_prop_hover(prop_id: String, entered: bool) -> void:
	if _ending:
		return
	var button := get_node_or_null("Hotspots/%s" % prop_id) as Control
	if button and not _viewed.get(prop_id, false):
		var icon := button.get_node_or_null("Icon") as CanvasItem
		var target := icon if icon else button
		target.modulate = Color(1.12, 1.08, 1.0, 1.0) if entered else Color(0.92, 0.88, 0.82, 1.0)
	if entered:
		if _viewed.get(prop_id, false):
			hint_label.text = "已经看过了"
		else:
			var line: Dictionary = PROP_LINES.get(prop_id, {})
			hint_label.text = "点击查看：%s" % str(line.get("speaker", ""))
	else:
		_refresh_hint()


func _on_prop_pressed(prop_id: String) -> void:
	if _ending or _awaiting_close:
		return
	if Dialogue.is_open():
		return
	if _viewed.get(prop_id, false):
		hint_label.text = "已经看过了"
		return
	var line: Dictionary = PROP_LINES.get(prop_id, {})
	if line.is_empty():
		return
	_pending_prop = prop_id
	_awaiting_close = true
	Dialogue.show_line(str(line["speaker"]), str(line["text"]))


func _on_dialogue_closed() -> void:
	if not _awaiting_close:
		return
	_awaiting_close = false

	if _ending:
		_finish_scene()
		return

	if _pending_prop.is_empty():
		return

	var prop_id := _pending_prop
	_pending_prop = ""
	_viewed[prop_id] = true
	_mark_prop_done(prop_id)
	_refresh_hint()

	if _viewed.size() >= PROP_LINES.size():
		_begin_ending()


func _begin_ending() -> void:
	_ending = true
	_awaiting_close = true
	hint_label.text = "回忆结束"
	for prop_id in PROP_LINES.keys():
		var button := get_node_or_null("Hotspots/%s" % prop_id) as Button
		if button:
			button.disabled = true
	back_button.disabled = true
	Dialogue.show_line("", CLOSING_TEXT)


func _finish_scene() -> void:
	GameState.set_flag(&"livingroom_memories_done", true)
	SceneManager.change_scene(NEXT_SCENE)


func _mark_prop_done(prop_id: String) -> void:
	var button := get_node_or_null("Hotspots/%s" % prop_id) as Button
	if button == null:
		return
	var icon := button.get_node_or_null("Icon") as CanvasItem
	if icon:
		icon.modulate = Color(0.55, 0.55, 0.55, 0.7)
	else:
		button.modulate = Color(0.55, 0.55, 0.55, 0.55)
	button.disabled = true


func _refresh_hint() -> void:
	var done := _viewed.size()
	var total := PROP_LINES.size()
	if done >= total:
		hint_label.text = "回忆结束"
	elif done == 0:
		hint_label.text = "点击角落里散落的物品（0/%d）" % total
	else:
		hint_label.text = "已查看 %d/%d" % [done, total]


func _on_back_pressed() -> void:
	if _ending or _awaiting_close:
		return
	SceneManager.change_scene(NEXT_SCENE)
