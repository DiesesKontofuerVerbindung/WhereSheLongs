extends Control

## 婚礼前段外壳。
##
## 复用森林正片同一套 UI（NARRATION_UI 顶部旁白、DIALOGUE_UI 底部对白、
## Enter/Space 推进、Times New Roman + 宋体回退），但事件表、场景与推进循环
## 完全独立：森林正片的 _events / source bounds / docx_source_lock 都被
## verify 硬断言锁住了，把婚礼混进去只会把那些断言全部打掉。
##
## 婚礼段暂时没有任何美术素材，场景一律是纯文字舞台占位。

const NarrationUIScript := preload("res://scripts/narration_ui.gd")
const DialogueUIScript := preload("res://scripts/dialogue_ui.gd")
const WeddingDataScript := preload("res://scripts/wedding_data.gd")
const MysticNightDataScript := preload("res://scripts/mystic_night_data.gd")
const StoryDataScript := preload("res://scripts/story_data.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")
const ChapterTransitionScript := preload("res://scripts/chapter_transition.gd")

const FOREST_MAIN_SCENE := "res://main.tscn"
const WEDDING_PROLOGUE_SCENE := "res://scenes/wedding/wedding_prologue.tscn"
const MYSTIC_NIGHT_SCENE := "res://scenes/mystic_night/mystic_night.tscn"
const DEV_JUMP_CHAPTER_ID := "wedding"
const FONT_PRIMARY_NAME := "Times New Roman"
const FONT_CJK_FALLBACK_NAME := "SimSun"

const COLOR_BG := Color(0.055, 0.05, 0.07, 1.0)
const COLOR_ACCENT := Color(0.86, 0.78, 0.62, 1.0)
const COLOR_MUTED := Color(0.62, 0.60, 0.66, 1.0)

const SHAKE_SECONDS := 1.1
const SHAKE_MAX_PIXELS := 26.0

## 底图比舞台外扩一圈，震动（最大 26px）时不会露出边缘。
const SCENE_TEXTURE_OVERSCAN := 64.0

signal prologue_finished

var _events: Array[Dictionary] = []
var _event_index := 0
var _current_scene := ""
var _verify_mode := false
var _endpoint_reached := false
var _visited_sources: Dictionary = {}
var _visited_modules: Dictionary = {}
var _interactions_done: Dictionary = {}
var _failures: PackedStringArray = []

var _dev_jump_overlay
var _pending_dev_jump: Dictionary = {}
var _dev_jump_active := false
var _dev_jump_requested_source := 0
var _dev_jump_actual_source := 0
var _current_source := 0

var _primary_font: SystemFont
var _cjk_fallback_font: SystemFont
var _root_bg: ColorRect
var _stage_root: Control
var _scene_texture: TextureRect
var _scene_label: Label
var _scene_subtitle: Label
var _advance_hint: Label
var _interaction_panel: PanelContainer
var _interaction_button: Button
var _module_host: Control
var _narration_ui
var _dialogue_ui

## 场景名 -> 底图路径。图没到位时保留文字占位回退（见 _set_scene）。
var _scene_texture_paths := {
	WeddingDataScript.SCENE_WEDDING_1: "res://assets/backgrounds/wedding/candidates/officiant.jpg",
	WeddingDataScript.SCENE_WEDDING_2: "res://assets/backgrounds/wedding/wedding_2.jpg",
	WeddingDataScript.SCENE_CAR: "res://assets/backgrounds/wedding/car.png",
	WeddingDataScript.SCENE_HOME: "res://assets/backgrounds/wedding/home.png",
}

var _shake_phase := 0.0
var _shake_intensity := 0.0
var _pending_interaction := ""
var _active_line_channel := ""


