extends Control

## 奇妙夜章节外壳。
##
## 事件循环与森林正片完全独立，只复用旁白、对白和 F4 回溯 UI。全屏画面在
## 正式 CG 到位前统一使用黑底白字资源槽；镜头效果只作用于该 placeholder。

const NarrationUIScript := preload("res://scripts/narration_ui.gd")
const DialogueUIScript := preload("res://scripts/dialogue_ui.gd")
const MysticNightDataScript := preload("res://scripts/mystic_night_data.gd")
const WeddingDataScript := preload("res://scripts/wedding_data.gd")
const StoryDataScript := preload("res://scripts/story_data.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")

const FOREST_MAIN_SCENE := "res://main.tscn"
const WEDDING_PROLOGUE_SCENE := "res://scenes/wedding/wedding_prologue.tscn"
const MYSTIC_NIGHT_SCENE := "res://scenes/mystic_night/mystic_night.tscn"
const DEV_JUMP_CHAPTER_ID := "mystic_night"
const FONT_PRIMARY_NAME := "Times New Roman"

const COLOR_BG := Color(0.0, 0.0, 0.0, 1.0)
const COLOR_TEXT := Color(0.96, 0.97, 1.0, 1.0)
const COLOR_MUTED := Color(0.62, 0.66, 0.74, 1.0)

const CG_NAMES := [
	"奇妙夜场景1",
	"奇妙夜场景2",
	"奇妙夜拉手图",
	"奇妙夜鸟图",
	"奇妙夜星星图",
	"奇妙夜送花图",
	"奇妙夜森林轮廓图",
	"奇妙夜女孩身影图",
	"黑屏",
]
const CAMERA_SHOT_IDS := [
	"shot_01_wake",
	"shot_02_turn",
	"shot_03_landing_pulse",
	"shot_04_reveal",
	"shot_05_run",
	"shot_06_forest_push",
	"shot_07_still",
	"shot_08_last_look",
]

signal prologue_finished

var _events: Array[Dictionary] = []
var _event_index := 0
var _current_scene := ""
var _current_cg := ""
var _current_source := 0
var _verify_mode := false
var _endpoint_reached := false
var _visited_sources: Dictionary = {}
var _visited_cgs: PackedStringArray = []
var _visited_camera_shots: PackedStringArray = []
var _interactions_done: Dictionary = {}
var _failures: PackedStringArray = []

var _pending_dev_jump: Dictionary = {}
var _dev_jump_active := false
var _dev_jump_requested_source := 0
var _dev_jump_actual_source := 0
var _dev_jump_overlay

var _primary_font: SystemFont
var _cjk_fallback_font: SystemFont
var _root_bg: ColorRect
var _cg_root: Control
var _cg_backdrop: ColorRect
var _cg_label: Label
var _back_buffer: BackBufferCopy
var _screen_fx: ColorRect
var _screen_fx_material: ShaderMaterial
var _radial_fx: ColorRect
var _radial_material: ShaderMaterial
var _vignette_fx: ColorRect
var _vignette_material: ShaderMaterial
var _dark_cover: ColorRect
var _advance_hint: Label
var _interaction_panel: PanelContainer
var _interaction_button: Button
var _narration_ui
var _dialogue_ui

var _pending_interaction := ""
var _active_line_channel := ""
var _pending_cg_turn := false
var _pending_final_turn := false
var _active_camera_tween: Tween
var _forest_push_tween: Tween


func _ready() -> void:
	name = "MysticNight"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending_dev_jump = DevJumpPanelScript.take_pending_jump(get_tree().root, DEV_JUMP_CHAPTER_ID)
	_verify_mode = "--verify" in OS.get_cmdline_user_args() or "--verify" in OS.get_cmdline_args()
	_configure_typography()
	_build_ui()
	_events = MysticNightDataScript.build_events()
	_setup_dev_jump_chapters()
	_apply_pending_dev_jump()
	call_deferred("_run_events")


