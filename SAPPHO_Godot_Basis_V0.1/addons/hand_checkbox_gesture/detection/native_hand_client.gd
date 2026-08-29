extends Node
## TCP client for native_hand_checkbox.py — spawns venv Python and keeps camera alive.

signal checked(payload: Dictionary)
signal frame(payload: Dictionary)
signal camera_status(payload: Dictionary)
signal connection_changed(connected: bool)

const HOST := "127.0.0.1"
const PORT := 8771

var connected: bool = false
var _tcp := StreamPeerTCP.new()
var _buf := PackedByteArray()
var _pid: int = -1
var _retry_at: float = 0.0
var _spawned: bool = false
var _spawn_attempts: int = 0


func start() -> void:
	_spawn_detector()
	_connect()


func stop() -> void:
	if _tcp.get_status() != StreamPeerTCP.STATUS_NONE:
		_tcp.disconnect_from_host()
	connected = false
	if _pid > 0:
		OS.kill(_pid)
		_pid = -1
		_spawned = false


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	_tcp.poll()
	var status := _tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			connection_changed.emit(true)
		_read_packets()
		return
	if connected:
		connected = false
		connection_changed.emit(false)
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	if _pid > 0 and not OS.is_process_running(_pid):
		_write_log("detector process exited pid=%s" % _pid)
		_spawned = false
		_pid = -1
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _retry_at:
		_retry_at = now + 1.0
		if not _spawned:
			_spawn_detector()
		_connect()


func _connect() -> void:
	if _tcp.get_status() != StreamPeerTCP.STATUS_NONE:
		_tcp.disconnect_from_host()
	_tcp = StreamPeerTCP.new()
	_tcp.connect_to_host(HOST, PORT)
	_buf = PackedByteArray()


func _spawn_detector() -> void:
	if _spawn_attempts > 8:
		return
	_spawn_attempts += 1
	var python := _python_path()
	var script := _script_path()
	_write_log("spawn attempt=%s python=%s script=%s" % [_spawn_attempts, python, script])
	if python.is_empty() or script.is_empty():
		push_warning("HandCheckbox: Python or script not found")
		camera_status.emit({"ok": false, "error": "python/script missing"})
		return
	var work_dir := script.get_base_dir()
	# Godot 4 create_process(path, args, blocking) — set cwd via absolute script is enough.
	_pid = OS.create_process(python, PackedStringArray([script]), false)
	_spawned = _pid > 0
	_write_log("pid=%s cwd=%s" % [_pid, work_dir])
	if not _spawned:
		camera_status.emit({"ok": false, "error": "failed to spawn detector"})


func _write_log(text: String) -> void:
	var path := "user://hand_checkbox_spawn.log"
	var prev := ""
	if FileAccess.file_exists(path):
		prev = FileAccess.get_file_as_string(path)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(prev + "%s %s\n" % [Time.get_datetime_string_from_system(), text])
		file.close()


func _python_path() -> String:
	var candidates: PackedStringArray = [
		"C:/Users/liuxi/Desktop/Peking26082026/.venv/Scripts/python.exe",
		ProjectSettings.globalize_path("res://../.venv/Scripts/python.exe"),
		OS.get_environment("LOCALAPPDATA").path_join("Programs/Python/Python312/python.exe"),
		"C:/Users/liuxi/AppData/Local/Programs/Python/Python312/python.exe",
	]
	for path in candidates:
		var p := path.replace("\\", "/")
		if FileAccess.file_exists(p):
			return p.replace("/", "\\")
		# OS path check fallback
		if FileAccess.file_exists(path):
			return path
	# Last resort: where.exe via OS — keep empty if none
	return "C:\\Users\\liuxi\\Desktop\\Peking26082026\\.venv\\Scripts\\python.exe"


func _script_path() -> String:
	var rel := "res://addons/hand_checkbox_gesture/detection/native_hand_checkbox.py"
	if ResourceLoader.exists(rel) or FileAccess.file_exists(rel):
		return ProjectSettings.globalize_path(rel)
	var abs_guess := "C:/Users/liuxi/Desktop/Peking26082026/SAPPHO_Godot_Basis_V0.1/addons/hand_checkbox_gesture/detection/native_hand_checkbox.py"
	if FileAccess.file_exists(abs_guess):
		return abs_guess.replace("/", "\\")
	return ""


func _read_packets() -> void:
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return
	var result: Array = _tcp.get_partial_data(available)
	if int(result[0]) != OK:
		return
	var chunk: PackedByteArray = result[1]
	_buf.append_array(chunk)
	while true:
		var newline := _buf.find(10)
		if newline < 0:
			break
		var line := _buf.slice(0, newline).get_string_from_utf8()
		_buf = _buf.slice(newline + 1)
		_handle_line(line)


func _handle_line(line: String) -> void:
	if line.is_empty():
		return
	var data = JSON.parse_string(line)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var payload: Dictionary = data
	match str(payload.get("type", "")):
		"checked":
			checked.emit(payload)
		"frame":
			frame.emit(payload)
		"camera":
			camera_status.emit(payload)
		_:
			pass
