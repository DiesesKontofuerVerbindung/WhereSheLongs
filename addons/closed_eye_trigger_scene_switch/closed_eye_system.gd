extends Node

signal closed_hold_detected
signal scene_switch_requested(main_scene: String, child_scene: String)

const ClosedEyeConfigurationScript := preload("res://addons/closed_eye_trigger_scene_switch/core/closed_eye_config.gd")
const ClosedEyeControllerScript := preload("res://addons/closed_eye_trigger_scene_switch/core/closed_eye_controller.gd")
const ClosedEyeGodotTransitionScript := preload("res://addons/closed_eye_trigger_scene_switch/transition/closed_eye_godot_transition.gd")
const NativeClosedEyeCameraScript := preload("res://addons/closed_eye_trigger_scene_switch/detection/native_camera_client.gd")
const ClosedEyeDebugUIScript := preload("res://addons/closed_eye_trigger_scene_switch/ui/debug_ui.gd")

var config = ClosedEyeConfigurationScript.new()
var _controller = ClosedEyeControllerScript.new()
var _transition
var _detector
var _debug
var _camera_connected: bool = false
var _face_detected: bool = false
var _left_eye: String = "unknown"
var _right_eye: String = "unknown"
var _last_note: String = ""
var _hub_connected: bool = false
var _hold_seconds: float = 0.0
var _last_frame_at: float = -1000.0
var _fired_this_closure: bool = false


func _ready() -> void:
	_transition = ClosedEyeGodotTransitionScript.new()
	add_child(_transition)
	_detector = NativeClosedEyeCameraScript.new()
	add_child(_detector)
	_detector.frame.connect(_on_detector_frame)
	_detector.closed_hold.connect(_on_detector_closed_hold)
	_detector.connection_changed.connect(_on_hub_connection)
	_debug = ClosedEyeDebugUIScript.new()
	add_child(_debug)
	_detector.start()
	_controller.state_changed.connect(func(_s): _refresh_debug())
	_controller.hold_ignored.connect(_on_ignored)
	_controller.consumed.connect(_on_consumed)
	_refresh_debug()


func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var stale: bool = now - _last_frame_at > float(config.stale_seconds)
	var both_closed: bool = (
		_face_detected
		and not stale
		and _left_eye == "closed"
		and _right_eye == "closed"
	)
	if both_closed:
		_hold_seconds += delta
		if not _fired_this_closure and _hold_seconds >= config.hold_seconds:
			_fired_this_closure = true
			_fire_closed_hold()
	else:
		_hold_seconds = 0.0
		_fired_this_closure = false
	_refresh_debug()


func _unhandled_input(event: InputEvent) -> void:
	if not config.debug_mode or not config.allow_debug_key:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_hold_seconds = config.hold_seconds
		_fired_this_closure = true
		_fire_closed_hold()


func configure(main_scene: String, child_scene: String) -> void:
	_controller.configure(main_scene, child_scene)
	_refresh_debug()


func arm() -> bool:
	var ok: bool = _controller.arm()
	if ok:
		_last_note = "ClosedEye System: ARMED"
	_refresh_debug()
	return ok


func is_armed() -> bool:
	return _controller.is_armed()


func is_consumed() -> bool:
	return _controller.is_consumed()


func get_hold_count() -> int:
	return _controller.hold_count


func reset() -> void:
	_controller.reset()
	_hold_seconds = 0.0
	_fired_this_closure = false
	_last_note = ""
	_refresh_debug()


func disable() -> void:
	_controller.disable()
	_refresh_debug()


func enable() -> void:
	_controller.enable()
	_refresh_debug()


func set_transition_handler(handler: Node) -> void:
	if _transition:
		_transition.queue_free()
	_transition = handler
	add_child(_transition)


func _fire_closed_hold() -> void:
	if not _controller.is_armed():
		return
	closed_hold_detected.emit()
	_controller.handle_closed_hold()


func _on_detector_closed_hold(_payload: Dictionary = {}) -> void:
	_fired_this_closure = true
	_fire_closed_hold()


func _on_consumed(main_scene: String, child_scene: String) -> void:
	_last_note = "Eyes Closed %.1fs!\nTransition:\n%s\n    ↓\n%s\nClosedEye System: CONSUMED" % [
		config.hold_seconds, main_scene, child_scene
	]
	_refresh_debug()
	scene_switch_requested.emit(main_scene, child_scene)
	if _transition.has_method("play"):
		_transition.play(child_scene, config)
		if not _transition.transition_finished.is_connected(_on_transition_finished):
			_transition.transition_finished.connect(_on_transition_finished)
	else:
		_transition.switch_to(child_scene)


func _on_transition_finished(_scene_id: String) -> void:
	_last_note = "ClosedEye System: TRIGGERED"
	_refresh_debug()


func _on_ignored(reason: String) -> void:
	if reason == "already_consumed":
		_last_note = "Closed hold ignored:\nSystem already consumed."
	elif reason == "idle":
		_last_note = "Closed hold ignored:\nSystem still IDLE (not configured)."
	else:
		_last_note = "Closed hold ignored:\n%s" % reason
	_refresh_debug()


func _on_hub_connection(connected: bool) -> void:
	_hub_connected = connected
	_refresh_debug()


func _on_detector_frame(payload: Dictionary) -> void:
	var frame: Dictionary = payload
	if payload.get("type", "") == "hello" and payload.has("lastFrame"):
		frame = payload["lastFrame"]
	_camera_connected = bool(frame.get("cameraConnected", false))
	_face_detected = bool(frame.get("faceDetected", false))
	_left_eye = str(frame.get("leftEye", "unknown"))
	_right_eye = str(frame.get("rightEye", "unknown"))
	_last_frame_at = Time.get_ticks_msec() / 1000.0
	if _debug:
		_debug.set_jpeg_preview(str(frame.get("jpeg", "")))
	_refresh_debug()


func _refresh_debug() -> void:
	if _debug == null:
		return
	_debug.visible = config.debug_mode
	var cam := "CONNECTED" if _camera_connected else "STARTING"
	if not _hub_connected and not _camera_connected:
		cam = "STARTING"
	_debug.set_text(
		"ClosedEye Camera: %s\nFace Detected: %s\nLeft Eye: %s\nRight Eye: %s\nClosed Hold: %.2f / %.2f s\nClosedEye System: %s\n%s"
		% [
			cam,
			"YES" if _face_detected else "NO",
			_left_eye.to_upper(),
			_right_eye.to_upper(),
			_hold_seconds,
			config.hold_seconds,
			_controller.state_name(),
			_last_note,
		]
	)