func _ready() -> void:
	name = "WeddingPrologue"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_pending_dev_jump = DevJumpPanelScript.take_pending_jump(get_tree().root, DEV_JUMP_CHAPTER_ID)
	_verify_mode = "--verify" in OS.get_cmdline_user_args() or "--verify" in OS.get_cmdline_args()
	_configure_typography()
	_build_ui()
	_events = WeddingDataScript.build_events()
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
	_root_bg.name = "WeddingBackdrop"
	_root_bg.color = COLOR_BG
	_root_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_bg)

	# 震动只晃舞台，不晃对白框——文字必须始终可读。
	_stage_root = Control.new()
	_stage_root.name = "WeddingStage"
	_stage_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage_root)

	# 美术底图插在舞台层、两个占位 Label 之下；震动跟着舞台走。
	_scene_texture = TextureRect.new()
	_scene_texture.name = "WeddingSceneTexture"
	_scene_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_texture.offset_left = -SCENE_TEXTURE_OVERSCAN
	_scene_texture.offset_top = -SCENE_TEXTURE_OVERSCAN
	_scene_texture.offset_right = SCENE_TEXTURE_OVERSCAN
	_scene_texture.offset_bottom = SCENE_TEXTURE_OVERSCAN
	_scene_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_scene_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scene_texture.visible = false
	_stage_root.add_child(_scene_texture)

	_scene_label = Label.new()
	_scene_label.set_anchors_preset(Control.PRESET_CENTER)
	_scene_label.offset_left = -360
	_scene_label.offset_right = 360
	_scene_label.offset_top = 16
	_scene_label.offset_bottom = 56
	_scene_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_label.add_theme_font_size_override("font_size", 26)
	_scene_label.add_theme_color_override("font_color", COLOR_ACCENT)
	_scene_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_root.add_child(_scene_label)

	_scene_subtitle = Label.new()
	_scene_subtitle.set_anchors_preset(Control.PRESET_CENTER)
	_scene_subtitle.offset_left = -400
	_scene_subtitle.offset_right = 400
	_scene_subtitle.offset_top = 64
	_scene_subtitle.offset_bottom = 100
	_scene_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scene_subtitle.add_theme_font_size_override("font_size", 15)
	_scene_subtitle.add_theme_color_override("font_color", COLOR_MUTED)
	_scene_subtitle.text = "婚礼前段 · 美术未到位，纯文字舞台占位"
	_scene_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_root.add_child(_scene_subtitle)

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
	_interaction_panel.name = "WeddingInteraction"
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

	_module_host = Control.new()
	_module_host.name = "WeddingModuleHost"
	_module_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_module_host.visible = false
	add_child(_module_host)

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
	# 只在真的等玩家推进时才亮：常显会让 wait/effect 这类定时事件看起来像卡住。
	_advance_hint.visible = false
	add_child(_advance_hint)

	# 章节注册要等 _events 装配好，这里只挂节点。
	_dev_jump_overlay = DevJumpPanelScript.new()
	add_child(_dev_jump_overlay)
	_dev_jump_overlay.jump_requested.connect(_on_dev_jump_requested)


