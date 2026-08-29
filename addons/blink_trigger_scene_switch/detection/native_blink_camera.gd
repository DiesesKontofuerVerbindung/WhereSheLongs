class_name NativeBlinkCamera
extends Node

## TCP client for native_webcam.py (same protocol as closed-eye). Blink events are classified in Godot.

signal frame(payload: Dictionary)
signal connection_changed(connected: bool)

const HOST := "127.0.0.1"
const PORT := 8766

var connected: bool = false
var _tcp := StreamPeerTCP.new()
var _buf := ""
var _pid: int = -1
var _retry_at: float = 0.0
var _spawned: bool = false


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


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_tcp.poll()
		if not connected:
			connected = true
			connection_changed.emit(true)
		_read_packets()
		return
	if connected:
		connected = false
		connection_changed.emit(false)
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _retry_at:
		_retry_at = now + 0.6
		if not _spawned:
			_spawn_detector()
		_connect()


func _connect() -> void:
	_tcp = StreamPeerTCP.new()
	_tcp.connect_to_host(HOST, PORT)
	_buf = ""


func _spawn_detector() -> void:
	var python := _python_path()
	var script := _script_path()
	_write_log("python=%s script=%s" % [python, script])
	if python.is_empty() or script.is_empty():
		push_warning("Blink: Python or native_webcam.py not found")
		return
	# open_console=true：弹出控制台 + OpenCV 摄像头预览窗
	_pid = OS.create_process(python, PackedStringArray([script]), true)
	_spawned = _pid > 0
	_write_log("pid=%s" % _pid)
	if not _spawned:
		push_warning("Blink: failed to start native webcam process")


func _write_log(text: String) -> void:
	var path := "user://blink_spawn.log"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text + "\n")
		file.close()


func _python_path() -> String:
	var home := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	var candidates: PackedStringArray = [
		home + "/Programs/Python/Python312/python.exe",
		home + "/Programs/Python/Python313/python.exe",
		home + "/Programs/Python/Python311/python.exe",
		"C:/Users/liuxi/AppData/Local/Programs/Python/Python312/python.exe",
	]
	for path in candidates:
		if FileAccess.file_exists(path):
			return path.replace("/", "\\")
	return ""


func _script_path() -> String:
	var rel := "res://addons/blink_trigger_scene_switch/detection/native_webcam.py"
	if FileAccess.file_exists(rel):
		return ProjectSettings.globalize_path(rel)
	# Fallback to closed-eye copy if present
	var alt := "res://addons/closed_eye_trigger_scene_switch/detection/native_webcam.py"
	if FileAccess.file_exists(alt):
		return ProjectSettings.globalize_path(alt)
	return ""


func _read_packets() -> void:
	var available := _tcp.get_available_bytes()
	if available <= 0:
		return
	var incoming := _tcp.get_utf8_string(available)
	if incoming.is_empty():
		return
	_buf += incoming
	while true:
		var nl := _buf.find("\n")
		if nl < 0:
			break
		var line := _buf.substr(0, nl).strip_edges()
		_buf = _buf.substr(nl + 1)
		if line.is_empty():
			continue
		var data: Variant = JSON.parse_string(line)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = data
		var kind := str(msg.get("type", ""))
		if kind == "frame" or kind == "hello" or kind == "preview":
			frame.emit(msg)
