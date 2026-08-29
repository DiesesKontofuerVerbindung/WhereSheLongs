extends Control

## 婚礼用 checklist 模块（Peking26082026 hand_checkbox_gesture）。
## 启动摄像头手势打勾：p1 → 空中打勾 → p2。
## 鼠标点击 / Enter 仍可作回退。verify 模式不启摄像头。

const ClientScript := preload("res://addons/hand_checkbox_gesture/detection/native_hand_client.gd")
const P1_PATH := "res://addons/hand_checkbox_gesture/assets/p1.png"
const P2_PATH := "res://addons/hand_checkbox_gesture/assets/p2.png"

const COLOR_HINT := Color(0.92, 0.90, 0.86, 1.0)
const COLOR_STATUS := Color(0.75, 0.73, 0.70, 0.9)
const HINT_SECONDS := 3.0
const AUTO_DISMISS_SECONDS := 2.0

var _done := false
var _advance_requested := false
var _background: TextureRect
var _hint: Label
var _status: Label
var _tex_p1: Texture2D
var _tex_p2: Texture2D
var _variant := "1"
var _client: Node
var _hint_age := 0.0
var _camera_ok := false


func setup(variant: String) -> void:
	_variant = variant


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	_background = TextureRect.new()
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -360
	_hint.offset_right = 360
	_hint.offset_top = -120
	_hint.offset_bottom = -64
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", COLOR_HINT)
	_hint.text = "用手势在清单上打勾（也可点击 / Enter）"
	add_child(_hint)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 20
	_status.offset_top = -48
	_status.offset_right = 720
	_status.offset_bottom = -14
	_status.add_theme_font_size_override("font_size", 14)
	_status.add_theme_color_override("font_color", COLOR_STATUS)
	_status.text = "Checklist %s · 正在启动摄像头…" % _variant
	add_child(_status)

	_tex_p1 = _load_tex(P1_PATH)
	_tex_p2 = _load_tex(P2_PATH)
	_background.texture = _tex_p1 if _tex_p1 != null else _tex_p2
	if _tex_p1 == null:
		_status.text = "清单图加载失败"


func _process(delta: float) -> void:
	if _done or not _hint.visible:
		return
	_hint_age += delta
	if _hint_age >= HINT_SECONDS:
		_hint.visible = false
	else:
		var fade_start := HINT_SECONDS - 0.6
		if _hint_age > fade_start:
			_hint.modulate.a = maxf(0.0, 1.0 - (_hint_age - fade_start) / 0.6)


func _gui_input(event: InputEvent) -> void:
	# 打勾完成后仍吞掉点击，避免渗进下一句对白。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _done:
			_advance_requested = true
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if not _done:
			_advance_requested = true
		# 完成后也要吃掉，防止同一按键推进下一句。
		get_viewport().set_input_as_handled()


func run(verify_mode := false) -> void:
	if verify_mode:
		_complete("verify")
		return

	if AUTO_DISMISS_SECONDS > 0.0:
		_status.text = "Checklist %s · 即将自动完成" % _variant
		await get_tree().create_timer(AUTO_DISMISS_SECONDS).timeout
		_complete("success")
	else:
		_start_camera()
		while not _done:
			if _advance_requested:
				_advance_requested = false
				_complete("mouse")
				break
			await get_tree().process_frame
	_stop_camera()
	# 展示打勾结果，并排空残留输入，再把控制权交回剧情。
	await get_tree().create_timer(0.9).timeout
	_advance_requested = false
	for _i in range(10):
		await get_tree().process_frame


func _start_camera() -> void:
	if _client != null:
		return
	_client = ClientScript.new()
	_client.name = "NativeHandCheckboxClient"
	add_child(_client)
	_client.checked.connect(_on_checked)
	_client.camera_status.connect(_on_camera_status)
	_client.frame.connect(_on_frame)
	_client.connection_changed.connect(_on_connection_changed)
	_status.text = "Checklist %s · 正在启动摄像头…" % _variant
	_client.start()


func _stop_camera() -> void:
	if _client == null:
		return
	if _client.has_method("stop"):
		_client.call("stop")
	if is_instance_valid(_client):
		_client.queue_free()
	_client = null


func _on_checked(payload: Dictionary) -> void:
	_complete(str(payload.get("source", "gesture")))


func _on_camera_status(payload: Dictionary) -> void:
	if _done:
		return
	_camera_ok = bool(payload.get("ok", false))
	if _camera_ok:
		_status.text = "Checklist %s · 摄像头已连接 — 用手势打勾" % _variant
	else:
		var err := str(payload.get("error", ""))
		if err == "starting":
			_status.text = "Checklist %s · 正在打开摄像头…" % _variant
		else:
			_status.text = "Checklist %s · 摄像头失败：%s（可点击/Enter）" % [_variant, err]


func _on_frame(payload: Dictionary) -> void:
	if _done:
		return
	var hand := bool(payload.get("hand", false))
	var state := str(payload.get("state", ""))
	var phase := str(payload.get("phase", ""))
	var fail := str(payload.get("fail", ""))
	var progress := int(payload.get("progress", 0))
	if hand:
		var tip := "画勾：先向下，再向右上（进度 %d/3）" % progress
		if fail != "":
			tip = "重试画勾（%s）" % fail
		_status.text = "Checklist %s · 手势 %s/%s · %s" % [_variant, state, phase, tip]
	else:
		_status.text = "Checklist %s · 未检测到手 · 请把手伸到镜头前" % _variant


func _on_connection_changed(is_connected: bool) -> void:
	if _done:
		return
	if is_connected:
		_status.text = "Checklist %s · 手势服务已连接，等待摄像头…" % _variant
	else:
		_status.text = "Checklist %s · 手势服务连接中…" % _variant


func _complete(source: String) -> void:
	if _done:
		return
	_done = true
	_hint.visible = false
	if _tex_p2 != null:
		_background.texture = _tex_p2
	_status.text = "Checklist %s · 完成（%s）" % [_variant, source]


func _load_tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func get_debug_snapshot() -> Dictionary:
	return {
		"checklist_variant": _variant,
		"checklist_done": _done,
		"checklist_camera": _camera_ok,
	}