func _configure_typography() -> void:
	_cjk_fallback_font = SystemFont.new()
	_cjk_fallback_font.font_names = PackedStringArray(["SimSun", "NSimSun", "宋体", "新宋体"])
	_cjk_fallback_font.allow_system_fallback = false

	_primary_font = SystemFont.new()
	_primary_font.font_names = PackedStringArray([FONT_PRIMARY_NAME])
	_primary_font.allow_system_fallback = false
	var fallback_chain: Array[Font] = [_cjk_fallback_font]
	_primary_font.fallbacks = fallback_chain

	var app_theme := Theme.new()
	app_theme.default_font = _primary_font
	app_theme.default_font_size = 18
	theme = app_theme


func _build_ui() -> void:
	_root_bg = ColorRect.new()
	_root_bg.name = "MysticNightBackdrop"
	_root_bg.color = COLOR_BG
	_root_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_bg)

	_cg_root = Control.new()
	_cg_root.name = "MysticNightCgPlaceholder"
	_cg_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cg_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cg_root.resized.connect(_update_cg_pivot)
	add_child(_cg_root)

	_cg_backdrop = ColorRect.new()
	_cg_backdrop.color = COLOR_BG
	_cg_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cg_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cg_root.add_child(_cg_backdrop)

	_cg_label = Label.new()
	_cg_label.name = "MysticNightCgName"
	_cg_label.set_anchors_preset(Control.PRESET_CENTER)
	_cg_label.offset_left = -440
	_cg_label.offset_right = 440
	_cg_label.offset_top = -48
	_cg_label.offset_bottom = 48
	_cg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cg_label.add_theme_font_size_override("font_size", 32)
	_cg_label.add_theme_color_override("font_color", COLOR_TEXT)
	_cg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cg_root.add_child(_cg_label)

	_back_buffer = BackBufferCopy.new()
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_back_buffer)

	_screen_fx_material = ShaderMaterial.new()
	var screen_shader := Shader.new()
	screen_shader.code = """
shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform float motion_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 motion_direction = vec2(1.0, 0.0);
void fragment() {
	vec2 offset = motion_direction * motion_amount * 0.012;
	vec4 center = textureLod(screen_texture, SCREEN_UV, blur_amount * 4.0);
	vec4 trail_a = textureLod(screen_texture, SCREEN_UV - offset, blur_amount * 3.0);
	vec4 trail_b = textureLod(screen_texture, SCREEN_UV - offset * 2.0, blur_amount * 2.0);
	COLOR = mix(center, (center * 0.58 + trail_a * 0.27 + trail_b * 0.15), motion_amount);
}
"""
	_screen_fx_material.shader = screen_shader
	_screen_fx = ColorRect.new()
	_screen_fx.name = "CgScreenEffect"
	_screen_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_fx.material = _screen_fx_material
	_screen_fx.visible = false
	add_child(_screen_fx)

	_radial_material = ShaderMaterial.new()
	var radial_shader := Shader.new()
	radial_shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.58, 0.62);
