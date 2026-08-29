class_name FanCameraBridge
extends Node

signal physics_frame_received(frame)
signal status_changed(state, detail)

const BRIDGE_PORT := 25683
const COMMAND_PORT := 25684
const BRIDGE_SCRIPT_PATH := "res://levels/minigames/fan_camera_bridge.py"
const MODEL_PATH := "res://levels/minigames/hand_landmarker.task"
const RUNTIME_CONFIG_PATH := "res://levels/minigames/fan_runtime/config.py"
const RUNTIME_BUNDLE_ROOT := "user://prototype2_fan_b198616"
const RUNTIME_RESOURCE_PREFIX := "res://levels/minigames/"
const RUNTIME_RESOURCE_PATHS := [
	BRIDGE_SCRIPT_PATH,
	MODEL_PATH,
	RUNTIME_CONFIG_PATH,
	"res://levels/minigames/fan_runtime/environment_recorder.py",
	"res://levels/minigames/fan_runtime/fan_detector.py",
	"res://levels/minigames/fan_runtime/fan_state.py",
	"res://levels/minigames/fan_runtime/hand_tracker.py",
	"res://levels/minigames/fan_runtime/interference_field.py",
	"res://levels/minigames/fan_runtime/one_euro_filter.py",
	"res://levels/minigames/fan_runtime/palm_signal_processor.py",
	"res://levels/minigames/fan_runtime/test_logger.py",
]
const ENTITY_COUNT := 72

## 玩法3 用满 72 个实体；主观内心那一幕只有六件物件，起桥前改这个值即可。
var entity_count := ENTITY_COUNT
var _udp := PacketPeerUDP.new()
var _command_udp := PacketPeerUDP.new()
var _bridge_pid := -1
var _started := false


func start_bridge() -> void:
	if _started:
		return
	_started = true
	if DisplayServer.get_name() == "headless":
		status_changed.emit("headless", "headless verification")
		return
	var runtime_paths := _materialize_runtime_bundle()
	if runtime_paths.is_empty():
		status_changed.emit("error", "Prototype_2_Fan 运行时不完整")
		return
	var bind_error := _udp.bind(BRIDGE_PORT, "127.0.0.1")
	if bind_error != OK:
		status_changed.emit("error", "摄像头通信端口被占用")
		return
	status_changed.emit("starting", "正在启动手部识别")
	var arguments := PackedStringArray([
		str(runtime_paths.get("bridge", "")),
		"--model",
		str(runtime_paths.get("model", "")),
		"--port",
		str(BRIDGE_PORT),
		"--command-port",
		str(COMMAND_PORT),
		"--entities",
		str(entity_count),
	])
	for python_path in _python_candidates():
		_bridge_pid = OS.create_process(python_path, arguments, false)
		if _bridge_pid > 0:
			return
	status_changed.emit("error", "找不到带 MediaPipe 的 Python 环境")


func prepare_runtime_bundle_for_verification() -> Dictionary:
	return _materialize_runtime_bundle()


func _materialize_runtime_bundle() -> Dictionary:
	var runtime_dir := RUNTIME_BUNDLE_ROOT.path_join("fan_runtime")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(runtime_dir))
	if mkdir_error != OK:
		return {}
	for source_path in RUNTIME_RESOURCE_PATHS:
		if not FileAccess.file_exists(source_path):
			return {}
		var relative_path := str(source_path).trim_prefix(RUNTIME_RESOURCE_PREFIX)
		var output_path := RUNTIME_BUNDLE_ROOT.path_join(relative_path)
		var output := FileAccess.open(output_path, FileAccess.WRITE)
		if output == null:
			return {}
		output.store_buffer(FileAccess.get_file_as_bytes(source_path))
		output.close()
	return {
		"bridge": ProjectSettings.globalize_path(RUNTIME_BUNDLE_ROOT.path_join("fan_camera_bridge.py")),
		"model": ProjectSettings.globalize_path(RUNTIME_BUNDLE_ROOT.path_join("hand_landmarker.task")),
		"config": ProjectSettings.globalize_path(RUNTIME_BUNDLE_ROOT.path_join("fan_runtime/config.py")),
		"file_count": RUNTIME_RESOURCE_PATHS.size(),
	}


func request_reset() -> bool:
	if _bridge_pid <= 0 or not OS.is_process_running(_bridge_pid):
		return false
	var connect_error := _command_udp.connect_to_host("127.0.0.1", COMMAND_PORT)
	if connect_error != OK:
		return false
	var command := JSON.stringify({"command": "reset"}).to_utf8_buffer()
	return _command_udp.put_packet(command) == OK


func _process(_delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var packet_text := _udp.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(packet_text)
		if not parsed is Dictionary:
			continue
		var packet: Dictionary = parsed
		match str(packet.get("event", "")):
			"bridge_status":
				status_changed.emit(str(packet.get("state", "error")), str(packet.get("detail", "")))
			"prototype2_physics_frame":
				physics_frame_received.emit(packet)


func stop_bridge() -> void:
	_udp.close()
	_command_udp.close()
	if _bridge_pid > 0 and OS.is_process_running(_bridge_pid):
		OS.kill(_bridge_pid)
	_bridge_pid = -1


func _exit_tree() -> void:
	stop_bridge()


func _python_candidates() -> PackedStringArray:
	var candidates := PackedStringArray()
	var configured := OS.get_environment("QIMIAOYE_FAN_PYTHON")
	if not configured.is_empty():
		candidates.append(configured)
	var conda_prefix := OS.get_environment("CONDA_PREFIX")
	if not conda_prefix.is_empty():
		candidates.append(conda_prefix.path_join("python.exe"))
	var user_profile := OS.get_environment("USERPROFILE")
	if not user_profile.is_empty():
		candidates.append(user_profile.path_join("anaconda3/python.exe"))
		candidates.append(user_profile.path_join("miniconda3/python.exe"))
	for executable_name in ["python3", "python"]:
		candidates.append(executable_name)
	return candidates
