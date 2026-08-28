extends Control

signal interaction_completed
signal embedded_module_finished(result: Dictionary)

const StoryData := preload("res://scripts/story_data.gd")
const NarrationUIScript := preload("res://scripts/narration_ui.gd")
const DialogueUIScript := preload("res://scripts/dialogue_ui.gd")
const RUNTIME_LOG_PATH := "user://logs/runtime.log"
const TRACE_LOG_PATH := "user://logs/trace_steps.log"
const ENGINE_LOG_PATH := "user://logs/godot.log"
const DEV_JUMP_META_KEY := "qimiaoye_dark_forest_dev_docx_jump"

const COLOR_BG := Color("050608")
const COLOR_PANEL := Color("10141de8")
const COLOR_TEXT := Color("edf1f7")
const COLOR_MUTED := Color("99a3b3")
const COLOR_ACCENT := Color("8fd3ff")
const COLOR_WARNING := Color("f4c36a")
const FONT_PRIMARY_NAME := "Times New Roman"
const FONT_CJK_FALLBACK_NAME := "SimSun"
const STORY_SHAKE_START_SOURCE := 354
const STORY_SHAKE_PEAK_SOURCE := 365
const STORY_SHAKE_END_SOURCE := 366
const STORY_SHAKE_START_STRENGTH := 1.35
const STORY_SHAKE_END_STRENGTH := 18.0
const MODULE_VIEW_SIZE := Vector2i(1280, 720)
const EXPECTED_MODULE_BINDINGS := {
	"ForestRun": {"source": 122, "type": "module", "scene": "res://scenes/forest/parkour/parkour_prototype.tscn", "signal": "parkour_completed"},
	"LakeJump": {"source": 193, "type": "module", "scene": "res://levels/river_jump.tscn", "signal": "finished"},
	"StarJar": {"source": 238, "type": "module", "scene": "res://levels/minigames/firefly_bottle.tscn", "signal": "finished"},
}
const ALLOWED_MODULE_IMAGE_ROOTS := [
	"res://assets/scene/",
	"res://assets/backgrounds/",
	"res://assets/characters/",
	"res://assets/stones/",
	"res://scenes/forest/parkour/",
]

var _events: Array[Dictionary] = []
var _labels: Dictionary = {}
var _event_index := 0
var _current_event_index := -1
var _current_event: Dictionary = {}
var _current_scene := ""
var _verify_mode := false
var _endpoint_reached := false
var _preflight_errors: PackedStringArray = []
var _visited_scenes: Dictionary = {}
var _visited_modules: Dictionary = {}
var _visited_sources: Dictionary = {}
var _step_started_msec := 0
var _narration_lines_seen := 0
var _dialogue_lines_seen := 0
var _psychology_lines_seen := 0
var _active_line_channel := ""
var _pending_dev_jump: Dictionary = {}
var _dev_jump_active := false
var _dev_jump_requested_source := 0
var _dev_jump_actual_source := 0
var _story_shake_active := false
var _story_shake_started := false
var _story_shake_finished := false
var _story_shake_base_position := Vector2.ZERO
var _story_shake_phase := 0.0
var _story_shake_current_strength := 0.0
var _story_shake_target_strength := 0.0
var _story_shake_peak_target_strength := 0.0
var _story_shake_last_source := 0
var _story_shake_start_count := 0
var _story_shake_stop_count := 0
var _module_active := false
var _active_module_id := ""
var _module_run_counts: Dictionary = {}

# 剧情外壳只保存不可见人物状态；独立玩法在隔离的 SubViewport 内管理自己的节点与图片。
var _actor_states := {
	"小凌": {"x": 0.18, "motion": "Idle", "direction": "right", "visible": false},
	"阿麦": {"x": 0.82, "motion": "Idle", "direction": "right", "visible": false},
	"女孩": {"x": 0.72, "motion": "Idle", "direction": "left", "visible": false},
}

var _root_bg: ColorRect
var _scene_label: Label
var _scene_subtitle: Label
var _status_label: Label
var _source_label: Label
var _narration_ui
var _dialogue_ui
var _interaction_panel: PanelContainer
var _interaction_prompt: Label
var _progress: ProgressBar
var _light_button: Button
var _action_button: Button
var _dark_overlay: ColorRect
var _vfx: Control
var _diagnostic_panel: PanelContainer
var _diagnostic_label: Label
var _endpoint_panel: PanelContainer
var _advance_hint_label: Label
var _dev_jump_overlay: ColorRect
var _dev_jump_panel: PanelContainer
var _dev_jump_range_label: Label
var _dev_jump_input: LineEdit
var _dev_jump_button: Button
var _dev_jump_feedback: Label
var _module_host: Control
var _module_viewport_container: SubViewportContainer
var _module_viewport: SubViewport
var _primary_font: SystemFont
var _cjk_fallback_font: SystemFont

var _awaiting_action_button := false
var _light_active := false
var _light_hovered := false
var _movement_active := false
var _movement_allow_reverse := false
var _movement_reverse_applied := false
var _right_held := false
var _left_held := false