void fragment() {
	float glow = 1.0 - smoothstep(0.0, 0.46, distance(UV, center));
	COLOR = vec4(vec3(1.0, 0.94, 0.72), glow * strength * 0.42);
}
"""
	_radial_material.shader = radial_shader
	_radial_fx = ColorRect.new()
	_radial_fx.name = "LandingRadialLight"
	_radial_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_radial_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radial_fx.material = _radial_material
	add_child(_radial_fx)

	_vignette_material = ShaderMaterial.new()
	var vignette_shader := Shader.new()
	vignette_shader.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.0, 0.74);
	float edge = smoothstep(0.30, 0.63, length(centered));
	COLOR = vec4(0.0, 0.0, 0.0, edge * strength * 0.78);
}
"""
	_vignette_material.shader = vignette_shader
	_vignette_fx = ColorRect.new()
	_vignette_fx.name = "CgVignette"
	_vignette_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_fx.material = _vignette_material
	add_child(_vignette_fx)

	_dark_cover = ColorRect.new()
	_dark_cover.name = "TurnIntoDarkness"
	_dark_cover.color = COLOR_BG
	_dark_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dark_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dark_cover.modulate.a = 0.0
	add_child(_dark_cover)

	_narration_ui = NarrationUIScript.new()
	_narration_ui.name = "NARRATION_UI"
	_narration_ui.anchor_left = 0.16
	_narration_ui.anchor_top = 0.02
	_narration_ui.anchor_right = 0.84
	_narration_ui.anchor_bottom = 0.20
	add_child(_narration_ui)

	_dialogue_ui = DialogueUIScript.new()
	_dialogue_ui.name = "DIALOGUE_UI"
	add_child(_dialogue_ui)

	_interaction_panel = PanelContainer.new()
	_interaction_panel.name = "MysticNightInteraction"
	_interaction_panel.set_anchors_preset(Control.PRESET_CENTER)
	_interaction_panel.offset_left = -150
	_interaction_panel.offset_right = 150
	_interaction_panel.offset_top = 120
	_interaction_panel.offset_bottom = 172
	_interaction_panel.visible = false
	add_child(_interaction_panel)

	_interaction_button = Button.new()
	_interaction_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_interaction_button.pressed.connect(_on_interaction_pressed)
	_interaction_panel.add_child(_interaction_button)

	_advance_hint = Label.new()
	_advance_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_advance_hint.offset_left = 16
	_advance_hint.offset_top = 12
	_advance_hint.offset_right = 320
	_advance_hint.offset_bottom = 40
	_advance_hint.add_theme_font_size_override("font_size", 13)
	_advance_hint.add_theme_color_override("font_color", COLOR_MUTED)
	_advance_hint.text = "按 Enter / Space 继续"
	_advance_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advance_hint.visible = false
	add_child(_advance_hint)

	_dev_jump_overlay = DevJumpPanelScript.new()
	add_child(_dev_jump_overlay)
	_dev_jump_overlay.jump_requested.connect(_on_dev_jump_requested)
	call_deferred("_update_cg_pivot")


func _update_cg_pivot() -> void:
	if _cg_root != null:
		_cg_root.pivot_offset = _cg_root.size * 0.5


func _setup_dev_jump_chapters() -> void:
	if _dev_jump_overlay == null:
		return
	var chapters: Array[Dictionary] = [
		{
			"id": "wedding",
			"title": "婚礼前夜回溯",
			"scene": WEDDING_PROLOGUE_SCENE,
			"events": WeddingDataScript.build_events(),
			"hint": "婚礼前段的 DOCX 行。选这一页会切到婚礼场景并从该行开始。",
		},
		{
			"id": DEV_JUMP_CHAPTER_ID,
			"title": "奇妙夜回溯",
			"scene": MYSTIC_NIGHT_SCENE,
			"events": _events,
			"hint": "奇妙夜的 DOCX 行。若该行没有事件，将从下一条有事件的行开始。",
		},
		{
			"id": "forest",
			"title": "森林回溯",
			"scene": FOREST_MAIN_SCENE,
			"events": StoryDataScript.get_events(),
			"hint": "森林正片的 DOCX 行。选这一页会切到森林场景并从该行开始。",
		},
	]
	_dev_jump_overlay.setup(chapters, DEV_JUMP_CHAPTER_ID)
	_dev_jump_overlay.refresh_preview(_current_source)


func _toggle_dev_jump_panel() -> void:
	if _dev_jump_overlay == null:
		return
	if _dev_jump_overlay.is_open():
		_dev_jump_overlay.close_panel()
	else:
		_dev_jump_overlay.open_panel(_current_source)


func _on_dev_jump_requested(payload: Dictionary) -> void:
	if bool(payload.get("same_chapter", true)):
		call_deferred("_reload_for_dev_jump")
		return
	call_deferred("_change_scene_for_dev_jump", str(payload.get("scene", "")))


func _reload_for_dev_jump() -> void:
	var reload_error := get_tree().reload_current_scene()
	if reload_error == OK:
		return
	get_tree().root.remove_meta(DevJumpPanelScript.META_KEY)
	_dev_jump_overlay.report_jump_failure("场景重载失败，错误码：%d" % reload_error)


