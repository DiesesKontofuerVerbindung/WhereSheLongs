extends Control
## Hand-checkbox Godot runner: show p1/p2, camera gesture, save via GameState.

const ClientScript := preload("res://addons/hand_checkbox_gesture/detection/native_hand_client.gd")
const P1_PATH := "res://addons/hand_checkbox_gesture/assets/p1.png"
const P2_PATH := "res://addons/hand_checkbox_gesture/assets/p2.png"
const RESULT_PATH := "user://hand_checkbox_result.json"
const HINT_TEXT := "用手势在checklist上打勾"
const HINT_SECONDS := 3.0

@onready var background: TextureRect = $Background
@onready var hint_label: Label = $Hint
@onready var status_label: Label = $Status

var _client: Node
var _done := false
var _hint_age := 0.0
var _started_unix := 0.0
var _auto_mode := ""
var _tex_p1: Texture2D
var _tex_p2: Texture2D


func _ready() -> void:
	_auto_mode = OS.get_environment("HAND_CHECKBOX_AUTO").strip_edges().to_lower()
	_started_unix = Time.get_unix_time_from_system()
	_tex_p1 = _load_texture(P1_PATH)
	_tex_p2 = _load_texture(P2_PATH)
	if _tex_p1 == null:
		status_label.text = "贴图加载失败: p1.png"
		push_error("HandCheckbox: p1 texture missing at %s" % ProjectSettings.globalize_path(P1_PATH))
	_show_p1()
	hint_label.text = HINT_TEXT
	hint_label.visible = true
	hint_label.modulate.a = 1.0

	_client = ClientScript.new()
	_client.name = "NativeHandCheckboxClient"
	add_child(_client)
	_client.checked.connect(_on_checked)
	_client.camera_status.connect(_on_camera_status)
	_client.frame.connect(_on_frame)
	_client.connection_changed.connect(_on_connection_changed)
	status_label.text = "正在启动摄像头…"
	_client.start()

	if _auto_mode == "mouse":
		await get_tree().create_timer(1.5).timeout
		_complete("mouse_auto")


func _process(delta: float) -> void:
	if hint_label.visible:
		_hint_age += delta
		if _hint_age >= HINT_SECONDS:
			hint_label.visible = false
		else:
			var fade_start := HINT_SECONDS - 0.6
			if _hint_age > fade_start:
				hint_label.modulate.a = maxf(0.0, 1.0 - (_hint_age - fade_start) / 0.6)


func _gui_input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_complete("mouse")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q or event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif event.keycode == KEY_R and not _done:
			_reset()


func _on_checked(payload: Dictionary) -> void:
	_complete(str(payload.get("source", "gesture")), payload)


func _on_camera_status(payload: Dictionary) -> void:
	var ok := bool(payload.get("ok", false))
	if ok:
		status_label.text = "摄像头已连接 — 用手画 ✓"
	else:
		status_label.text = "摄像头失败：%s（可鼠标点击）" % str(payload.get("error", ""))


func _on_frame(payload: Dictionary) -> void:
	if _done:
		return
	if bool(payload.get("hand", false)):
		if not status_label.text.begins_with("已"):
			status_label.text = "检测到手 — 画勾"


func _on_connection_changed(is_connected: bool) -> void:
	if _done:
		return
	if is_connected:
		if status_label.text.begins_with("正在") or status_label.text.begins_with("手势"):
			status_label.text = "手势服务已连接，等待摄像头…"
	else:
		status_label.text = "手势服务连接中…"


func _show_p1() -> void:
	background.texture = _tex_p1


func _show_p2() -> void:
	background.texture = _tex_p2


func _load_texture(path: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		push_error("HandCheckbox: file missing %s" % abs_path)
		return null
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	if bytes.is_empty():
		push_error("HandCheckbox: empty file %s" % abs_path)
		return null
	var image := Image.new()
	var err := OK
	if path.ends_with(".png"):
		err = image.load_png_from_buffer(bytes)
	elif path.ends_with(".jpg") or path.ends_with(".jpeg"):
		err = image.load_jpg_from_buffer(bytes)
	else:
		err = image.load(abs_path)
	if err != OK:
		push_error("HandCheckbox: decode failed %s err=%s" % [abs_path, err])
		return null
	return ImageTexture.create_from_image(image)


func _complete(source: String, payload: Dictionary = {}) -> void:
	if _done:
		return
	_done = true
	hint_label.visible = false
	_show_p2()
	var result := {
		"ok": true,
		"source": source,
		"profile": str(payload.get("profile", "")),
		"started_unix": _started_unix,
		"finished_unix": Time.get_unix_time_from_system(),
		"scene": "p2",
		"plugin": "hand_checkbox_gesture",
		"camera_connected": _client != null and bool(_client.get("connected")),
	}
	GameState.set_flag(&"hand_checkbox_done", true)
	GameState.set_flag(&"hand_checkbox_result", result)
	_save_result(result)
	status_label.text = "已保存到桌面 hand_checkbox_result.json"
	# Only auto-quit in CI/auto mode so interactive play can see p2.
	if not _auto_mode.is_empty():
		await get_tree().create_timer(1.2).timeout
		get_tree().quit()


func _save_result(result: Dictionary) -> void:
	var text := JSON.stringify(result, "\t")
	var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()
		print("HandCheckbox saved: ", ProjectSettings.globalize_path(RESULT_PATH))
	var mirror := "res://addons/hand_checkbox_gesture/last_result.json"
	var mirror_file := FileAccess.open(mirror, FileAccess.WRITE)
	if mirror_file:
		mirror_file.store_string(text)
		mirror_file.close()
	var desktop := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join("hand_checkbox_result.json")
	var desk_file := FileAccess.open(desktop, FileAccess.WRITE)
	if desk_file:
		desk_file.store_string(text)
		desk_file.close()
		print("HandCheckbox desktop copy: ", desktop)


func _reset() -> void:
	_done = false
	_hint_age = 0.0
	_started_unix = Time.get_unix_time_from_system()
	hint_label.modulate.a = 1.0
	hint_label.visible = true
	hint_label.text = HINT_TEXT
	status_label.text = "已重置 — 用手画 ✓ 或点击"
	_show_p1()
	GameState.erase_flag(&"hand_checkbox_done")
	GameState.erase_flag(&"hand_checkbox_result")