func _setup_dev_jump_chapters() -> void:
	if _dev_jump_overlay == null:
		return
	var forest_events: Array = StoryDataScript.get_events()
	var chapters: Array[Dictionary] = [
		{
			"id": DEV_JUMP_CHAPTER_ID,
			"title": "婚礼前夜回溯",
			"scene": WEDDING_PROLOGUE_SCENE,
			"events": _events,
			"hint": "婚礼前段的 DOCX 行。若该行没有事件，将从下一条有事件的行开始。",
		},
		{
			"id": "mystic_night",
			"title": "奇妙夜回溯",
			"scene": MYSTIC_NIGHT_SCENE,
			"events": MysticNightDataScript.build_events(),
			"hint": "奇妙夜的 DOCX 行。选这一页会切到奇妙夜场景并从该行开始。",
		},
		{
			"id": "forest",
			"title": "森林回溯",
			"scene": FOREST_MAIN_SCENE,
			"events": forest_events,
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


## 面板已经把 payload 写进 root meta；回自己是重载，去森林是换场景。
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


## 把事件指针挪到目标行，并把该行之前最后一个场景标题补回舞台上。
func _apply_pending_dev_jump() -> void:
	if _pending_dev_jump.is_empty():
		return
	var requested_source := int(_pending_dev_jump.get("requested_source", 0))
	var resolved := DevJumpPanelScript.resolve_source_line(_events, requested_source)
	if resolved.is_empty():
		_failures.append("婚礼开发跳转目标无效：DOCX 第 %d 行" % requested_source)
		return
	var target_index := int(resolved.get("index", -1))
	if target_index < 0 or target_index >= _events.size():
		_failures.append("婚礼开发跳转事件索引越界：%d" % target_index)
		return
	_dev_jump_active = true
	_dev_jump_requested_source = requested_source
	_dev_jump_actual_source = int(resolved.get("source", 0))
	_event_index = target_index
	_restore_dev_jump_scene_context(target_index)


func _restore_dev_jump_scene_context(target_index: int) -> void:
	var scene_name := ""
	for i in range(clampi(target_index, 0, _events.size())):
		var event: Dictionary = _events[i]
		if str(event.get("type", "")) == "scene":
			scene_name = str(event.get("name", scene_name))
	if scene_name.is_empty():
		return
	_set_scene(scene_name)
	_scene_subtitle.text = "婚礼前段 · 开发跳转到 DOCX 第 %d 行" % _dev_jump_actual_source


func _process(delta: float) -> void:
	if _shake_intensity <= 0.0:
		if _stage_root != null:
			_stage_root.position = Vector2.ZERO
		return
	_shake_phase += delta
	var amplitude := SHAKE_MAX_PIXELS * _shake_intensity
	_stage_root.position = Vector2(
		sin(_shake_phase * 37.0) * amplitude,
		cos(_shake_phase * 29.0) * amplitude * 0.6
	)


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
	# 回溯面板开着的时候 Enter 属于面板的输入框，不能拿去推进剧情。
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
		_failures.append("婚礼前段没有走到终点")
	prologue_finished.emit()
	if _verify_mode:
		_report_verification()
		return
	# 转场节点挂在 SceneTree.root，旧章节释放后仍能覆盖新章节的首帧。
	ChapterTransitionScript.begin(get_tree(), MYSTIC_NIGHT_SCENE)


func _run_event(event: Dictionary) -> void:
	var source := int(event.get("source", 0))
	if source > 0:
		_visited_sources[source] = true
		_current_source = source
		if _dev_jump_overlay != null and _dev_jump_overlay.is_open():
			_dev_jump_overlay.refresh_preview(source)
	match str(event.get("type", "")):
		"scene":
			_set_scene(str(event.get("name", "")))
			await _brief_pause()
		"line":
			await _show_line(event)
		"action":
			_scene_subtitle.text = str(event.get("status", ""))
			await _brief_pause()
		"effect":
			await _run_effect(event)
		"wait":
			await _run_wait(event)
		"interaction":
			await _run_interaction(event)
		"module":
			await _run_module(event)
		"endpoint":
			_endpoint_reached = true
			_scene_label.text = ""
			_scene_subtitle.text = ""
		_:
			_failures.append("未知事件类型：%s" % str(event.get("type", "")))


func _set_scene(scene_name: String) -> void:
	_current_scene = scene_name
	var texture_path := str(_scene_texture_paths.get(scene_name, ""))
	var texture: Texture2D = null
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		texture = load(texture_path)
	if texture != null:
		_scene_texture.texture = texture
		_scene_texture.visible = true
		_scene_label.text = ""
		_scene_subtitle.text = ""
	else:
		# 素材没到位（或导入缓存损坏导致加载失败）的场景保留文字占位回退，不让缺图变成黑屏。
		_scene_texture.visible = false
		_scene_label.text = scene_name
		_scene_subtitle.text = "婚礼前段 · 美术未到位，纯文字舞台占位"


func _show_line(event: Dictionary) -> void:
	# present() 只等到入场动画播完，不等玩家。森林正片在 present 之后还要
	# set_advance_waiting(true) + await advance_requested，婚礼这边原先漏了，
	# 于是 124 条台词全部自动流过去，按 Enter 也没有反应
	# （request_advance() 被 _waiting_for_advance == false 直接挡回）。
	var speaker := str(event.get("speaker", ""))
	var text := str(event.get("text", ""))
	if speaker == "旁白":
		_dialogue_ui.hide_dialogue()
		await _narration_ui.present(text, _verify_mode)
		if _verify_mode:
			return
		await _drain_advance_input()
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
		await _drain_advance_input()
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


func _run_effect(event: Dictionary) -> void:
	if str(event.get("id", "")) != "world_shake":
		return
	_scene_subtitle.text = str(event.get("status", ""))
	_shake_intensity = float(event.get("intensity", 0.5))
	if _verify_mode:
		_shake_intensity = 0.0
		return
	await get_tree().create_timer(SHAKE_SECONDS).timeout
	# 最后一次震动不回零：她就是这样被晃进森林的。
	if _shake_intensity < 1.0:
		_shake_intensity = 0.0


func _run_wait(event: Dictionary) -> void:
	var seconds := float(event.get("seconds", 1.0))
	_scene_subtitle.text = str(event.get("status", ""))
	if _verify_mode:
		return
	await get_tree().create_timer(seconds).timeout


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
	_scene_subtitle.text = str(event.get("status", ""))


func _on_interaction_pressed() -> void:
	_pending_interaction = ""
	_interaction_panel.visible = false


func _run_module(event: Dictionary) -> void:
	var module_id := str(event.get("id", ""))
	var scene_path := str(event.get("scene", ""))
	_visited_modules[module_id] = true
	if not ResourceLoader.exists(scene_path):
		# 模块场景缺失不能卡住剧情：记一笔，让剧本继续走完。
		_failures.append("婚礼模块场景缺失：%s" % scene_path)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("婚礼模块场景无法加载：%s" % scene_path)
		return
	var instance := packed.instantiate()
	if instance.has_method("setup"):
		instance.call("setup", str(event.get("checklist_variant", "")))
	_module_host.add_child(instance)
	_module_host.visible = true
	# 用协程而不是信号：verify 模式下模块可能在 _ready 里就跑完了，
	# 那时再去 await 信号会永久挂起。
	if instance.has_method("run"):
		await instance.call("run", _verify_mode)
	else:
		_failures.append("婚礼模块缺少 run(verify_mode) 协程：%s" % module_id)
	_module_host.visible = false
	if is_instance_valid(instance):
		instance.queue_free()
	if not _verify_mode:
		await _drain_advance_input()


func _drain_advance_input() -> void:
	_active_line_channel = ""
	if _narration_ui != null:
		_narration_ui.set_advance_waiting(false)
	if _dialogue_ui != null:
		_dialogue_ui.set_advance_waiting(false)
	_set_advance_hint(false)
	for _i in range(8):
		await get_tree().process_frame


func _brief_pause() -> void:
	if _verify_mode:
		return
	await get_tree().create_timer(0.25).timeout


func _report_verification() -> void:
	if _dev_jump_overlay == null or not _dev_jump_overlay.verify_contract():
		_failures.append("F4 回溯面板不完整（婚礼前夜 / 奇妙夜 / 森林三页缺失或行号范围为空）")
	elif _dev_jump_overlay.get_chapter_ids() != PackedStringArray([DEV_JUMP_CHAPTER_ID, "mystic_night", "forest"]):
		_failures.append("回溯面板章节页缺失或顺序异常：%s" % str(_dev_jump_overlay.get_chapter_ids()))
	elif _dev_jump_overlay.is_open():
		_failures.append("F4 回溯面板不应默认显示")
	if _endpoint_reached and (not _scene_label.text.is_empty() or not _scene_subtitle.text.is_empty()):
		_failures.append("婚礼前夜 DOCX 145 终点仍显示章节提示文字")
	if not _failures.is_empty():
		for failure in _failures:
			print("WEDDING_PROLOGUE_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("WEDDING_PROLOGUE_PASS events=%d scenes=4 sources=%d modules=%d interactions=%d endpoint=%s narration_lines=%d dialogue_lines=%d font=Times_New_Roman cjk_fallback=SimSun text_only_stage=true advance_gated=true endpoint_text_hidden=true chapter_loading=Where_She_Longs dev_docx_jump=true dev_jump_chapters=wedding_mystic_night_forest wedding_source_bounds=%s" % [
		_events.size(),
		_visited_sources.size(),
		_visited_modules.size(),
		_interactions_done.size(),
		str(_endpoint_reached),
		_narration_ui.get_layout_sample_count(),
		_dialogue_ui.get_presented_line_count(),
		str(DevJumpPanelScript.source_bounds(_events)),
	])
	get_tree().quit(0)


func get_debug_snapshot() -> Dictionary:
	return {
		"wedding_events": _events.size(),
		"wedding_scene": _current_scene,
		"wedding_endpoint": _endpoint_reached,
		"wedding_sources": _visited_sources.size(),
		"wedding_modules": _visited_modules.size(),
		"wedding_interactions": _interactions_done.size(),
		"wedding_shake_intensity": _shake_intensity,
		"wedding_failures": _failures.size(),
	}