func _change_scene_for_dev_jump(scene_path: String) -> void:
	var change_error := get_tree().change_scene_to_file(scene_path)
	if change_error == OK:
		return
	get_tree().root.remove_meta(DevJumpPanelScript.META_KEY)
	_dev_jump_overlay.report_jump_failure("切换到 %s 失败，错误码：%d" % [scene_path, change_error])


func _apply_pending_dev_jump() -> void:
	if _pending_dev_jump.is_empty():
		return
	var requested_source := int(_pending_dev_jump.get("requested_source", 0))
	var resolved := DevJumpPanelScript.resolve_source_line(_events, requested_source)
	if resolved.is_empty():
		_failures.append("奇妙夜开发跳转目标无效：DOCX 第 %d 行" % requested_source)
		return
	var target_index := int(resolved.get("index", -1))
	if target_index < 0 or target_index >= _events.size():
		_failures.append("奇妙夜开发跳转事件索引越界：%d" % target_index)
		return
	_dev_jump_active = true
	_dev_jump_requested_source = requested_source
	_dev_jump_actual_source = int(resolved.get("source", 0))
	_event_index = target_index
	_restore_dev_jump_context(target_index)


func _restore_dev_jump_context(target_index: int) -> void:
	var scene_name := ""
	var cg_name := ""
	for i in range(clampi(target_index, 0, _events.size())):
		var event: Dictionary = _events[i]
		match str(event.get("type", "")):
			"scene":
				scene_name = str(event.get("name", scene_name))
			"cg":
				cg_name = str(event.get("name", cg_name))
	if not scene_name.is_empty():
		_current_scene = scene_name
	if not cg_name.is_empty():
		_set_cg_immediately(cg_name)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F4:
		_toggle_dev_jump_panel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and _dev_jump_overlay != null and _dev_jump_overlay.is_open():
		_dev_jump_overlay.close_panel()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _dev_jump_overlay != null and _dev_jump_overlay.is_open():
		return
	if _active_line_channel.is_empty():
		return
	if key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if _active_line_channel == "NARRATION":
			_narration_ui.request_advance()
		else:
			_dialogue_ui.request_advance()
		get_viewport().set_input_as_handled()


func _run_events() -> void:
	while _event_index < _events.size():
		var event := _events[_event_index]
		_event_index += 1
		await _run_event(event)
	if not _endpoint_reached:
		_failures.append("奇妙夜没有走到终点")
	prologue_finished.emit()
	if _verify_mode:
		_report_verification()
		return
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file(FOREST_MAIN_SCENE)


func _run_event(event: Dictionary) -> void:
	var source := int(event.get("source", 0))
	if source > 0:
		_visited_sources[source] = true
		_current_source = source
		if _dev_jump_overlay != null and _dev_jump_overlay.is_open():
			_dev_jump_overlay.refresh_preview(source)
	match str(event.get("type", "")):
		"scene":
			_current_scene = str(event.get("name", ""))
		"cg":
			await _set_cg(str(event.get("name", "")))
		"line":
			await _show_line(event)
		"camera":
			await _run_camera(event)
		"interaction":
			await _run_interaction(event)
		"endpoint":
			_endpoint_reached = true
			_cg_label.text = str(event.get("text", "请闭上眼睛"))
		_:
			_failures.append("未知事件类型：%s" % str(event.get("type", "")))


