extends Node

signal blink_detected
signal scene_switch_requested(main_scene: String, child_scene: String)

var config := BlinkConfiguration.new()
var _controller := BlinkController.new()
var _transition: GodotSceneTransition
var _detector: WebsocketBlinkDetector
var _debug: BlinkDebugUI
var _camera_connected: bool = false
var _face_detected: bool = false
var _left_eye: String = "unknown"
var _right_eye: String = "unknown"
var _last_note: String = ""
var _hub_connected: bool = false


func _ready() -> void:
	_transition = GodotSceneTransition.new()
	add_child(_transition)
	_detector = WebsocketBlinkDetector.new()
	add_child(_detector)
	_detector.blink.connect(_on_detector_blink)
	_detector.frame.connect(_on_detector_frame)
	_detector.connection_changed.connect(_on_hub_connection)
	_debug = BlinkDebugUI.new()
	add_child(_debug)
	_detector.start(config.detector_ws_url)
	_controller.state_changed.connect(func(_s): _refresh_debug())
	_controller.blink_ignored.connect(_on_ignored)
	_controller.consumed.connect(_on_consumed)
	_refresh_debug()


func _unhandled_input(event: InputEvent) -> void:
	if not config.allow_debug_key_blink:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		_on_detector_blink({})


func configure(main_scene: String, child_scene: String) -> void:
	_controller.configure(main_scene, child_scene)
	_refresh_debug()


func unlock() -> bool:
	var ok := _controller.unlock()
	if ok:
		_last_note = "Blink System: UNLOCKED"
	_refresh_debug()
	return ok


func is_unlocked() -> bool:
	return _controller.is_unlocked()


func is_consumed() -> bool:
	return _controller.is_consumed()


func get_blink_count() -> int:
	return _controller.get_blink_count()


func reset() -> void:
	_controller.reset()
	_last_note = ""
	_refresh_debug()


func disable() -> void:
	_controller.disable()
	_refresh_debug()


func enable() -> void:
	_controller.enable()
	_refresh_debug()


func set_transition_handler(handler: SceneTransitionHandler) -> void:
	if _transition:
		_transition.queue_free()
	_transition = handler
	add_child(_transition)


func _on_detector_blink(_payload: Dictionary = {}) -> void:
	blink_detected.emit()
	_controller.handle_blink()


func _on_consumed(main_scene: String, child_scene: String) -> void:
	_last_note = "Blink Detected!\nTransition:\n%s\n    ↓\n%s\nBlink System: CONSUMED" % [main_scene, child_scene]
	_refresh_debug()
	scene_switch_requested.emit(main_scene, child_scene)
	if _transition is GodotSceneTransition:
		(_transition as GodotSceneTransition).play(child_scene, config)
		if not (_transition as GodotSceneTransition).transition_finished.is_connected(_on_transition_finished):
			(_transition as GodotSceneTransition).transition_finished.connect(_on_transition_finished)
	else:
		_transition.switch_to(child_scene)


func _on_transition_finished(_scene_id: String) -> void:
	_last_note = "Blink System: TRIGGERED"
	_refresh_debug()


func _on_ignored(reason: String) -> void:
	if reason == "already_consumed":
		_last_note = "Blink Ignored:\nSystem already consumed."
	elif reason == "locked":
		_last_note = "Blink Ignored:\nSystem still LOCKED."
	else:
		_last_note = "Blink Ignored:\n%s" % reason
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
	_refresh_debug()


func _refresh_debug() -> void:
	if _debug == null:
		return
	_debug.visible = config.debug_mode
	var cam := "CONNECTED" if _camera_connected else "DISCONNECTED"
	if not _hub_connected:
		cam = "DISCONNECTED (open detector page)"
	_debug.set_text(
		"Camera: %s\nFace Detected: %s\nLeft Eye: %s\nRight Eye: %s\nBlink System: %s\nBlink Count: %d\n%s"
		% [
			cam,
			"YES" if _face_detected else "NO",
			_left_eye.to_upper(),
			_right_eye.to_upper(),
			_controller.state_name(),
			_controller.get_blink_count(),
			_last_note,
		]
	)