class VFXCanvas extends Control:
	var mode := "none"
	var phase := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func set_mode(next_mode: String) -> void:
		mode = next_mode
		queue_redraw()

	func _process(delta: float) -> void:
		phase += delta
		if mode != "none":
			queue_redraw()

	func _draw() -> void:
		var center := size * Vector2(0.50, 0.52)
		match mode:
			"heart":
				for i in range(7, 0, -1):
					var radius := 22.0 + float(i) * 24.0
					var alpha := 0.018 + float(8 - i) * 0.012
					draw_circle(center, radius, Color(0.72, 0.48, 0.92, alpha))
			"fireflies":
				for i in range(13):
					var t := fmod(phase * 0.18 + float(i) / 13.0, 1.0)
					var p := Vector2(size.x * (0.2 + t * 0.72), size.y * (0.48 + sin(float(i) * 1.7 + phase) * 0.07))
					var glow := 3.5 + sin(phase * 3.0 + float(i)) * 1.5
					draw_circle(p, glow, Color(0.94, 0.88, 0.38, 0.72))
			"single_firefly":
				var p := Vector2(size.x * 0.50, size.y * 0.53)
				var glow := 6.0 + sin(phase * 3.0) * 2.5
				for i in range(4, 0, -1):
					draw_circle(p, glow * float(i), Color(0.95, 0.88, 0.35, 0.035 * float(5 - i)))
				draw_circle(p, glow, Color(1.0, 0.94, 0.58, 0.88))
			"motion":
				for i in range(9):
					var y := size.y * (0.24 + float(i) * 0.065)
					var offset := fmod(phase * 380.0 + float(i) * 130.0, size.x + 240.0) - 120.0
					draw_line(Vector2(offset - 150.0, y), Vector2(offset, y), Color(0.56, 0.74, 0.88, 0.16), 2.0)
			"water":
				for i in range(8):
					var y := size.y * (0.34 + float(i) * 0.055) - fmod(phase * 80.0, 70.0)
					draw_line(Vector2(0, y), Vector2(size.x, y - 25.0), Color(0.65, 0.87, 0.94, 0.08 + float(i) * 0.018), 12.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending_dev_jump = _take_pending_dev_jump()
	_verify_mode = OS.get_cmdline_user_args().has("--verify")
	_configure_typography()
	_build_ui()
	_story_shake_base_position = position
	_initialize_logs(not _pending_dev_jump.is_empty())
	_log_runtime("TYPOGRAPHY primary=%s cjk_fallback=%s latin_A=%s cjk_zhong=%s" % [
		FONT_PRIMARY_NAME,
		FONT_CJK_FALLBACK_NAME,
		_primary_font.has_char("A".unicode_at(0)),
		_cjk_fallback_font.has_char("中".unicode_at(0)),
	])
	_events = StoryData.get_events()
	_build_label_index()
	_refresh_dev_jump_preview()
	_preflight_errors = _validate_contract()
	var dev_jump_error := _apply_pending_dev_jump()
	if not dev_jump_error.is_empty():
		_preflight_errors.append(dev_jump_error)
	_log_runtime("START verify_mode=%s events=%d dev_jump=%s requested_source=%d actual_source=%d" % [
		_verify_mode,
		_events.size(),
		_dev_jump_active,
		_dev_jump_requested_source,
		_dev_jump_actual_source,
	])
	if not _preflight_errors.is_empty():
		for issue in _preflight_errors:
			_log_runtime("PREFLIGHT_ERROR %s" % issue)
	if _verify_mode and not _preflight_errors.is_empty():
		_finish_verification(false, _preflight_errors)
		return
	call_deferred("_run_story")


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
	_root_bg.color = COLOR_BG
	_root_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_bg)

	_scene_label = Label.new()
	_scene_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scene_label.add_theme_font_size_override("font_size", 46)
	_scene_label.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95, 0.82))
	_scene_label.text = "环境背景图0"
	_scene_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene_label)

	_scene_subtitle = Label.new()
	_scene_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	_scene_subtitle.offset_left = -360
	_scene_subtitle.offset_right = 360
	_scene_subtitle.offset_top = 64
	_scene_subtitle.offset_bottom = 100
	_scene_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_subtitle.add_theme_font_size_override("font_size", 16)
	_scene_subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	_scene_subtitle.text = "剧情外壳纯文字 · 独立玩法按 DOCX 行切入"
	_scene_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scene_subtitle)

	_vfx = VFXCanvas.new()
	add_child(_vfx)

	_dark_overlay = ColorRect.new()
	_dark_overlay.color = Color.BLACK
	_dark_overlay.modulate.a = 0.0
	_dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dark_overlay)

	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_margin.offset_left = -260
	top_margin.offset_top = 14
	top_margin.offset_right = 260
	top_margin.offset_bottom = 112
	top_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.visible = _verify_mode
	add_child(top_margin)

	var top_col := VBoxContainer.new()
	top_col.add_theme_constant_override("separation", 6)
	top_margin.add_child(top_col)

	_source_label = Label.new()
	_source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_source_label.add_theme_font_size_override("font_size", 12)
	_source_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_source_label.text = "DOCX · 等待启动"
	top_col.add_child(_source_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", COLOR_WARNING)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "演出状态：初始化"
	top_col.add_child(_status_label)

	_build_narration_ui()
	_build_dialogue_ui()
	_build_interaction_panel()
	_build_diagnostic_panel()
	_build_endpoint_panel()
	_build_advance_hint()
	_build_module_host()
	_build_dev_jump_panel()


func _build_narration_ui() -> void:
	_narration_ui = NarrationUIScript.new()
	_narration_ui.name = "NARRATION_UI"
	_narration_ui.anchor_left = 0.16
	_narration_ui.anchor_top = 0.02
	_narration_ui.anchor_right = 0.84
	_narration_ui.anchor_bottom = 0.20
	_narration_ui.offset_left = 0
	_narration_ui.offset_top = 0
	_narration_ui.offset_right = 0
	_narration_ui.offset_bottom = 0
	add_child(_narration_ui)


func _build_dialogue_ui() -> void:
	_dialogue_ui = DialogueUIScript.new()
	_dialogue_ui.name = "DIALOGUE_UI"
	add_child(_dialogue_ui)


func _build_interaction_panel() -> void:
	_interaction_panel = PanelContainer.new()
	_interaction_panel.set_anchors_preset(Control.PRESET_CENTER)
	_interaction_panel.offset_left = -300
	_interaction_panel.offset_right = 300
	_interaction_panel.offset_top = -100
	_interaction_panel.offset_bottom = 100
	_interaction_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0d1119f2")
	style.border_color = Color("8fd3ffb0")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	_interaction_panel.add_theme_stylebox_override("panel", style)
	add_child(_interaction_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_interaction_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	_interaction_prompt = Label.new()
	_interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_interaction_prompt.add_theme_font_size_override("font_size", 20)
	col.add_child(_interaction_prompt)

	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 100
	_progress.value = 0
	_progress.show_percentage = true
	_progress.custom_minimum_size.y = 28
	col.add_child(_progress)

	_light_button = Button.new()
	_light_button.text = "光源交互区\n持续悬停"
	_light_button.custom_minimum_size = Vector2(210, 70)
	_light_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_light_button.mouse_entered.connect(_on_light_mouse_entered)
	_light_button.mouse_exited.connect(_on_light_mouse_exited)
	_light_button.visible = false
	col.add_child(_light_button)

	_action_button = Button.new()
	_action_button.text = "执行"
	_action_button.custom_minimum_size = Vector2(260, 52)
	_action_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action_button.pressed.connect(_on_action_button_pressed)
	_action_button.visible = false
	col.add_child(_action_button)


func _build_diagnostic_panel() -> void:
	_diagnostic_panel = PanelContainer.new()
	_diagnostic_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_diagnostic_panel.offset_left = -520
	_diagnostic_panel.offset_right = -18
	_diagnostic_panel.offset_top = 18
	_diagnostic_panel.offset_bottom = 340
	_diagnostic_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("090c12f4")
	style.border_color = Color("f4c36aa8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	_diagnostic_panel.add_theme_stylebox_override("panel", style)
	add_child(_diagnostic_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_diagnostic_panel.add_child(margin)

	_diagnostic_label = Label.new()
	_diagnostic_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnostic_label.add_theme_font_size_override("font_size", 14)
	_diagnostic_label.add_theme_color_override("font_color", COLOR_TEXT)
	margin.add_child(_diagnostic_label)
	_refresh_diagnostics()


func _build_endpoint_panel() -> void:
	_endpoint_panel = PanelContainer.new()
	_endpoint_panel.set_anchors_preset(Control.PRESET_CENTER)
	_endpoint_panel.offset_left = -320
	_endpoint_panel.offset_right = 320
	_endpoint_panel.offset_top = -90
	_endpoint_panel.offset_bottom = 90
	_endpoint_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color("080a0ff5")
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	_endpoint_panel.add_theme_stylebox_override("panel", style)
	add_child(_endpoint_panel)

	var label := Label.new()
	label.text = "[ENDPOINT]\n黑暗森林章节在此结束\n\n本并行版停止，不进入下一章。"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	_endpoint_panel.add_child(label)


func _build_advance_hint() -> void:
	_advance_hint_label = Label.new()
	_advance_hint_label.name = "AdvanceKeyboardHint"
	_advance_hint_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_advance_hint_label.offset_left = 24
	_advance_hint_label.offset_top = 18
	_advance_hint_label.offset_right = 430
	_advance_hint_label.offset_bottom = 48
	_advance_hint_label.text = "按 Enter / Space 继续"
	_advance_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_advance_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_advance_hint_label.add_theme_font_size_override("font_size", 15)
	_advance_hint_label.add_theme_color_override("font_color", Color(0.72, 0.77, 0.84, 0.78))
	_advance_hint_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	_advance_hint_label.add_theme_constant_override("shadow_offset_x", 1)
	_advance_hint_label.add_theme_constant_override("shadow_offset_y", 1)
	_advance_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_advance_hint_label.visible = false
	add_child(_advance_hint_label)


func _build_module_host() -> void:
	_module_host = Control.new()
	_module_host.name = "EmbeddedModuleHost"
	_module_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_module_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_module_host.z_index = 100
	_module_host.visible = false
	add_child(_module_host)

	var backdrop := ColorRect.new()
	backdrop.name = "ModuleBackdrop"
	backdrop.color = Color.BLACK
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_module_host.add_child(backdrop)

	_module_viewport_container = SubViewportContainer.new()
	_module_viewport_container.name = "ModuleViewportContainer"
	_module_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_module_viewport_container.stretch = true
	_module_viewport_container.stretch_shrink = 1
	_module_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_module_host.add_child(_module_viewport_container)

	_module_viewport = SubViewport.new()
	_module_viewport.name = "ModuleViewport"
	_module_viewport.size = MODULE_VIEW_SIZE
	_module_viewport.handle_input_locally = true
	_module_viewport.gui_disable_input = false
	_module_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_module_viewport_container.add_child(_module_viewport)


func _build_dev_jump_panel() -> void:
	_dev_jump_overlay = ColorRect.new()
	_dev_jump_overlay.name = "DeveloperDocxJumpOverlay"
	_dev_jump_overlay.color = Color(0.01, 0.015, 0.025, 0.88)
	_dev_jump_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dev_jump_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_dev_jump_overlay.z_index = 200
	_dev_jump_overlay.visible = false
	add_child(_dev_jump_overlay)

	_dev_jump_panel = PanelContainer.new()
	_dev_jump_panel.name = "DeveloperDocxJumpPanel"
	_dev_jump_panel.set_anchors_preset(Control.PRESET_CENTER)
	_dev_jump_panel.offset_left = -310
	_dev_jump_panel.offset_right = 310
	_dev_jump_panel.offset_top = -170
	_dev_jump_panel.offset_bottom = 170
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("0b0f17fa")
	panel_style.border_color = Color("f4c36ad0")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	_dev_jump_panel.add_theme_stylebox_override("panel", panel_style)
	_dev_jump_overlay.add_child(_dev_jump_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	_dev_jump_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Label.new()
	title.text = "开发者功能 · DOCX 行回溯"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", COLOR_WARNING)
	col.add_child(title)

	var help := Label.new()
	help.text = "输入 DOCX 来源行。若该行没有剧情事件，将从下一条有事件的行开始。\n跳转会重载灰盒场景，并保留运行日志与逐步检测日志。"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 16)
	help.add_theme_color_override("font_color", COLOR_TEXT)
	col.add_child(help)

	_dev_jump_range_label = Label.new()
	_dev_jump_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dev_jump_range_label.add_theme_font_size_override("font_size", 14)
	_dev_jump_range_label.add_theme_color_override("font_color", COLOR_MUTED)
	col.add_child(_dev_jump_range_label)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 12)
	col.add_child(input_row)

	_dev_jump_input = LineEdit.new()
	_dev_jump_input.name = "DeveloperDocxLineInput"
	_dev_jump_input.placeholder_text = "例如：181"
	_dev_jump_input.custom_minimum_size = Vector2(300, 48)
	_dev_jump_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dev_jump_input.add_theme_font_size_override("font_size", 20)
	_dev_jump_input.text_changed.connect(_on_dev_jump_text_changed)
	_dev_jump_input.text_submitted.connect(_on_dev_jump_text_submitted)
	input_row.add_child(_dev_jump_input)

	_dev_jump_button = Button.new()
	_dev_jump_button.name = "DeveloperDocxJumpButton"
	_dev_jump_button.text = "从此行开始"
	_dev_jump_button.custom_minimum_size = Vector2(170, 48)
	_dev_jump_button.pressed.connect(_submit_dev_jump)
	input_row.add_child(_dev_jump_button)

	_dev_jump_feedback = Label.new()
	_dev_jump_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dev_jump_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_jump_feedback.add_theme_font_size_override("font_size", 15)
	_dev_jump_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
	_dev_jump_feedback.custom_minimum_size.y = 42
	col.add_child(_dev_jump_feedback)

	var close_button := Button.new()
	close_button.text = "取消 · Esc / F4"
	close_button.custom_minimum_size = Vector2(210, 40)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(_close_dev_jump_panel)
	col.add_child(close_button)


func _process(delta: float) -> void:
	_update_story_shake(delta)
	if _module_active:
		return
	if _dev_jump_overlay != null and _dev_jump_overlay.visible:
		return
	if _light_active and _light_hovered:
		_progress.value = minf(100.0, _progress.value + delta * 42.0)
		if _progress.value >= 100.0:
			_light_active = false
			_light_hovered = false
			interaction_completed.emit()
	if _movement_active:
		if _left_held and _movement_allow_reverse and not _movement_reverse_applied:
			_apply_reverse_darkness()
		if _right_held:
			_progress.value = minf(100.0, _progress.value + delta * 48.0)
			if _progress.value >= 100.0:
				_movement_active = false
				_right_held = false
				_left_held = false
				interaction_completed.emit()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F4:
		_toggle_dev_jump_panel()
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_ESCAPE and _dev_jump_overlay != null and _dev_jump_overlay.visible:
		_close_dev_jump_panel()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if _module_active:
		return
	if _dev_jump_overlay != null and _dev_jump_overlay.visible:
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_F3 and key_event.pressed and not key_event.echo:
		_diagnostic_panel.visible = not _diagnostic_panel.visible
		_refresh_diagnostics()
		get_viewport().set_input_as_handled()
		return
	if key_event.pressed and not key_event.echo and not _active_line_channel.is_empty() and key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		if _active_line_channel == "NARRATION":
			_narration_ui.request_advance()
		else:
			_dialogue_ui.request_advance()
		get_viewport().set_input_as_handled()
		return
	var key: Key = key_event.keycode
	var physical: Key = key_event.physical_keycode
	if key == KEY_RIGHT or key == KEY_D or physical == KEY_D:
		_right_held = key_event.pressed
	if key == KEY_LEFT or key == KEY_A or physical == KEY_A:
		_left_held = key_event.pressed


func _toggle_dev_jump_panel() -> void:
	if _dev_jump_overlay == null:
		return
	if _dev_jump_overlay.visible:
		_close_dev_jump_panel()
	else:
		_open_dev_jump_panel()


func _open_dev_jump_panel() -> void:
	if _dev_jump_overlay == null or _dev_jump_input == null:
		return
	_dev_jump_overlay.visible = true
	_right_held = false
	_left_held = false
	var bounds := _docx_source_bounds()
	var current_source := int(_current_event.get("source", 0))
	var suggested_source := current_source if current_source > 0 else bounds.x
	_dev_jump_input.text = str(suggested_source)
	_dev_jump_input.select_all()
	_dev_jump_input.grab_focus()
	_refresh_dev_jump_preview()


func _close_dev_jump_panel() -> void:
	if _dev_jump_overlay == null:
		return
	_dev_jump_overlay.visible = false
	if _dev_jump_input != null:
		_dev_jump_input.release_focus()


func _on_dev_jump_text_changed(_new_text: String) -> void:
	_refresh_dev_jump_preview()


func _on_dev_jump_text_submitted(_submitted_text: String) -> void:
	_submit_dev_jump()


func _refresh_dev_jump_preview() -> void:
	if _dev_jump_input == null or _dev_jump_button == null or _dev_jump_feedback == null:
		return
	var bounds := _docx_source_bounds()
	var current_source := int(_current_event.get("source", 0))
	_dev_jump_range_label.text = "当前 DOCX 行：%s　|　可跳转来源范围：%d–%d　|　F4 打开/关闭" % [
		str(current_source) if current_source > 0 else "等待启动",
		bounds.x,
		bounds.y,
	]
	var raw := _dev_jump_input.text.strip_edges()
	if raw.is_empty():
		_dev_jump_feedback.text = "请输入一个 DOCX 行号。"
		_dev_jump_button.disabled = true
		return
	if not raw.is_valid_int() or int(raw) <= 0:
		_dev_jump_feedback.text = "行号必须是正整数。"
		_dev_jump_button.disabled = true
		return
	var requested_source := int(raw)
	var resolved := _resolve_docx_source_line(requested_source)
	if resolved.is_empty():
		_dev_jump_feedback.text = "第 %d 行之后没有剧情事件；最后一个来源行是 %d。" % [requested_source, bounds.y]
		_dev_jump_button.disabled = true
		return
	var actual_source := int(resolved.get("source", 0))
	var event: Dictionary = resolved.get("event", {})
	var event_id := _event_debug_id(event)
	if bool(resolved.get("exact", false)):
		_dev_jump_feedback.text = "精确落点：DOCX 第 %d 行 · %s / %s" % [actual_source, event.get("type", ""), event_id]
	else:
		_dev_jump_feedback.text = "第 %d 行没有事件，将从下一条：DOCX 第 %d 行 · %s / %s 开始" % [
			requested_source,
			actual_source,
			event.get("type", ""),
			event_id,
		]
	_dev_jump_button.disabled = false


func _submit_dev_jump() -> void:
	if _dev_jump_input == null:
		return
	var raw := _dev_jump_input.text.strip_edges()
	if not raw.is_valid_int() or int(raw) <= 0:
		_refresh_dev_jump_preview()
		return
	var requested_source := int(raw)
	var resolved := _resolve_docx_source_line(requested_source)
	if resolved.is_empty():
		_refresh_dev_jump_preview()
		return
	var actual_source := int(resolved.get("source", 0))
	var target_index := int(resolved.get("index", -1))
	var from_source := int(_current_event.get("source", 0))
	var payload := {
		"requested_source": requested_source,
		"actual_source": actual_source,
		"target_index": target_index,
		"from_source": from_source,
		"requested_at": Time.get_datetime_string_from_system(),
	}
	_log_runtime("DEV_JUMP_REQUEST from_source=%d requested_source=%d actual_source=%d target_step=%d exact=%s" % [
		from_source,
		requested_source,
		actual_source,
		target_index + 1,
		resolved.get("exact", false),
	])
	_append_log(TRACE_LOG_PATH, "%s | phase=DEV_JUMP_REQUEST | from_source=%d | requested_source=%d | actual_source=%d | target_step=%d" % [
		Time.get_time_string_from_system(),
		from_source,
		requested_source,
		actual_source,
		target_index + 1,
	])
	get_tree().root.set_meta(DEV_JUMP_META_KEY, payload)
	_dev_jump_button.disabled = true
	_dev_jump_feedback.text = "正在跳转到 DOCX 第 %d 行……" % actual_source
	call_deferred("_reload_for_dev_jump")


func _reload_for_dev_jump() -> void:
	var reload_error := get_tree().reload_current_scene()
	if reload_error == OK:
		return
	get_tree().root.remove_meta(DEV_JUMP_META_KEY)
	_dev_jump_button.disabled = false
	_dev_jump_feedback.text = "场景重载失败，错误码：%d" % reload_error
	_log_runtime("DEV_JUMP_RELOAD_FAIL error=%d" % reload_error)


func _take_pending_dev_jump() -> Dictionary:
	var root := get_tree().root
	if root == null or not root.has_meta(DEV_JUMP_META_KEY):
		return {}
	var raw_payload = root.get_meta(DEV_JUMP_META_KEY)
	root.remove_meta(DEV_JUMP_META_KEY)
	if typeof(raw_payload) == TYPE_DICTIONARY:
		var payload: Dictionary = raw_payload
		return payload.duplicate(true)
	return {}


func _apply_pending_dev_jump() -> String:
	if _pending_dev_jump.is_empty():
		return ""
	var requested_source := int(_pending_dev_jump.get("requested_source", 0))
	var resolved := _resolve_docx_source_line(requested_source)
	if resolved.is_empty():
		return "开发跳转目标无效：DOCX 第 %d 行" % requested_source
	var target_index := int(resolved.get("index", -1))
	if target_index < 0 or target_index >= _events.size():
		return "开发跳转事件索引越界：%d" % target_index
	_dev_jump_active = true
	_dev_jump_requested_source = requested_source
	_dev_jump_actual_source = int(resolved.get("source", 0))
	_event_index = target_index
	_current_event_index = target_index
	_current_event = _events[target_index]
	_restore_dev_jump_scene_context(target_index)
	var from_source := int(_pending_dev_jump.get("from_source", 0))
	var event_id := _event_debug_id(_current_event)
	_log_runtime("DEV_JUMP_APPLY from_source=%d requested_source=%d actual_source=%d target_step=%d scene_context=%s event=%s" % [
		from_source,
		_dev_jump_requested_source,
		_dev_jump_actual_source,
		target_index + 1,
		_current_scene,
		event_id,
	])
	_append_log(TRACE_LOG_PATH, "%s | phase=DEV_JUMP_APPLY | from_source=%d | requested_source=%d | actual_source=%d | target_step=%d | scene=%s | event=%s" % [
		Time.get_time_string_from_system(),
		from_source,
		_dev_jump_requested_source,
		_dev_jump_actual_source,
		target_index + 1,
		_current_scene,
		event_id,
	])
	_source_label.text = "DOCX 行 %d · 开发跳转待启动" % _dev_jump_actual_source
	_status("开发跳转：请求第 %d 行，实际从第 %d 行开始" % [_dev_jump_requested_source, _dev_jump_actual_source])
	return ""


func _restore_dev_jump_scene_context(target_index: int) -> void:
	var scene_context := "环境背景图0"
	for i in range(clampi(target_index, 0, _events.size())):
		var event: Dictionary = _events[i]
		match str(event.get("type", "")):
			"scene":
				scene_context = str(event.get("name", scene_context))
			"transition":
				scene_context = str(event.get("to", scene_context))
	_current_scene = scene_context
	_scene_label.text = scene_context
	_scene_subtitle.text = "剧情外壳纯文字 · 开发跳转场景恢复"
	_dark_overlay.modulate.a = 0.0
	_vfx.set_mode("none")


func _docx_source_bounds() -> Vector2i:
	var min_source := 2147483647
	var max_source := 0
	for event in _events:
		var source := int(event.get("source", 0))
		if source <= 0:
			continue
		min_source = mini(min_source, source)
		max_source = maxi(max_source, source)
	if max_source == 0:
		return Vector2i.ZERO
	return Vector2i(min_source, max_source)


func _resolve_docx_source_line(requested_source: int) -> Dictionary:
	if requested_source <= 0:
		return {}
	var best_index := -1
	var best_source := 2147483647
	for i in range(_events.size()):
		var event: Dictionary = _events[i]
		var source := int(event.get("source", 0))
		if source <= 0 or source < requested_source:
			continue
		if source < best_source:
			best_source = source
			best_index = i
	if best_index < 0:
		return {}
	return {
		"index": best_index,
		"source": best_source,
		"exact": best_source == requested_source,
		"event": _events[best_index],
	}


func _event_debug_id(event: Dictionary) -> String:
	return str(event.get("id", event.get("name", event.get("type", "event"))))


func _run_story() -> void:
	if _verify_mode:
		var ui_queue_errors := await _run_ui_queue_stress_check()
		if not ui_queue_errors.is_empty():
			_finish_verification(false, ui_queue_errors)
			return
	while _event_index < _events.size() and not _endpoint_reached:
		_current_event_index = _event_index
		_current_event = _events[_event_index]
		_event_index += 1
		_step_started_msec = Time.get_ticks_msec()
		_sync_story_shake_for_event(_current_event)
		_trace_current_step("BEGIN")
		await _execute_event(_current_event)
		_trace_current_step("END")
	if _endpoint_reached:
		_complete_story()
	elif _event_index >= _events.size():
		var issue := "事件列表耗尽但未到达 ENDPOINT"
		_log_runtime("FATAL %s" % issue)
		if _verify_mode:
			_finish_verification(false, PackedStringArray([issue]))
		else:
			_show_fatal(issue)


func _execute_event(event: Dictionary) -> void:
	_set_advance_hint(false)
	var kind := str(event.get("type", ""))
	match kind:
		"scene":
			_set_scene(str(event.get("name", "未命名场景")))
			await _brief_pause()
		"transition":
			await _play_transition(event)
		"line":
			await _show_line(event)
		"action", "effect", "asset_suppressed":
			await _run_action(event)
		"wait":
			await _run_wait(event)
		"choice":
			await _run_choice(event)
		"interaction":
			await _run_interaction(event)
		"movement":
			await _run_movement(event)
		"module":
			await _run_embedded_module(event, false)
		"module_placeholder":
			await _run_embedded_module(event, true)
		"module_skip":
			await _run_module_skip(event)
		"audio":
			_status("[AUDIO] %s" % str(event.get("cue", "")))
			_log_runtime("AUDIO cue=%s" % str(event.get("cue", "")))
			await _brief_pause()
		"goto":
			_jump_to_label(str(event.get("target", "")))
		"label":
			pass
		"endpoint":
			_endpoint_reached = true
			_status("[ENDPOINT] %s" % str(event.get("text", "")))
			_log_runtime("ENDPOINT id=%s" % str(event.get("id", "")))
		_:
			_preflight_errors.append("未知事件类型：%s" % kind)


func _show_line(event: Dictionary) -> void:
	_interaction_panel.visible = false
	_endpoint_panel.visible = false
	var channel := _resolve_line_channel(event)
	var speaker := str(event.get("speaker", ""))
	var text := str(event.get("text", ""))
	var is_psychology := _is_psychology_event(event)
	var display_speaker := "小凌" if is_psychology else speaker
	var display_text := _format_psychology_text(speaker, text) if is_psychology else text
	if channel == "NARRATION":
		_dialogue_ui.hide_dialogue()
		await _narration_ui.present(text, _verify_mode)
		_narration_lines_seen += 1
		_status("NARRATION_UI 等待继续；队列独立运行")
		_log_runtime("LINE channel=NARRATION source=%s queue_visible=%d center_error=%.3f width_overflow=%.3f direct_reveal=true text=%s" % [
			event.get("source", 0),
			_narration_ui.get_visible_entry_count(),
			_narration_ui.get_max_center_error(),
			_narration_ui.get_max_width_overflow(),
			text,
		])
		if _verify_mode:
			await _brief_pause()
			return
		_active_line_channel = "NARRATION"
		_narration_ui.set_advance_waiting(true)
		_set_advance_hint(true)
		await _narration_ui.advance_requested
		_set_advance_hint(false)
		_narration_ui.set_advance_waiting(false)
	else:
		_narration_ui.begin_fade_for_dialogue(_verify_mode)
		await _dialogue_ui.present_line(display_speaker, display_text, _verify_mode)
		_dialogue_lines_seen += 1
		if is_psychology:
			_psychology_lines_seen += 1
		_status("DIALOGUE_UI 等待继续；旁白区域独立消散")
		_log_runtime("LINE channel=DIALOGUE source=%s speaker=%s psychology=%s alignment=left progressive_reveal=true text=%s" % [
			event.get("source", 0),
			display_speaker,
			is_psychology,
			display_text,
		])
		if _verify_mode:
			await _brief_pause()
			return
		_active_line_channel = "DIALOGUE"
		_dialogue_ui.set_advance_waiting(true)
		_set_advance_hint(true)
		await _dialogue_ui.advance_requested
		_set_advance_hint(false)
		_dialogue_ui.set_advance_waiting(false)
	_active_line_channel = ""


func _set_advance_hint(enabled: bool) -> void:
	if _advance_hint_label != null:
		_advance_hint_label.visible = enabled and not _verify_mode


func _resolve_line_channel(event: Dictionary) -> String:
	var explicit_channel := str(event.get("channel", ""))
	if explicit_channel in ["NARRATION", "DIALOGUE"]:
		return explicit_channel
	var speaker := str(event.get("speaker", ""))
	if speaker == "旁白":
		return "NARRATION"
	return "DIALOGUE"


func _is_psychology_event(event: Dictionary) -> bool:
	return str(event.get("speaker", "")).begins_with("心理")


func _format_psychology_text(speaker: String, text: String) -> String:
	var cue := ""
	var cue_start := speaker.find("（")
	var cue_end := speaker.find("）", cue_start + 1)
	if cue_start >= 0 and cue_end > cue_start:
		cue = speaker.substr(cue_start + 1, cue_end - cue_start - 1).strip_edges()
	var thought := text.strip_edges()
	if not cue.is_empty() and not thought.is_empty():
		return "（%s：%s）" % [cue, thought]
	if not cue.is_empty():
		return "（%s）" % cue
	return "（%s）" % thought


func _run_ui_queue_stress_check() -> PackedStringArray:
	var errors := PackedStringArray()
	_narration_ui.clear_immediately()
	_narration_ui.enqueue("__NARRATION_QUEUE_1__", true)
	_narration_ui.enqueue("__NARRATION_QUEUE_2__", true)
	_narration_ui.enqueue("__NARRATION_QUEUE_3__", true)
	await _narration_ui.wait_until_idle()
	if not _narration_ui.is_queue_idle():
		errors.append("NARRATION_UI 快速队列未归于 idle")
	if _narration_ui.get_visible_entry_count() > 2:
		errors.append("NARRATION_UI 稳态条目超过2条")
	if _narration_ui.get_max_observed_count() > 3:
		errors.append("NARRATION_UI 动画期间条目超过3条")
	if _narration_ui.get_latest_text() != "__NARRATION_QUEUE_3__":
		errors.append("NARRATION_UI 快速队列顺序错误")
	if not _narration_ui.is_horizontally_centered():
		errors.append("NARRATION_UI 快速队列文字未保持居中")
	if not _narration_ui.uses_direct_reveal():
		errors.append("NARRATION_UI 整句直接淡入未启用")
	_narration_ui.clear_immediately()

	_dialogue_ui.clear_immediately()
	_dialogue_ui.enqueue_line("测试", "__DIALOGUE_QUEUE_1__", true)
	_dialogue_ui.enqueue_line("测试", "__DIALOGUE_QUEUE_2__", true)
	_dialogue_ui.enqueue_line("测试", "__DIALOGUE_QUEUE_3__", true)
	await _dialogue_ui.wait_until_idle()
	if not _dialogue_ui.is_queue_idle():
		errors.append("DIALOGUE_UI 快速队列未归于 idle")
	if _dialogue_ui.get_body_text() != "__DIALOGUE_QUEUE_3__":
		errors.append("DIALOGUE_UI 快速队列顺序错误")
	if not _dialogue_ui.is_panel_centered():
		errors.append("DIALOGUE_UI 面板未保持屏幕居中")
	if not _dialogue_ui.is_text_left_aligned():
		errors.append("DIALOGUE_UI 快速队列文字未保持左对齐")
	if not _dialogue_ui.is_body_compact_at_top():
		errors.append("DIALOGUE_UI 快速队列正文未保持顶部紧凑布局")
	if not _dialogue_ui.is_continue_button_centered():
		errors.append("DIALOGUE_UI 快速队列继续按钮未保持居中")
	if not _dialogue_ui.uses_progressive_reveal():
		errors.append("DIALOGUE_UI 逐字淡显未启用")
	_dialogue_ui.show_choice("__CHOICE_LAYOUT__", [
		{"id": "left", "text": "左侧选项"},
		{"id": "right", "text": "右侧选项"},
	])
	await get_tree().process_frame
	if not _dialogue_ui.is_choice_group_centered():
		errors.append("DIALOGUE_UI 选项组未按对白框中轴居中")
	_dialogue_ui.clear_immediately()
	_log_runtime("UI_QUEUE_STRESS narration_max=%d dialogue_depth=%d errors=%d" % [
		_narration_ui.get_max_observed_count(),
		_dialogue_ui.get_max_queue_depth(),
		errors.size(),
	])
	return errors


func _run_choice(event: Dictionary) -> void:
	_interaction_panel.visible = false
	_narration_ui.begin_fade_for_dialogue(_verify_mode)
	_dialogue_ui.show_choice(str(event.get("prompt", "")), event.get("options", []))
	var selected := ""
	if _verify_mode:
		selected = "stay" if str(event.get("id", "")) == "follow_choice" else "lake_no"
		await _brief_pause()
	else:
		selected = await _dialogue_ui.choice_selected
	var routes: Dictionary = event.get("routes", {})
	var target := str(routes.get(selected, ""))
	_log_runtime("CHOICE id=%s selected=%s target=%s" % [event.get("id", ""), selected, target])
	_dialogue_ui.hide_dialogue()
	_jump_to_label(target)


func _run_interaction(event: Dictionary) -> void:
	_dialogue_ui.hide_dialogue()
	_interaction_panel.visible = true
	_interaction_prompt.text = str(event.get("prompt", ""))
	_progress.value = 0
	_light_button.visible = false
	_action_button.visible = false
	var interaction_id := str(event.get("id", ""))
	_status("等待玩家交互：%s" % interaction_id)
	if interaction_id == "light_hover":
		_vfx.set_mode("heart")
		_light_button.visible = true
		if _verify_mode:
			_progress.value = 100
			await _brief_pause()
		else:
			_light_active = true
			await interaction_completed
			_light_active = false
	elif interaction_id == "jump_button":
		_action_button.text = "跳水"
		_action_button.visible = true
		if _verify_mode:
			await _brief_pause()
		else:
			_awaiting_action_button = true
			await interaction_completed
			_awaiting_action_button = false
	_log_runtime("INTERACTION_COMPLETE id=%s" % interaction_id)
	_interaction_panel.visible = false


func _run_movement(event: Dictionary) -> void:
	_dialogue_ui.hide_dialogue()
	_interaction_panel.visible = true
	_interaction_prompt.text = str(event.get("prompt", ""))
	_progress.value = 0
	_light_button.visible = false
	_action_button.visible = false
	_movement_allow_reverse = bool(event.get("allow_reverse", false))
	_movement_reverse_applied = false
	_status("玩家控制权：左右移动；等待右侧 trigger")
	if _verify_mode:
		if _movement_allow_reverse:
			_apply_reverse_darkness()
		_progress.value = 100
		_actor_states["小凌"]["motion"] = "Run" if str(event.get("id", "")) == "forest_run_entry" else "Walk"
		_actor_states["小凌"]["x"] = 0.88
		await _brief_pause()
	else:
		_movement_active = true
		await interaction_completed
		_movement_active = false
	_actor_states["小凌"]["motion"] = "Idle"
	_log_runtime("MOVEMENT_COMPLETE id=%s reverse=%s" % [event.get("id", ""), _movement_reverse_applied])
	_interaction_panel.visible = false


func _run_wait(event: Dictionary) -> void:
	var seconds := float(event.get("seconds", 0.0))
	_status(str(event.get("status", "等待 %.1f 秒" % seconds)))
	_log_runtime("WAIT seconds=%.1f source=%s" % [seconds, event.get("source", 0)])
	if _verify_mode:
		await _brief_pause()
	else:
		await get_tree().create_timer(seconds).timeout


func _run_embedded_module(event: Dictionary, is_placeholder: bool) -> void:
	var module_id := str(event.get("id", ""))
	var source := int(event.get("source", 0))
	var scene_path := str(event.get("scene", ""))
	var completion_signal := str(event.get("completion_signal", ""))
	_visited_modules[module_id] = true
	_module_run_counts[module_id] = int(_module_run_counts.get(module_id, 0)) + 1
	_status("[%s] %s · DOCX %d" % ["MODULE_PLACEHOLDER" if is_placeholder else "MODULE", module_id, source])
	_log_runtime("MODULE_START id=%s source=%d kind=%s scene=%s completion_signal=%s run=%d" % [
		module_id,
		source,
		"placeholder" if is_placeholder else "playable",
		scene_path,
		completion_signal,
		int(_module_run_counts[module_id]),
	])

	if not ResourceLoader.exists(scene_path, "PackedScene"):
		_record_module_failure(module_id, source, "场景资源不存在：%s" % scene_path)
		await _brief_pause()
		return
	var packed_resource := load(scene_path)
	if not packed_resource is PackedScene:
		_record_module_failure(module_id, source, "资源不是 PackedScene：%s" % scene_path)
		await _brief_pause()
		return
	var module_instance := (packed_resource as PackedScene).instantiate()
	if module_instance == null:
		_record_module_failure(module_id, source, "场景实例化失败：%s" % scene_path)
		await _brief_pause()
		return
	if not module_instance.has_signal(completion_signal):
		_record_module_failure(module_id, source, "缺少完成信号：%s" % completion_signal)
		module_instance.free()
		await _brief_pause()
		return

	if module_instance.has_method("setup"):
		module_instance.call("setup", event)
	if completion_signal == "parkour_completed":
		module_instance.connect(StringName(completion_signal), Callable(self, "_on_embedded_module_completed_without_result"), CONNECT_ONE_SHOT)
	else:
		module_instance.connect(StringName(completion_signal), Callable(self, "_on_embedded_module_completed_with_result"), CONNECT_ONE_SHOT)

	_active_module_id = module_id
	_module_active = true
	_dialogue_ui.hide_dialogue()
	_narration_ui.begin_fade_for_dialogue(_verify_mode)
	_interaction_panel.visible = false
	_endpoint_panel.visible = false
	_module_host.visible = true
	_module_viewport.add_child(module_instance)
	await get_tree().process_frame
	await get_tree().process_frame

	_log_runtime("MODULE_READY id=%s source=%d root_type=%s children=%d viewport=%dx%d" % [
		module_id,
		source,
		module_instance.get_class(),
		module_instance.get_child_count(),
		MODULE_VIEW_SIZE.x,
		MODULE_VIEW_SIZE.y,
	])
	if module_id == "ForestRun" and not module_instance is Node2D:
		_record_module_failure(module_id, source, "ForestRun 根节点必须是 Node2D")
	if module_id == "LakeJump" and not module_instance is Node2D:
		_record_module_failure(module_id, source, "LakeJump 根节点必须是 Node2D")
	if module_id == "StarJar" and not module_instance is Control:
		_record_module_failure(module_id, source, "StarJar 根节点必须是 Control")
	if is_placeholder and (not module_instance.has_method("verify_contract") or not bool(module_instance.call("verify_contract"))):
		_record_module_failure(module_id, source, "LakeJump 占位页结构不完整")

	var result: Dictionary
	if _verify_mode:
		result = {"result": str(event.get("result", "verified")), "verification": "simulated_after_ready"}
	else:
		result = await embedded_module_finished
	_log_runtime("MODULE_COMPLETE id=%s source=%d kind=%s result=%s" % [
		module_id,
		source,
		"placeholder" if is_placeholder else "playable",
		JSON.stringify(result),
	])

	module_instance.queue_free()
	await get_tree().process_frame
	_module_host.visible = false
	_module_active = false
	_active_module_id = ""
	_status("[MODULE_RETURN] %s → 剧情继续" % module_id)


func _on_embedded_module_completed_without_result() -> void:
	if not _module_active:
		return
	embedded_module_finished.emit({"result": "success", "module": _active_module_id})


func _on_embedded_module_completed_with_result(value: Variant) -> void:
	if not _module_active:
		return
	var result: Dictionary = value if value is Dictionary else {"result": str(value)}
	result["module"] = _active_module_id
	embedded_module_finished.emit(result)


func _record_module_failure(module_id: String, source: int, issue: String) -> void:
	var message := "模块 %s（DOCX %d）%s" % [module_id, source, issue]
	_preflight_errors.append(message)
	_log_runtime("MODULE_ERROR id=%s source=%d issue=%s" % [module_id, source, issue])
	push_error(message)


func _run_module_skip(event: Dictionary) -> void:
	var module_id := str(event.get("id", ""))
	var result := str(event.get("result", "continue"))
	_visited_modules[module_id] = true
	_module_run_counts[module_id] = int(_module_run_counts.get(module_id, 0)) + 1
	_status("[MODULE_SKIP] %s → %s（不打开模块页面）" % [module_id, result])
	_log_runtime("MODULE_SKIP id=%s source=%s result=%s callback=immediate run=%d" % [module_id, event.get("source", 0), result, int(_module_run_counts[module_id])])
	await _brief_pause()


func _run_action(event: Dictionary) -> void:
	var action_id := str(event.get("id", ""))
	_status("[演出指令] %s" % str(event.get("status", action_id)))
	match action_id:
		"light_trigger":
			_dark_overlay.modulate.a = 0.80
			_actor_states["小凌"]["motion"] = "Idle"
		"heart_light":
			_vfx.set_mode("heart")
		"xiaoling_back_two", "xiaoling_back_lake":
			_actor_states["小凌"]["motion"] = "BackStep"
			_actor_states["小凌"]["x"] = maxf(0.05, float(_actor_states["小凌"]["x"]) - 0.08)
			await _brief_pause()
			_actor_states["小凌"]["motion"] = "Idle"
			if action_id == "xiaoling_back_two":
				await _fade_dark_overlay(0.20)
		"amai_firefly_gesture":
			_vfx.set_mode("fireflies")
		"single_firefly":
			_vfx.set_mode("single_firefly")
		"amai_walk_waypoint":
			_actor_states["阿麦"]["motion"] = "Walk"
			_actor_states["阿麦"]["x"] = 0.72
			await _brief_pause()
			_actor_states["阿麦"]["motion"] = "Idle"
		"amai_stop_idle":
			_actor_states["阿麦"]["motion"] = "Idle"
		"amai_run_entry":
			_actor_states["阿麦"]["motion"] = "Run"
			_actor_states["阿麦"]["x"] = 0.88
		"xiaoling_run_follow":
			_actor_states["小凌"]["motion"] = "Run"
		"switch_wet_states":
			_actor_states["小凌"]["state"] = "小凌2"
			_actor_states["阿麦"]["state"] = "阿麦2"
		"switch_stream_states":
			_actor_states["小凌"]["state"] = "小凌3"
			_actor_states["阿麦"]["state"] = "阿麦3"
		"lake_approach":
			_actor_states["阿麦"]["motion"] = "Walk"
			_actor_states["阿麦"]["x"] = 0.68
		"amai_stone_route":
			_actor_states["阿麦"]["motion"] = "ScriptedStoneRoute"
			_actor_states["阿麦"]["x"] = 0.52
			await _brief_pause()
			_actor_states["阿麦"]["motion"] = "Idle"
		"amai_dive":
			_actor_states["阿麦"]["motion"] = "Dive"
			_actor_states["阿麦"]["state"] = "BelowWater"
			await _camera_shake(1, 7.0)
		"cough_camera_shake":
			await _camera_shake(3, 3.5)
		"subjective_soundscape":
			_log_runtime("SOUNDSCAPE state=layered_to_mute no_external_audio_assets=true")
		"world_shake":
			# 第 364 行只负责把持续震动推入后段强度，不再启动会阻塞剧情的短震循环。
			_raise_story_shake_for_source(int(event.get("source", STORY_SHAKE_END_SOURCE - 2)), "world_shake")
	_log_runtime("ACTION id=%s actor_state=%s" % [action_id, JSON.stringify(_actor_states)])
	await _brief_pause()


func _play_transition(event: Dictionary) -> void:
	var transition_id := str(event.get("id", ""))
	var target := str(event.get("to", ""))
	_status("[TRANSITION: %s] %s" % [transition_id, event.get("status", "")])
	_log_runtime("TRANSITION_BEGIN id=%s from=%s to=%s" % [transition_id, _current_scene, target])
	var duration := 0.012 if _verify_mode else 0.72
	match transition_id:
		"EYE_OPEN":
			_set_scene(target)
			_dark_overlay.modulate.a = 1.0
			await _tween_alpha(_dark_overlay, 0.0, duration)
		"FIREFLY_GUIDE":
			_vfx.set_mode("fireflies")
			await _tween_alpha(_scene_label, 0.18, duration * 0.5)
			_set_scene(target)
			await _tween_alpha(_scene_label, 1.0, duration * 0.5)
		"WALK_CONTINUE", "FOREST_RUN_EXIT", "STREAM_WALK":
			_vfx.set_mode("motion")
			await _tween_alpha(_scene_label, 0.0, duration * 0.5)
			_set_scene(target)
			await _tween_alpha(_scene_label, 1.0, duration * 0.5)
			_vfx.set_mode("none")
		"WATERFALL_JUMP":
			_vfx.set_mode("water")
			await _tween_alpha(_dark_overlay, 0.92, duration * 0.5)
			_set_scene(target)
			await _tween_alpha(_dark_overlay, 0.0, duration * 0.5)
			_vfx.set_mode("none")
		_:
			await _tween_alpha(_dark_overlay, 1.0, duration * 0.5)
			_set_scene(target)
			await _tween_alpha(_dark_overlay, 0.0, duration * 0.5)
	_log_runtime("TRANSITION_END id=%s scene=%s" % [transition_id, _current_scene])


func _set_scene(scene_name: String) -> void:
	_current_scene = scene_name
	_visited_scenes[scene_name] = true
	_scene_label.text = scene_name
	_scene_label.modulate.a = 1.0
	_scene_subtitle.text = "剧情外壳纯文字 · 独立玩法按 DOCX 行切入"
	_log_runtime("SCENE scene=%s" % scene_name)
	_refresh_diagnostics()


func _apply_reverse_darkness() -> void:
	_movement_reverse_applied = true
	_dark_overlay.modulate.a = 0.86
	_status("[TRIGGER] 重新陷入黑暗；森林入口不复存在。仍可按 D / → 跟上阿麦。")
	_log_runtime("TRIGGER reverse_direction darkness=true forest_entrance=false")


func _fade_dark_overlay(target: float) -> void:
	var duration := 0.012 if _verify_mode else 0.55
	await _tween_alpha(_dark_overlay, target, duration)


func _camera_shake(count: int, strength: float) -> void:
	var duration := 0.001 if _verify_mode else 0.055
	var origin := position
	for i in range(count):
		position = origin + Vector2((-1.0 if i % 2 == 0 else 1.0) * strength, sin(float(i) * 2.1) * strength * 0.45)
		await get_tree().create_timer(duration).timeout
	position = origin


func _sync_story_shake_for_event(event: Dictionary) -> void:
	var source := int(event.get("source", 0))
	if source < STORY_SHAKE_START_SOURCE or source > STORY_SHAKE_END_SOURCE:
		return
	if not _story_shake_active:
		_start_story_shake(source)
	_raise_story_shake_for_source(source, "story_progress")


func _start_story_shake(source: int) -> void:
	_story_shake_active = true
	_story_shake_started = true
	_story_shake_finished = false
	_story_shake_base_position = position
	_story_shake_phase = 0.0
	_story_shake_current_strength = 0.0
	_story_shake_target_strength = STORY_SHAKE_START_STRENGTH
	_story_shake_peak_target_strength = STORY_SHAKE_START_STRENGTH
	_story_shake_last_source = 0
	_story_shake_start_count += 1
	_log_runtime("SHAKE_START contract_source=%d actual_source=%d start_strength=%.2f end_strength=%.2f curve=progressive" % [
		STORY_SHAKE_START_SOURCE,
		source,
		STORY_SHAKE_START_STRENGTH,
		STORY_SHAKE_END_STRENGTH,
	])


func _raise_story_shake_for_source(source: int, reason: String) -> void:
	if not _story_shake_active:
		return
	var clamped_source := clampi(source, STORY_SHAKE_START_SOURCE, STORY_SHAKE_END_SOURCE)
	if clamped_source < _story_shake_last_source:
		return
	var progress := clampf(
		float(clamped_source - STORY_SHAKE_START_SOURCE) / float(STORY_SHAKE_PEAK_SOURCE - STORY_SHAKE_START_SOURCE),
		0.0,
		1.0
	)
	var curved_progress := pow(progress, 1.12)
	var next_strength := lerpf(STORY_SHAKE_START_STRENGTH, STORY_SHAKE_END_STRENGTH, curved_progress)
	_story_shake_target_strength = maxf(_story_shake_target_strength, next_strength)
	_story_shake_peak_target_strength = maxf(_story_shake_peak_target_strength, _story_shake_target_strength)
	if clamped_source != _story_shake_last_source:
		_story_shake_last_source = clamped_source
		_log_runtime("SHAKE_LEVEL source=%d progress=%.3f target_strength=%.2f reason=%s" % [
			clamped_source,
			progress,
			_story_shake_target_strength,
			reason,
		])


func _update_story_shake(delta: float) -> void:
	if not _story_shake_active:
		return
	if _dev_jump_overlay != null and _dev_jump_overlay.visible:
		position = _story_shake_base_position
		return
	_story_shake_phase += delta
	var response_speed := 2.4 + _story_shake_target_strength * 0.42
	_story_shake_current_strength = move_toward(
		_story_shake_current_strength,
		_story_shake_target_strength,
		delta * response_speed
	)
	var normalized_strength := clampf(_story_shake_current_strength / STORY_SHAKE_END_STRENGTH, 0.0, 1.0)
	var frequency := lerpf(8.5, 15.0, normalized_strength)
	var x_wave := sin(_story_shake_phase * frequency) * 0.64 + sin(_story_shake_phase * frequency * 2.17 + 0.8) * 0.36
	var y_wave := cos(_story_shake_phase * frequency * 0.91 + 0.35) * 0.62 + sin(_story_shake_phase * frequency * 1.71) * 0.38
	position = _story_shake_base_position + Vector2(x_wave, y_wave) * _story_shake_current_strength


func _stop_story_shake(reason: String) -> void:
	if not _story_shake_active:
		return
	_story_shake_active = false
	_story_shake_finished = true
	_story_shake_stop_count += 1
	position = _story_shake_base_position
	_log_runtime("SHAKE_STOP source=%d peak_target_strength=%.2f reason=%s reset_position=%s" % [
		_story_shake_last_source,
		_story_shake_peak_target_strength,
		reason,
		position == _story_shake_base_position,
	])


func _tween_alpha(node: CanvasItem, target: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", target, maxf(duration, 0.001))
	await tween.finished


func _brief_pause() -> void:
	if _verify_mode:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(0.22).timeout


func _on_action_button_pressed() -> void:
	if not _awaiting_action_button:
		return
	_awaiting_action_button = false
	interaction_completed.emit()


func _on_light_mouse_entered() -> void:
	_light_hovered = true


func _on_light_mouse_exited() -> void:
	_light_hovered = false


func _jump_to_label(label_id: String) -> void:
	if not _labels.has(label_id):
		_preflight_errors.append("跳转目标不存在：%s" % label_id)
		_log_runtime("FATAL missing_label=%s" % label_id)
		return
	_event_index = int(_labels[label_id]) + 1
	_log_runtime("GOTO label=%s next_index=%d" % [label_id, _event_index])


func _build_label_index() -> void:
	_labels.clear()
	for i in range(_events.size()):
		var event := _events[i]
		if str(event.get("type", "")) == "label":
			_labels[str(event.get("id", ""))] = i


func _status(text: String) -> void:
	_status_label.text = "演出状态：%s" % text
	_refresh_diagnostics()


func _show_fatal(text: String) -> void:
	_stop_story_shake("fatal")
	_dialogue_ui.hide_dialogue()
	_narration_ui.begin_fade_for_dialogue(true)
	_interaction_panel.visible = true
	_interaction_prompt.text = "运行错误\n%s" % text
	_progress.visible = false
	_light_button.visible = false
	_action_button.visible = false
	_status(text)


func _complete_story() -> void:
	_stop_story_shake("endpoint")
	_dialogue_ui.hide_dialogue()
	_narration_ui.begin_fade_for_dialogue(_verify_mode)
	_interaction_panel.visible = false
	_endpoint_panel.visible = true
	_vfx.set_mode("none")
	_refresh_diagnostics()
	_log_runtime("LAYOUT_AUDIT narration_samples=%d narration_violations=%d max_center_error=%.3f max_width_overflow=%.3f dialogue_samples=%d psychology_samples=%d choice_samples=%d choice_violations=%d choice_max_center_error=%.3f psychology_in_dialogue=true psychology_parentheses=true dialogue_left=%s dialogue_body_top=%s continue_button_centered=%s choices_centered=%s shortcut_hint=%s narration_direct_reveal=%s dialogue_progressive_reveal=%s" % [
		_narration_ui.get_layout_sample_count(),
		_narration_ui.get_layout_violation_count(),
		_narration_ui.get_max_center_error(),
		_narration_ui.get_max_width_overflow(),
		_dialogue_ui.get_presented_line_count(),
		_psychology_lines_seen,
		_dialogue_ui.get_choice_layout_sample_count(),
		_dialogue_ui.get_choice_layout_violation_count(),
		_dialogue_ui.get_choice_layout_max_center_error(),
		_dialogue_ui.is_text_left_aligned(),
		_dialogue_ui.is_body_compact_at_top(),
		_dialogue_ui.is_continue_button_centered(),
		_dialogue_ui.get_choice_layout_violation_count() == 0,
		_advance_hint_label != null and _advance_hint_label.text == "按 Enter / Space 继续",
		_narration_ui.uses_direct_reveal(),
		_dialogue_ui.uses_progressive_reveal(),
	])
	var runtime_errors := _validate_dev_jump_completion() if _dev_jump_active else _validate_runtime_completion()
	if _verify_mode:
		_finish_verification(runtime_errors.is_empty(), runtime_errors)
	else:
		if runtime_errors.is_empty():
			if _dev_jump_active:
				_log_runtime("COMPLETE status=ok mode=dev_jump requested_source=%d actual_source=%d" % [
					_dev_jump_requested_source,
					_dev_jump_actual_source,
				])
			else:
				_log_runtime("COMPLETE status=ok")
		else:
			for issue in runtime_errors:
				_log_runtime("COMPLETE_ERROR %s" % issue)


func _validate_contract() -> PackedStringArray:
	var errors := PackedStringArray()
	var seen_scenes: Dictionary = {}
	var seen_modules: Dictionary = {}
	var module_bindings: Dictionary = {}
	var endpoint_count := 0
	var line_count := 0
	var narration_count := 0
	var dialogue_count := 0
	var psychology_count := 0
	var psychology_sources: Dictionary = {}
	var shake_start_line_found := false
	var world_shake_cue_found := false
	for event in _events:
		var kind := str(event.get("type", ""))
		var source := int(event.get("source", 0))
		if kind == "line" and source == STORY_SHAKE_START_SOURCE and str(event.get("text", "")) == "我们以前是不是见过？":
			shake_start_line_found = true
		if kind == "effect" and source == 364 and str(event.get("id", "")) == "world_shake":
			world_shake_cue_found = true
		if kind == "scene":
			seen_scenes[str(event.get("name", ""))] = true
		elif kind == "transition":
			seen_scenes[str(event.get("to", ""))] = true
		elif kind in ["module", "module_placeholder", "module_skip"]:
			var module_id := str(event.get("id", ""))
			seen_modules[module_id] = true
			var bindings: Array = module_bindings.get(module_id, [])
			bindings.append(event)
			module_bindings[module_id] = bindings
		elif kind == "endpoint":
			endpoint_count += 1
		elif kind == "line":
			line_count += 1
			var channel := _resolve_line_channel(event)
			if channel == "NARRATION":
				narration_count += 1
			else:
				dialogue_count += 1
			if _is_psychology_event(event):
				psychology_count += 1
				psychology_sources[int(event.get("source", 0))] = true
				if channel != "DIALOGUE":
					errors.append("心理文字被错误映射到旁白区域：%s" % event.get("source", 0))
				var formatted_psychology := _format_psychology_text(str(event.get("speaker", "")), str(event.get("text", "")))
				if not formatted_psychology.begins_with("（") or not formatted_psychology.ends_with("）"):
					errors.append("心理文字未使用全角括号：%s" % event.get("source", 0))
		if kind == "choice":
			var routes: Dictionary = event.get("routes", {})
			for target in routes.values():
				if not _labels.has(str(target)):
					errors.append("选择跳转目标不存在：%s" % target)
		if kind == "goto" and not _labels.has(str(event.get("target", ""))):
			errors.append("goto 目标不存在：%s" % event.get("target", ""))
	for scene_name in StoryData.required_scene_names():
		if not seen_scenes.has(scene_name):
			errors.append("缺少资源场景：%s" % scene_name)
	for module_id in StoryData.required_module_hooks():
		if not seen_modules.has(module_id):
			errors.append("缺少模块 hook：%s" % module_id)
	for module_id in EXPECTED_MODULE_BINDINGS:
		var expected: Dictionary = EXPECTED_MODULE_BINDINGS[module_id]
		var bindings: Array = module_bindings.get(module_id, [])
		if bindings.size() != 1:
			errors.append("模块 %s 应且仅应绑定一次，实际为%d" % [module_id, bindings.size()])
			continue
		var binding: Dictionary = bindings[0]
		if int(binding.get("source", 0)) != int(expected.get("source", 0)):
			errors.append("模块 %s DOCX 插入行错误：%s/%s" % [module_id, binding.get("source", 0), expected.get("source", 0)])
		if str(binding.get("type", "")) != str(expected.get("type", "")):
			errors.append("模块 %s 事件类型错误：%s/%s" % [module_id, binding.get("type", ""), expected.get("type", "")])
		if str(binding.get("scene", "")) != str(expected.get("scene", "")):
			errors.append("模块 %s 场景绑定错误：%s" % [module_id, binding.get("scene", "")])
		if str(binding.get("completion_signal", "")) != str(expected.get("signal", "")):
			errors.append("模块 %s 完成信号绑定错误：%s" % [module_id, binding.get("completion_signal", "")])
		var scene_path := str(binding.get("scene", ""))
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			errors.append("模块 %s 场景资源不存在：%s" % [module_id, scene_path])
	if endpoint_count != 1:
		errors.append("ENDPOINT 数量应为1，实际为%d" % endpoint_count)
	if line_count < 140:
		errors.append("玩家可见文本数量异常：%d" % line_count)
	if narration_count < 61:
		errors.append("NARRATION 映射数量异常：%d" % narration_count)
	if dialogue_count < 60:
		errors.append("DIALOGUE 映射数量异常：%d" % dialogue_count)
	if psychology_count != 5:
		errors.append("心理文字数量应为5，实际为%d" % psychology_count)
	for psychology_source in [54, 72, 81, 82, 134]:
		if not psychology_sources.has(psychology_source):
			errors.append("缺少心理文字来源行：%d" % psychology_source)
	if not shake_start_line_found:
		errors.append("渐强晃动起点未绑定 DOCX 第 354 行目标对白")
	if not world_shake_cue_found:
		errors.append("渐强晃动缺少 DOCX 第 364 行世界震动演出指令")
	if STORY_SHAKE_START_SOURCE >= STORY_SHAKE_PEAK_SOURCE or STORY_SHAKE_PEAK_SOURCE >= STORY_SHAKE_END_SOURCE:
		errors.append("渐强晃动来源行区间配置无效")
	if STORY_SHAKE_START_STRENGTH <= 0.0 or STORY_SHAKE_END_STRENGTH <= STORY_SHAKE_START_STRENGTH:
		errors.append("渐强晃动强度配置无效")
	if _narration_ui == null or _dialogue_ui == null or _narration_ui == _dialogue_ui:
		errors.append("NARRATION_UI 与 DIALOGUE_UI 未建立为独立组件")
	else:
		if _narration_ui.name != "NARRATION_UI" or _dialogue_ui.name != "DIALOGUE_UI":
			errors.append("UI 组件命名不符合独立分区契约")
		if _narration_ui is PanelContainer:
			errors.append("NARRATION_UI 不得使用传统矩形面板")
		if not is_equal_approx(_narration_ui.anchor_top, 0.02) or not is_equal_approx(_narration_ui.anchor_bottom, 0.20):
			errors.append("NARRATION_UI 未整体上移到顶部2%–20%区域")
		if _dialogue_ui.anchor_top < 0.90:
			errors.append("DIALOGUE_UI 未固定在画面底部")
		if not _narration_ui.is_horizontally_centered():
			errors.append("NARRATION_UI 未按画面中轴居中")
		if not _narration_ui.uses_direct_reveal():
			errors.append("NARRATION_UI 未启用整句直接淡入")
		if not _dialogue_ui.is_panel_centered():
			errors.append("DIALOGUE_UI 面板未按画面中轴居中")
		if not _dialogue_ui.is_text_left_aligned():
			errors.append("DIALOGUE_UI 角色名与正文未左对齐")
		if not _dialogue_ui.is_body_compact_at_top():
			errors.append("DIALOGUE_UI 正文未紧邻角色名顶部显示")
		if not _dialogue_ui.is_continue_button_centered():
			errors.append("DIALOGUE_UI 继续按钮未居中或按钮文案不简洁")
		if not _dialogue_ui.uses_progressive_reveal():
			errors.append("DIALOGUE_UI 未启用逐字淡显")
	if _advance_hint_label == null or _advance_hint_label.text != "按 Enter / Space 继续":
		errors.append("左上角键盘推进提示缺失")
	elif _advance_hint_label.anchor_left != 0.0 or _advance_hint_label.anchor_top != 0.0:
		errors.append("键盘推进提示未固定在画面左上角")
	if _dev_jump_overlay == null or _dev_jump_panel == null or _dev_jump_input == null or _dev_jump_button == null:
		errors.append("F4 DOCX 行跳转开发面板不完整")
	elif _dev_jump_overlay.visible:
		errors.append("F4 DOCX 行跳转开发面板不应默认显示")
	if _module_host == null or _module_viewport_container == null or _module_viewport == null:
		errors.append("独立模块宿主未完整建立")
	elif _module_host.visible or _module_viewport.get_child_count() != 0:
		errors.append("模块宿主启动时应保持隐藏且为空")
	var source_bounds := _docx_source_bounds()
	if source_bounds != Vector2i(29, 366):
		errors.append("DOCX 来源行范围异常：%s" % source_bounds)
	var exact_jump := _resolve_docx_source_line(83)
	if exact_jump.is_empty() or int(exact_jump.get("source", 0)) != 83 or not bool(exact_jump.get("exact", false)):
		errors.append("DOCX 精确行跳转解析失败：83")
	var gap_jump := _resolve_docx_source_line(60)
	if gap_jump.is_empty() or int(gap_jump.get("source", 0)) != 61 or bool(gap_jump.get("exact", true)):
		errors.append("DOCX 空白行未映射至下一事件：60 -> 61")
	var first_jump := _resolve_docx_source_line(1)
	if first_jump.is_empty() or int(first_jump.get("source", 0)) != 29:
		errors.append("DOCX 下界之前的行未映射到首个事件")
	if not _resolve_docx_source_line(367).is_empty():
		errors.append("DOCX 上界之后的行不应产生跳转目标")
	for source_line in range(source_bounds.x, source_bounds.y + 1):
		if _resolve_docx_source_line(source_line).is_empty():
			errors.append("DOCX 行无法解析至当前或下一事件：%d" % source_line)
			break
	if _scene_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER or _scene_subtitle.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		errors.append("场景标题未按画面中轴居中")
	if _interaction_prompt.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
		errors.append("交互提示未按画面中轴居中")
	if _light_button.size_flags_horizontal != Control.SIZE_SHRINK_CENTER or _action_button.size_flags_horizontal != Control.SIZE_SHRINK_CENTER:
		errors.append("交互按钮未按画面中轴居中")
	if theme == null or theme.default_font != _primary_font:
		errors.append("全局字体未绑定 Times New Roman")
	if _primary_font == null or _primary_font.font_names.is_empty() or _primary_font.font_names[0] != FONT_PRIMARY_NAME:
		errors.append("Times New Roman 主字体配置缺失")
	elif not _primary_font.has_char("A".unicode_at(0)):
		errors.append("Times New Roman 无法渲染拉丁字符")
	if _cjk_fallback_font == null or _cjk_fallback_font.font_names.is_empty() or _cjk_fallback_font.font_names[0] != FONT_CJK_FALLBACK_NAME:
		errors.append("中文宋体回退配置缺失")
	elif not _cjk_fallback_font.has_char("中".unicode_at(0)):
		errors.append("中文宋体回退无法渲染中文")
	for image_path in _find_forbidden_images("res://"):
		errors.append("剧情外壳发现未授权图片资产：%s" % image_path)
	for node_name in _find_forbidden_visual_nodes(self):
		errors.append("剧情外壳发现未授权人物/图片节点：%s" % node_name)
	return errors


func _validate_runtime_completion() -> PackedStringArray:
	var errors := _preflight_errors.duplicate()
	if not _endpoint_reached:
		errors.append("未到达 ENDPOINT")
	for scene_name in StoryData.required_scene_names():
		if not _visited_scenes.has(scene_name):
			errors.append("全流程未访问场景：%s" % scene_name)
	for module_id in StoryData.required_module_hooks():
		if not _visited_modules.has(module_id):
			errors.append("全流程未经过模块 hook：%s" % module_id)
		elif int(_module_run_counts.get(module_id, 0)) != 1:
			errors.append("全流程模块 %s 执行次数异常：%d/1" % [module_id, int(_module_run_counts.get(module_id, 0))])
	for required_source in [54, 122, 193, 238, 308, 360, 366]:
		if not _visited_sources.has(required_source):
			errors.append("全流程未执行 DOCX 行：%d" % required_source)
	if _module_active or (_module_host != null and _module_host.visible):
		errors.append("全流程结束时模块宿主仍处于活动状态")
	if _module_viewport != null and _module_viewport.get_child_count() != 0:
		errors.append("全流程结束时模块实例未释放：%d" % _module_viewport.get_child_count())
	if _narration_lines_seen < 61:
		errors.append("全流程 NARRATION_UI 覆盖不足：%d" % _narration_lines_seen)
	if _dialogue_lines_seen < 60:
		errors.append("全流程 DIALOGUE_UI 覆盖不足：%d" % _dialogue_lines_seen)
	if _psychology_lines_seen != 5:
		errors.append("全流程心理文字进入 DIALOGUE_UI 数量异常：%d/5" % _psychology_lines_seen)
	if _narration_ui.get_max_observed_count() > 3:
		errors.append("NARRATION_UI 队列峰值超过3：%d" % _narration_ui.get_max_observed_count())
	if not _narration_ui.is_queue_idle():
		errors.append("NARRATION_UI 在终点仍有未完成队列")
	if not _dialogue_ui.is_queue_idle():
		errors.append("DIALOGUE_UI 在终点仍有未完成队列")
	if not _narration_ui.is_horizontally_centered():
		errors.append("运行结束 NARRATION_UI 居中约束失效")
	if _narration_ui.get_layout_sample_count() != _narration_lines_seen:
		errors.append("NARRATION_UI 布局审计数量不完整：%d/%d" % [_narration_ui.get_layout_sample_count(), _narration_lines_seen])
	if _narration_ui.get_layout_violation_count() > 0:
		errors.append("NARRATION_UI 存在偏心或溢出：%d" % _narration_ui.get_layout_violation_count())
	if _dialogue_ui.get_presented_line_count() != _dialogue_lines_seen:
		errors.append("DIALOGUE_UI 布局审计数量不完整：%d/%d" % [_dialogue_ui.get_presented_line_count(), _dialogue_lines_seen])
	if _dialogue_ui.get_choice_layout_sample_count() != 2:
		errors.append("DIALOGUE_UI 选项布局审计数量不完整：%d/2" % _dialogue_ui.get_choice_layout_sample_count())
	if _dialogue_ui.get_choice_layout_violation_count() > 0:
		errors.append("DIALOGUE_UI 存在选项组偏心：%d" % _dialogue_ui.get_choice_layout_violation_count())
	if not _dialogue_ui.is_panel_centered():
		errors.append("运行结束 DIALOGUE_UI 面板居中约束失效")
	if not _dialogue_ui.is_text_left_aligned():
		errors.append("运行结束 DIALOGUE_UI 左对齐约束失效")
	if not _dialogue_ui.is_body_compact_at_top():
		errors.append("运行结束 DIALOGUE_UI 正文顶部布局失效")
	if not _dialogue_ui.is_continue_button_centered():
		errors.append("运行结束 DIALOGUE_UI 继续按钮布局失效")
	errors.append_array(_validate_story_shake_completion())
	for image_path in _find_forbidden_images("res://"):
		errors.append("运行结束剧情外壳发现未授权图片资产：%s" % image_path)
	for node_name in _find_forbidden_visual_nodes(self):
		errors.append("运行结束剧情外壳发现未授权人物/图片节点：%s" % node_name)
	return errors


func _validate_dev_jump_completion() -> PackedStringArray:
	var errors := _preflight_errors.duplicate()
	if not _endpoint_reached:
		errors.append("开发跳转流程未到达 ENDPOINT")
	if not _narration_ui.is_queue_idle():
		errors.append("开发跳转结束时 NARRATION_UI 队列未清空")
	if not _dialogue_ui.is_queue_idle():
		errors.append("开发跳转结束时 DIALOGUE_UI 队列未清空")
	if _narration_ui.get_layout_violation_count() > 0:
		errors.append("开发跳转后 NARRATION_UI 存在偏心或溢出：%d" % _narration_ui.get_layout_violation_count())
	if _dialogue_ui.get_choice_layout_violation_count() > 0:
		errors.append("开发跳转后 DIALOGUE_UI 存在选项组偏心：%d" % _dialogue_ui.get_choice_layout_violation_count())
	errors.append_array(_validate_story_shake_completion())
	for image_path in _find_forbidden_images("res://"):
		errors.append("开发跳转结束剧情外壳发现未授权图片资产：%s" % image_path)
	for node_name in _find_forbidden_visual_nodes(self):
		errors.append("开发跳转结束剧情外壳发现未授权人物/图片节点：%s" % node_name)
	return errors


func _validate_story_shake_completion() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _story_shake_started or _story_shake_start_count != 1:
		errors.append("渐强晃动应启动一次，实际启动 %d 次" % _story_shake_start_count)
	if _story_shake_last_source != STORY_SHAKE_END_SOURCE:
		errors.append("渐强晃动未保持至终点行：%d/%d" % [_story_shake_last_source, STORY_SHAKE_END_SOURCE])
	if _story_shake_peak_target_strength < STORY_SHAKE_END_STRENGTH - 0.01:
		errors.append("渐强晃动未达到结尾强度：%.2f/%.2f" % [_story_shake_peak_target_strength, STORY_SHAKE_END_STRENGTH])
	if _story_shake_active:
		errors.append("渐强晃动在终点后仍处于活动状态")
	if not _story_shake_finished or _story_shake_stop_count != 1:
		errors.append("渐强晃动终点复位次数异常：%d" % _story_shake_stop_count)
	if position != _story_shake_base_position:
		errors.append("渐强晃动终点后屏幕位置未复位")
	return errors


func _find_forbidden_images(path: String) -> PackedStringArray:
	var found := PackedStringArray()
	if _is_allowed_module_image_path(path):
		return found
	var dir := DirAccess.open(path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry == ".godot":
			entry = dir.get_next()
			continue
		var child_path := path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_find_forbidden_images(child_path))
		elif entry.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg", "bmp", "gif"]:
			found.append(child_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _is_allowed_module_image_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	for allowed_root in ALLOWED_MODULE_IMAGE_ROOTS:
		var root := str(allowed_root)
		if normalized == root.trim_suffix("/") or normalized.begins_with(root):
			return true
	return false


func _find_forbidden_visual_nodes(node: Node) -> PackedStringArray:
	var found := PackedStringArray()
	for child in node.get_children():
		if child == _module_host:
			continue
		if child is Sprite2D or child is AnimatedSprite2D or child is TextureRect or child is CharacterBody2D:
			found.append("%s (%s)" % [child.get_path(), child.get_class()])
		found.append_array(_find_forbidden_visual_nodes(child))
	return found


func _initialize_logs(preserve_existing := false) -> void:
	var log_dir := ProjectSettings.globalize_path("user://logs")
	DirAccess.make_dir_recursive_absolute(log_dir)
	if preserve_existing and FileAccess.file_exists(RUNTIME_LOG_PATH):
		_append_log(RUNTIME_LOG_PATH, "# Developer DOCX jump reload · %s" % Time.get_datetime_string_from_system())
	else:
		_reset_log(RUNTIME_LOG_PATH, "# Dark Forest runtime log")
	if preserve_existing and FileAccess.file_exists(TRACE_LOG_PATH):
		_append_log(TRACE_LOG_PATH, "# Developer DOCX jump reload · %s" % Time.get_datetime_string_from_system())
	else:
		_reset_log(TRACE_LOG_PATH, "# Dark Forest step trace")
	_log_runtime("LOG_PATH runtime=%s" % ProjectSettings.globalize_path(RUNTIME_LOG_PATH))
	_log_runtime("LOG_PATH trace=%s" % ProjectSettings.globalize_path(TRACE_LOG_PATH))
	_log_runtime("LOG_PATH engine=%s" % ProjectSettings.globalize_path(ENGINE_LOG_PATH))
	_log_runtime("LOG_MODE preserve_existing=%s" % preserve_existing)


func _reset_log(path: String, title: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot create log: %s" % path)
		return
	file.store_line(title)
	file.store_line("session_started=%s" % Time.get_datetime_string_from_system())
	file.close()


func _append_log(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot append log: %s" % path)
		return
	file.seek_end()
	file.store_line(text)
	file.close()


func _log_runtime(text: String) -> void:
	_append_log(RUNTIME_LOG_PATH, "%s | %s" % [Time.get_time_string_from_system(), text])


func _trace_current_step(phase: String) -> void:
	var source := int(_current_event.get("source", 0))
	if source > 0:
		_visited_sources[source] = true
	var elapsed := Time.get_ticks_msec() - _step_started_msec
	var event_id := str(_current_event.get("id", _current_event.get("name", _current_event.get("type", ""))))
	var channel := _resolve_line_channel(_current_event) if str(_current_event.get("type", "")) == "line" else "-"
	var line := "%s | phase=%s | step=%04d/%04d | source=%d | type=%s | channel=%s | id=%s | scene=%s | elapsed_ms=%d | narration_visible=%d | shake_active=%s | shake_target=%.2f | actors=%s" % [
		Time.get_time_string_from_system(),
		phase,
		_current_event_index + 1,
		_events.size(),
		source,
		_current_event.get("type", ""),
		channel,
		event_id,
		_current_scene,
		elapsed,
		_narration_ui.get_visible_entry_count(),
		_story_shake_active,
		_story_shake_target_strength,
		JSON.stringify(_actor_states),
	]
	_append_log(TRACE_LOG_PATH, line)
	_source_label.text = "DOCX 行 %d · 步骤 %d / %d · %s" % [source, _current_event_index + 1, _events.size(), event_id]
	_refresh_diagnostics()


func _refresh_diagnostics() -> void:
	if _diagnostic_label == null:
		return
	var event_id := str(_current_event.get("id", _current_event.get("name", "等待启动")))
	var channel := _resolve_line_channel(_current_event) if str(_current_event.get("type", "")) == "line" else "-"
	var dev_jump_status := "当前会话未使用跳转"
	if _dev_jump_active:
		dev_jump_status = "请求第 %d 行 → 实际第 %d 行" % [_dev_jump_requested_source, _dev_jump_actual_source]
	_diagnostic_label.text = "F3 诊断面板 · F4 DOCX 行跳转\n\n当前步骤：%d / %d\nDOCX 来源行：%s\n事件：%s / %s\n文本通道：%s\n场景：%s\n开发跳转：%s\n当前独立玩法：%s\n玩法执行计数：%s\n旁白队列：%d（峰值 %d）\n对白队列峰值：%d\n持续晃动：%s（目标强度 %.2f）\n\n剧情外壳人物状态：\n%s\n\n运行日志：\n%s\n\n逐步检测日志：\n%s\n\n引擎日志：\n%s" % [
		_current_event_index + 1,
		_events.size(),
		_current_event.get("source", 0),
		_current_event.get("type", ""),
		event_id,
		channel,
		_current_scene,
		dev_jump_status,
		_active_module_id if _module_active else "-",
		JSON.stringify(_module_run_counts),
		_narration_ui.get_visible_entry_count() if _narration_ui != null else 0,
		_narration_ui.get_max_observed_count() if _narration_ui != null else 0,
		_dialogue_ui.get_max_queue_depth() if _dialogue_ui != null else 0,
		_story_shake_active,
		_story_shake_target_strength,
		JSON.stringify(_actor_states),
		ProjectSettings.globalize_path(RUNTIME_LOG_PATH),
		ProjectSettings.globalize_path(TRACE_LOG_PATH),
		ProjectSettings.globalize_path(ENGINE_LOG_PATH),
	]


func _finish_verification(success: bool, issues: PackedStringArray) -> void:
	if success:
		var message := "FULL_FLOW_PASS events=%d scenes=%d modules=%d endpoint=%s narration_lines=%d dialogue_lines=%d psychology_lines=%d narration_queue_max=%d dialogue_queue_max=%d narration_layout_samples=%d dialogue_layout_samples=%d choice_layout_samples=%d split_ui=true narration_top_2_20=true narration_centered=true narration_direct_reveal=true dialogue_progressive_reveal=true psychology_in_dialogue=true psychology_parentheses=true dialogue_left_aligned=true dialogue_body_top=true continue_button_centered=true choices_centered=true shortcut_hint=true shake_start_source=354 shake_peak_source=365 shake_end_source=366 shake_progressive=true shake_reset=true dev_docx_jump=true docx_jump_all_sources_resolvable=true dev_jump_logs_preserved=true font=Times_New_Roman cjk_fallback=SimSun narrative_shell_text_only=true ForestRun_source=122 ForestRun_ready=true LakeJump_source=193 LakeJump_ready=true LakeJump_placeholder=false StarJar_source=238 StarJar_ready=true module_subviewport_isolated=true" % [
			_events.size(),
			_visited_scenes.size(),
			_visited_modules.size(),
			_endpoint_reached,
			_narration_lines_seen,
			_dialogue_lines_seen,
			_psychology_lines_seen,
			_narration_ui.get_max_observed_count(),
			_dialogue_ui.get_max_queue_depth(),
			_narration_ui.get_layout_sample_count(),
			_dialogue_ui.get_presented_line_count(),
			_dialogue_ui.get_choice_layout_sample_count(),
		]
		print(message)
		_log_runtime(message)
		get_tree().quit(0)
	else:
		for issue in issues:
			print("FULL_FLOW_FAIL %s" % issue)
			_log_runtime("FULL_FLOW_FAIL %s" % issue)
		get_tree().quit(1)