func _set_cg(cg_name: String) -> void:
	_visited_cgs.append(cg_name)
	if _verify_mode:
		_set_cg_immediately(cg_name)
		_pending_cg_turn = false
		_pending_final_turn = false
		return
	if _pending_final_turn and cg_name == "黑屏":
		await _turn_into_darkness()
		_set_cg_immediately(cg_name)
		_pending_final_turn = false
		return
	if _pending_cg_turn:
		await _turn_to_next_cg(cg_name)
		_pending_cg_turn = false
		return
	var fade_out := create_tween()
	fade_out.tween_property(_cg_root, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_out.finished
	_set_cg_immediately(cg_name)
	_cg_root.modulate.a = 0.0
	var fade_in := create_tween()
	fade_in.tween_property(_cg_root, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await fade_in.finished


func _set_cg_immediately(cg_name: String) -> void:
	_current_cg = cg_name
	_cg_label.text = "请闭上眼睛" if cg_name == "黑屏" else cg_name
	_cg_root.position = Vector2.ZERO
	_cg_root.scale = Vector2.ONE
	_cg_root.modulate = Color.WHITE
	_dark_cover.modulate.a = 0.0
	_set_screen_fx(0.0, 0.0)


func _turn_to_next_cg(cg_name: String) -> void:
	_set_screen_fx(0.03, 0.14, Vector2(1.0, 0.0))
	var turn_out := create_tween()
	turn_out.set_parallel(true)
	turn_out.tween_property(_cg_root, "position:x", -58.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	turn_out.tween_property(_cg_root, "modulate:a", 0.18, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await turn_out.finished
	_set_cg_immediately(cg_name)
	_cg_root.position.x = 58.0
	_cg_root.modulate.a = 0.18
	_set_screen_fx(0.02, 0.10, Vector2(1.0, 0.0))
	var turn_in := create_tween()
	turn_in.set_parallel(true)
	turn_in.tween_property(_cg_root, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	turn_in.tween_property(_cg_root, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	turn_in.tween_method(_set_motion_amount, 0.10, 0.0, 0.22)
	await turn_in.finished
	_set_screen_fx(0.0, 0.0)


func _turn_into_darkness() -> void:
	_stop_camera_motion()
	_set_screen_fx(0.02, 0.18, Vector2(1.0, 0.0))
	_dark_cover.modulate.a = 0.0
	var turn := create_tween()
	turn.set_parallel(true)
	turn.tween_property(_cg_root, "position:x", 92.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	turn.tween_property(_dark_cover, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	turn.tween_method(_set_motion_amount, 0.18, 0.0, 0.5)
	await turn.finished


func _show_line(event: Dictionary) -> void:
	if int(event.get("source", 0)) == 110:
		_stop_forest_push()
	var speaker := str(event.get("speaker", ""))
	var text := str(event.get("text", ""))
	if speaker == "旁白":
		_dialogue_ui.hide_dialogue()
		await _narration_ui.present(text, _verify_mode)
		if _verify_mode:
			return
		_active_line_channel = "NARRATION"
		_narration_ui.set_advance_waiting(true)
		_set_advance_hint(true)
		await _narration_ui.advance_requested
		_set_advance_hint(false)
		_narration_ui.set_advance_waiting(false)
	else:
		_narration_ui.begin_fade_for_dialogue(_verify_mode)
		await _dialogue_ui.present_line(speaker, text, _verify_mode)
		if _verify_mode:
			return
		_active_line_channel = "DIALOGUE"
		_dialogue_ui.set_advance_waiting(true)
		_set_advance_hint(true)
		await _dialogue_ui.advance_requested
		_set_advance_hint(false)
		_dialogue_ui.set_advance_waiting(false)
	_active_line_channel = ""


func _set_advance_hint(enabled: bool) -> void:
	if _advance_hint != null:
		_advance_hint.visible = enabled and not _verify_mode


func _run_camera(event: Dictionary) -> void:
	var shot_id := str(event.get("id", ""))
	_visited_camera_shots.append(shot_id)
	if _verify_mode:
		_pending_cg_turn = shot_id == "shot_02_turn"
		_pending_final_turn = shot_id == "shot_08_last_look"
		_reset_camera_immediately()
		return
	match shot_id:
		"shot_01_wake":
			await _shot_wake()
		"shot_02_turn":
			await _shot_turn_prepare()
		"shot_03_landing_pulse":
			await _shot_landing_pulse()
		"shot_04_reveal":
			await _shot_reveal()
		"shot_05_run":
			await _shot_run()
		"shot_06_forest_push":
			_shot_forest_push()
		"shot_07_still":
			await _shot_still()
		"shot_08_last_look":
			await _shot_last_look()
		_:
			_failures.append("未知重点镜头：%s" % shot_id)


func _shot_wake() -> void:
	_stop_camera_motion()
	_cg_root.position = Vector2(0.0, 24.0)
	_cg_root.modulate = Color(0.62, 0.62, 0.62, 1.0)
	_set_screen_fx(0.34, 0.0)
	_active_camera_tween = create_tween()
	_active_camera_tween.set_parallel(true)
	_active_camera_tween.tween_property(_cg_root, "position:y", 0.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_camera_tween.tween_property(_cg_root, "modulate", Color.WHITE, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_camera_tween.tween_method(_set_blur_amount, 0.34, 0.0, 1.0)
	await _active_camera_tween.finished
	_set_screen_fx(0.0, 0.0)


func _shot_turn_prepare() -> void:
	_stop_camera_motion()
	_set_screen_fx(0.02, 0.04, Vector2(1.0, 0.0))
	_active_camera_tween = create_tween()
	_active_camera_tween.tween_property(_cg_root, "position:x", 10.0, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _active_camera_tween.finished
	_pending_cg_turn = true


func _shot_landing_pulse() -> void:
	_radial_material.set_shader_parameter("strength", 0.0)
	_active_camera_tween = create_tween()
	_active_camera_tween.tween_method(_set_radial_strength, 0.0, 0.72, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_camera_tween.tween_method(_set_radial_strength, 0.72, 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _active_camera_tween.finished


func _shot_reveal() -> void:
	_stop_camera_motion()
	_cg_root.scale = Vector2(1.04, 1.04)
	_active_camera_tween = create_tween()
	_active_camera_tween.tween_property(_cg_root, "scale", Vector2.ONE, 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await _active_camera_tween.finished


func _shot_run() -> void:
	_stop_camera_motion()
	_set_screen_fx(0.018, 0.035, Vector2(1.0, 0.0))
	_set_vignette_strength(0.22)
	for step in range(8):
		var side := -1.0 if step % 2 == 0 else 1.0
		_active_camera_tween = create_tween()
		_active_camera_tween.tween_property(_cg_root, "position", Vector2(side * 2.5, side * 4.0), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await _active_camera_tween.finished
	_active_camera_tween = create_tween()
	_active_camera_tween.set_parallel(true)
	_active_camera_tween.tween_property(_cg_root, "position", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_camera_tween.tween_method(_set_motion_amount, 0.035, 0.0, 0.3)
	_active_camera_tween.tween_method(_set_vignette_strength, 0.22, 0.0, 0.3)
	await _active_camera_tween.finished
	_set_screen_fx(0.0, 0.0)


func _shot_forest_push() -> void:
	_stop_camera_motion()
	_set_vignette_strength(0.30)
	_cg_root.scale = Vector2.ONE
	_forest_push_tween = create_tween()
	_forest_push_tween.tween_property(_cg_root, "scale", Vector2(1.025, 1.025), 8.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _shot_still() -> void:
	_stop_camera_motion()
	_cg_root.position = Vector2.ZERO
	_cg_root.scale = Vector2.ONE
	_cg_root.modulate = Color(0.90, 0.90, 0.90, 1.0)
	_set_screen_fx(0.0, 0.0)
	await get_tree().create_timer(0.75).timeout
	_cg_root.modulate = Color.WHITE


func _shot_last_look() -> void:
	_stop_camera_motion()
	_cg_root.position = Vector2.ZERO
	_cg_root.scale = Vector2.ONE
	_set_vignette_strength(0.42)
	await get_tree().create_timer(1.35).timeout
	_pending_final_turn = true


func _stop_forest_push() -> void:
	if _forest_push_tween != null and _forest_push_tween.is_valid():
		_forest_push_tween.kill()
	_forest_push_tween = null
	_cg_root.scale = Vector2(1.025, 1.025)


func _stop_camera_motion() -> void:
	if _active_camera_tween != null and _active_camera_tween.is_valid():
		_active_camera_tween.kill()
	_active_camera_tween = null
	if _forest_push_tween != null and _forest_push_tween.is_valid():
		_forest_push_tween.kill()
	_forest_push_tween = null


func _reset_camera_immediately() -> void:
	_stop_camera_motion()
	_cg_root.position = Vector2.ZERO
	_cg_root.scale = Vector2.ONE
	_cg_root.modulate = Color.WHITE
	_dark_cover.modulate.a = 0.0
	_set_screen_fx(0.0, 0.0)
	_set_radial_strength(0.0)
	_set_vignette_strength(0.0)


func _set_screen_fx(blur_amount: float, motion_amount: float, direction := Vector2(1.0, 0.0)) -> void:
	_screen_fx_material.set_shader_parameter("blur_amount", blur_amount)
	_screen_fx_material.set_shader_parameter("motion_amount", motion_amount)
	_screen_fx_material.set_shader_parameter("motion_direction", direction)
	_screen_fx.visible = blur_amount > 0.0001 or motion_amount > 0.0001


func _set_blur_amount(value: float) -> void:
	_screen_fx_material.set_shader_parameter("blur_amount", value)
	_screen_fx.visible = value > 0.0001 or float(_screen_fx_material.get_shader_parameter("motion_amount")) > 0.0001


func _set_motion_amount(value: float) -> void:
	_screen_fx_material.set_shader_parameter("motion_amount", value)
	_screen_fx.visible = value > 0.0001 or float(_screen_fx_material.get_shader_parameter("blur_amount")) > 0.0001


func _set_radial_strength(value: float) -> void:
	_radial_material.set_shader_parameter("strength", value)


func _set_vignette_strength(value: float) -> void:
	_vignette_material.set_shader_parameter("strength", value)


func _run_interaction(event: Dictionary) -> void:
	var interaction_id := str(event.get("id", ""))
	_pending_interaction = interaction_id
	_interaction_button.text = str(event.get("prompt", "继续"))
	_interaction_panel.visible = true
	if _verify_mode:
		_on_interaction_pressed()
	else:
		while _pending_interaction == interaction_id:
			await get_tree().process_frame
	_interactions_done[interaction_id] = true


func _on_interaction_pressed() -> void:
	_pending_interaction = ""
	_interaction_panel.visible = false


func _report_verification() -> void:
	_validate_event_contract()
	if _narration_ui == null or _dialogue_ui == null:
		_failures.append("旁白或对白 UI 缺失")
	else:
		if _narration_ui.name != "NARRATION_UI" or _dialogue_ui.name != "DIALOGUE_UI":
			_failures.append("旁白与对白 UI 命名异常")
		if _narration_ui.get_layout_sample_count() != 55:
			_failures.append("旁白显示数量异常：%d" % _narration_ui.get_layout_sample_count())
		if _dialogue_ui.get_presented_line_count() != 36:
			_failures.append("人物对白显示数量异常：%d" % _dialogue_ui.get_presented_line_count())
	if _dev_jump_overlay == null or not _dev_jump_overlay.verify_contract():
		_failures.append("F4 回溯面板不完整（婚礼前夜 / 奇妙夜 / 森林三页缺失或行号范围为空）")
	elif _dev_jump_overlay.get_chapter_ids() != PackedStringArray(["wedding", DEV_JUMP_CHAPTER_ID, "forest"]):
		_failures.append("回溯面板章节页缺失或顺序异常：%s" % str(_dev_jump_overlay.get_chapter_ids()))
	elif _dev_jump_overlay.is_open():
		_failures.append("F4 回溯面板不应默认显示")
	if _visited_cgs != PackedStringArray(CG_NAMES):
		_failures.append("全屏 CG 资源槽顺序异常：%s" % str(_visited_cgs))
	if _visited_camera_shots != PackedStringArray(CAMERA_SHOT_IDS):
		_failures.append("重点镜头顺序异常：%s" % str(_visited_camera_shots))
	if not _interactions_done.has("follow_girl"):
		_failures.append("“跟上去”交互没有完成")
	if _current_cg != "黑屏" or _cg_label.text != "请闭上眼睛":
		_failures.append("奇妙夜终点没有停在黑屏闭眼引导")
	if not _endpoint_reached:
		_failures.append("奇妙夜 endpoint 未到达")
	if not _failures.is_empty():
		for failure in _failures:
			print("MYSTIC_NIGHT_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("MYSTIC_NIGHT_PASS events=%d sources=%d cgs=%d camera_shots=%d interactions=%d endpoint=%s narration_lines=55 dialogue_lines=36 first_person=true audio=false placeholder=true dev_jump_chapters=wedding_mystic_night_forest source_bounds=%s" % [
		_events.size(),
		_visited_sources.size(),
		_visited_cgs.size(),
		_visited_camera_shots.size(),
		_interactions_done.size(),
		str(_endpoint_reached),
		str(DevJumpPanelScript.source_bounds(_events)),
	])
	get_tree().quit(0)


func _validate_event_contract() -> void:
	var type_counts: Dictionary = {}
	var camera_ids := PackedStringArray()
	var cg_names := PackedStringArray()
	var source_63_lines := PackedStringArray()
	for event in _events:
		var event_type := str(event.get("type", ""))
		type_counts[event_type] = int(type_counts.get(event_type, 0)) + 1
		var text := str(event.get("text", ""))
		if "（" in text or "）" in text:
			_failures.append("括号演出提示被写进显示文字：%s" % text)
		if event_type == "camera":
			camera_ids.append(str(event.get("id", "")))
		if event_type == "cg":
			cg_names.append(str(event.get("name", "")))
		if event_type == "line" and int(event.get("source", 0)) == 63:
			source_63_lines.append(text)
	var expected_counts := {
		"scene": 1,
		"cg": 9,
		"camera": 8,
		"line": 91,
		"interaction": 1,
		"endpoint": 1,
	}
	if type_counts != expected_counts:
		_failures.append("事件类型统计异常：%s" % str(type_counts))
	if DevJumpPanelScript.source_bounds(_events) != Vector2i(1, 146):
		_failures.append("奇妙夜 DOCX 来源范围异常：%s" % DevJumpPanelScript.source_bounds(_events))
	if cg_names != PackedStringArray(CG_NAMES):
		_failures.append("CG 数据表顺序异常：%s" % str(cg_names))
	if camera_ids != PackedStringArray(CAMERA_SHOT_IDS):
		_failures.append("重点镜头数据表顺序异常：%s" % str(camera_ids))
	if source_63_lines != PackedStringArray(["远处偶尔传来不知道什么动物的叫声。", "前面是一片很高的草坡。"]):
		_failures.append("DOCX 第 63 段没有拆成两条旁白")
	_validate_split_line(39, "旁白", "她静静面对着小凌。")
	_validate_split_line(45, "女孩", "可能是因为，我迷路了。")
	_validate_split_line(64, "女孩", "你刚才在哭吗？")
	_validate_split_line(82, "小凌", "我明天要结婚了。")
	for forbidden_source in [102, 135, 140]:
		for event in _events:
			if int(event.get("source", 0)) == forbidden_source:
				_failures.append("未编号技术效果不应进入事件表：DOCX 第 %d 段" % forbidden_source)


func _validate_split_line(source: int, speaker: String, text: String) -> void:
	var matches := 0
	for event in _events:
		if str(event.get("type", "")) != "line" or int(event.get("source", 0)) != source:
			continue
		if str(event.get("speaker", "")) == speaker and str(event.get("text", "")) == text:
			matches += 1
	if matches != 1:
		_failures.append("DOCX 第 %d 段拆分结果异常" % source)


func get_debug_snapshot() -> Dictionary:
	return {
		"mystic_night_events": _events.size(),
		"mystic_night_scene": _current_scene,
		"mystic_night_cg": _current_cg,
		"mystic_night_endpoint": _endpoint_reached,
		"mystic_night_sources": _visited_sources.size(),
		"mystic_night_camera_shots": _visited_camera_shots.size(),
		"mystic_night_interactions": _interactions_done.size(),
		"mystic_night_failures": _failures.size(),
	}
