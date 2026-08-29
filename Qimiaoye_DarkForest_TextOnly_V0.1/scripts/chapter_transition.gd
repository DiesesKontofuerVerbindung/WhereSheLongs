extends CanvasLayer
class_name ChapterTransition

const NODE_NAME := "ChapterTransition"
const LOADING_TEXT := "Where She Longs"
const FADE_TO_BLACK_SECONDS := 0.72
const MINIMUM_BLACK_SECONDS := 0.85
const FADE_FROM_BLACK_SECONDS := 0.55

var _ui_root: Control
var _blocker: ColorRect
var _loading_label: Label
var _running := false
var _phase := 0.0


static func begin(tree: SceneTree, target_scene_path: String) -> void:
	if tree == null or tree.root == null or target_scene_path.is_empty():
		push_error("章节转场参数无效：%s" % target_scene_path)
		return
	if tree.root.get_node_or_null(NODE_NAME) != null:
		return
	var transition := ChapterTransition.new()
	transition.name = NODE_NAME
	tree.root.add_child(transition)
	transition.call_deferred("_run_transition", target_scene_path)


func _ready() -> void:
	layer = 512
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	set_process(true)
	set_process_input(true)


func _build_ui() -> void:
	_ui_root = Control.new()
	_ui_root.name = "TransitionUI"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

	_blocker = ColorRect.new()
	_blocker.name = "BlackFade"
	_blocker.color = Color.BLACK
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.modulate.a = 0.0
	_ui_root.add_child(_blocker)

	_loading_label = Label.new()
	_loading_label.name = "LoadingTitle"
	_loading_label.text = LOADING_TEXT
	_loading_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_loading_label.offset_left = -420.0
	_loading_label.offset_top = -104.0
	_loading_label.offset_right = -48.0
	_loading_label.offset_bottom = -38.0
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_loading_label.add_theme_font_size_override("font_size", 34)
	_loading_label.add_theme_color_override("font_color", Color(0.91, 0.92, 0.94, 1.0))
	_loading_label.add_theme_constant_override("outline_size", 6)
	_loading_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Times New Roman", "Georgia"])
	title_font.allow_system_fallback = true
	_loading_label.add_theme_font_override("font", title_font)
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_label.modulate.a = 0.0
	_loading_label.z_index = 1
	_ui_root.add_child(_loading_label)


func _process(delta: float) -> void:
	if not _running or _loading_label == null:
		return
	_phase += delta
	_loading_label.self_modulate.a = 0.84 + sin(_phase * 2.1) * 0.12


func _input(_event: InputEvent) -> void:
	if _running:
		get_viewport().set_input_as_handled()


func _run_transition(target_scene_path: String) -> void:
	_running = true
	var request_error := ResourceLoader.load_threaded_request(target_scene_path, "PackedScene")
	var request_started := request_error == OK
	var fade_to_black := create_tween()
	fade_to_black.set_parallel(true)
	fade_to_black.set_trans(Tween.TRANS_SINE)
	fade_to_black.set_ease(Tween.EASE_IN_OUT)
	fade_to_black.tween_property(_blocker, "modulate:a", 1.0, FADE_TO_BLACK_SECONDS)
	fade_to_black.tween_property(_loading_label, "modulate:a", 1.0, FADE_TO_BLACK_SECONDS * 0.72).set_delay(FADE_TO_BLACK_SECONDS * 0.28)
	await fade_to_black.finished

	var black_started_msec := Time.get_ticks_msec()
	var packed_scene: PackedScene = null
	if request_started:
		var load_status := ResourceLoader.load_threaded_get_status(target_scene_path)
		while load_status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			load_status = ResourceLoader.load_threaded_get_status(target_scene_path)
		if load_status == ResourceLoader.THREAD_LOAD_LOADED:
			packed_scene = ResourceLoader.load_threaded_get(target_scene_path) as PackedScene
	else:
		packed_scene = load(target_scene_path) as PackedScene

	var minimum_msec := int(MINIMUM_BLACK_SECONDS * 1000.0)
	while Time.get_ticks_msec() - black_started_msec < minimum_msec:
		await get_tree().process_frame

	if packed_scene == null:
		await _recover_from_failure("章节场景加载失败：%s（error=%d）" % [target_scene_path, request_error])
		return
	var change_error := get_tree().change_scene_to_packed(packed_scene)
	if change_error != OK:
		await _recover_from_failure("章节场景切换失败：%s（error=%d）" % [target_scene_path, change_error])
		return
	await get_tree().process_frame
	await get_tree().process_frame

	var fade_from_black := create_tween()
	fade_from_black.set_parallel(true)
	fade_from_black.set_trans(Tween.TRANS_SINE)
	fade_from_black.set_ease(Tween.EASE_IN_OUT)
	fade_from_black.tween_property(_blocker, "modulate:a", 0.0, FADE_FROM_BLACK_SECONDS)
	fade_from_black.tween_property(_loading_label, "modulate:a", 0.0, FADE_FROM_BLACK_SECONDS * 0.65)
	await fade_from_black.finished
	_running = false
	queue_free()


func _recover_from_failure(issue: String) -> void:
	push_error(issue)
	var recovery := create_tween()
	recovery.set_parallel(true)
	recovery.tween_property(_blocker, "modulate:a", 0.0, 0.35)
	recovery.tween_property(_loading_label, "modulate:a", 0.0, 0.25)
	await recovery.finished
	_running = false
	queue_free()


func verify_contract() -> bool:
	return (
		layer >= 500
		and _ui_root != null
		and _blocker != null
		and _blocker.color == Color.BLACK
		and _blocker.mouse_filter == Control.MOUSE_FILTER_STOP
		and _loading_label != null
		and _loading_label.text == LOADING_TEXT
		and is_equal_approx(_loading_label.anchor_left, 1.0)
		and is_equal_approx(_loading_label.anchor_top, 1.0)
		and _loading_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT
	)
