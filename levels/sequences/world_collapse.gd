extends Control

## 奇妙夜·世界坍缩：图A + 文案 → 循环视频 → 解锁眨眼 → 切图B
## 摄像头仅后台检测眼睛，无预览画面。

signal finished(result)

const IMAGE_A := "res://assets/cg/world_collapse/grasp_a.jpg"
const IMAGE_B := "res://assets/cg/world_collapse/grasp_b.jpg"
const VIDEO_PATH := "res://assets/cg/world_collapse/collapse_loop.ogv"
const LINE_COLLAPSE := "世界即将坍缩"
const LINE_DONT_BLINK := "请不要眨眼"
const TYPE_CPS := 22.0
const TEXT_HOLD_SEC := 1.4
const SHAKE_AMOUNT := 3.5
const SHAKE_SPEED := 14.0
const FLASH_COUNT := 3
const FLASH_INTERVAL := 0.12


class LocalBlinkTransition extends SceneTransitionHandler:
	signal local_switched(scene_id: String)

	func switch_to(scene_id: String) -> void:
		transition_started.emit(scene_id)
		local_switched.emit(scene_id)
		transition_finished.emit(scene_id)


var _bg: ColorRect
var _image: TextureRect
var _video: VideoStreamPlayer
var _type_label: Label
var _transition: LocalBlinkTransition
var _blink: Node
var _phase: String = "boot"
var _done: bool = false
var _shake_active: bool = false
var _shake_time: float = 0.0


func setup(_scene_def: Dictionary) -> void:
	pass


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_blink = get_node_or_null("/root/BlinkSystem")
	_start_camera()
	call_deferred("_run_sequence")


func _start_camera() -> void:
	if _blink == null:
		push_error("BlinkSystem autoload missing")
		return
	if _blink.get("config") != null:
		_blink.config.debug_mode = true
	if _blink.has_method("ensure_started"):
		_blink.ensure_started()


func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color(0.02, 0.05, 0.12, 1.0)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_image = TextureRect.new()
	_image.set_anchors_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)

	_video = VideoStreamPlayer.new()
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.visible = false
	add_child(_video)

	_type_label = Label.new()
	_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_type_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_type_label.add_theme_font_size_override("font_size", 36)
	_type_label.add_theme_color_override("font_color", Color(0.95, 0.96, 1.0, 1.0))
	_type_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_type_label.add_theme_constant_override("outline_size", 8)
	_type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_type_label.z_index = 2
	_type_label.text = ""
	_type_label.visible = false
	add_child(_type_label)


func _process(delta: float) -> void:
	if not _shake_active or _type_label == null or not _type_label.visible:
		return
	_shake_time += delta
	var ox := sin(_shake_time * SHAKE_SPEED) * SHAKE_AMOUNT + randf_range(-1.4, 1.4)
	var oy := cos(_shake_time * (SHAKE_SPEED * 1.15)) * SHAKE_AMOUNT + randf_range(-1.4, 1.4)
	_type_label.position = Vector2(ox, oy)


func _set_shake(active: bool) -> void:
	_shake_active = active
	_shake_time = 0.0
	if _type_label:
		_type_label.position = Vector2.ZERO


func _run_sequence() -> void:
	_phase = "image_a"
	_set_image(IMAGE_A)
	await get_tree().create_timer(0.35).timeout

	_phase = "typewriter"
	await _show_line_then_clear(LINE_COLLAPSE)
	await _show_line_then_clear(LINE_DONT_BLINK)

	_phase = "video"
	await _start_loop_video()
	_arm_blink()
	_phase = "await_blink"


func _set_image(path: String) -> void:
	if ResourceLoader.exists(path):
		_image.texture = load(path)
		_image.visible = true
	else:
		push_warning("Missing image: %s" % path)


func _show_line_then_clear(text: String) -> void:
	_set_shake(true)
	await _play_typewriter(text)
	await get_tree().create_timer(TEXT_HOLD_SEC).timeout
	await _flash_text()
	_set_shake(false)
	_type_label.visible = false
	_type_label.modulate = Color(1, 1, 1, 1)
	_type_label.text = ""


func _play_typewriter(text: String) -> void:
	_type_label.visible = true
	_type_label.modulate = Color(1, 1, 1, 1)
	_type_label.text = ""
	var delay := 1.0 / maxf(TYPE_CPS, 0.1)
	for i in text.length():
		_type_label.text = text.substr(0, i + 1)
		await get_tree().create_timer(delay).timeout


func _flash_text() -> void:
	for _i in FLASH_COUNT:
		_type_label.modulate = Color(1, 1, 1, 0.15)
		await get_tree().create_timer(FLASH_INTERVAL).timeout
		_type_label.modulate = Color(1, 1, 1, 1)
		await get_tree().create_timer(FLASH_INTERVAL).timeout


func _start_loop_video() -> void:
	if not ResourceLoader.exists(VIDEO_PATH):
		push_warning("Missing video: %s" % VIDEO_PATH)
		return
	var stream: VideoStream = load(VIDEO_PATH)
	_video.stream = stream
	_video.visible = true
	_video.modulate = Color(1, 1, 1, 0.92)
	_video.play()
	if not _video.finished.is_connected(_on_video_finished):
		_video.finished.connect(_on_video_finished)
	await get_tree().create_timer(0.2).timeout


func _on_video_finished() -> void:
	if _phase == "await_blink" or _phase == "video":
		_video.play()


func _arm_blink() -> void:
	if _blink == null:
		push_error("BlinkSystem autoload missing")
		return
	_blink.reset()
	_blink.enable()
	_blink.configure("world_collapse_a", "world_collapse_b")
	if _transition == null:
		_transition = LocalBlinkTransition.new()
		_blink.set_transition_handler(_transition)
		_transition.local_switched.connect(_on_blink_switch)
	_blink.ensure_started()
	_blink.unlock()


func _on_blink_switch(_scene_id: String) -> void:
	if _done:
		return
	_done = true
	_phase = "image_b"
	_type_label.visible = false
	if _blink and _blink.has_method("disable"):
		_blink.disable()
	if _video.is_playing():
		_video.stop()
	_video.visible = false
	_set_image(IMAGE_B)
	await get_tree().create_timer(1.2).timeout
	finished.emit({"result": "success"})


func _unhandled_input(event: InputEvent) -> void:
	if _phase != "await_blink" or _done:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_on_blink_switch("world_collapse_b")
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _blink and _blink.has_method("disable"):
		_blink.disable()
	if _video and _video.is_playing():
		_video.stop()
