extends Control

## 婚礼前段外壳。
##
## 复用森林正片同一套 UI（NARRATION_UI 顶部旁白、DIALOGUE_UI 底部对白、
## Enter/Space 推进、Times New Roman + 宋体回退），但事件表、场景与推进循环
## 完全独立：森林正片的 _events / source bounds / docx_source_lock 都被
## verify 硬断言锁住了，把婚礼混进去只会把那些断言全部打掉。
##
## 四场景底图走 KEEP_ASPECT_COVERED（源图约 3:2，16:9 上下各裁约 11%）。
## 缺图时回退文字占位，避免黑屏。

const NarrationUIScript := preload("res://scripts/narration_ui.gd")
const DialogueUIScript := preload("res://scripts/dialogue_ui.gd")
const WeddingDataScript := preload("res://scripts/wedding_data.gd")
const MysticNightDataScript := preload("res://scripts/mystic_night_data.gd")
const Chapter3DataScript := preload("res://scripts/chapter3_data.gd")
const StoryDataScript := preload("res://scripts/story_data.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")
const ChapterIndexScript := preload("res://scripts/chapter_index.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const ChapterTransitionScript := preload("res://scripts/chapter_transition.gd")
const UiTypographyScript := preload("res://scripts/ui_typography.gd")

const FOREST_MAIN_SCENE := "res://main.tscn"
const WEDDING_PROLOGUE_SCENE := "res://scenes/wedding/wedding_prologue.tscn"
const MYSTIC_NIGHT_SCENE := "res://scenes/mystic_night/mystic_night.tscn"
const CHAPTER3_SCENE := "res://scenes/chapter3/chapter3.tscn"
const DEV_JUMP_CHAPTER_ID := "wedding"
const FONT_PRIMARY_NAME := "Times New Roman"
const FONT_CJK_FALLBACK_NAME := "SimSun"

const COLOR_BG := Color(0.055, 0.05, 0.07, 1.0)
const COLOR_ACCENT := Color(0.86, 0.78, 0.62, 1.0)
const COLOR_MUTED := Color(0.62, 0.60, 0.66, 1.0)

## 场景名 → 底图。路径与 wedding_data 场景常量对齐。
const SCENE_TEXTURE_PATHS := {
	"婚礼背景图1": "res://assets/wedding/scene_wedding_1.png",
	"婚礼背景图2": "res://assets/wedding/scene_wedding_eve.jpg",
	"车上背景图": "res://assets/wedding/scene_car.png",
	"家里场景": "res://assets/wedding/scene_home.png",
}

## 婚礼前段 BGM/环境声资源路径。命名用 ASCII，避免中文路径在打包/导入时的坑。
const AUDIO_WEDDING_BGM_OPENING := "res://assets/audio/wedding_bgm_opening.ogg"
const AUDIO_WEDDING_AMB_REHEARSAL := "res://assets/audio/wedding_amb_rehearsal.mp3"
const AUDIO_WEDDING_BGM_CAR := "res://assets/audio/wedding_bgm_car.ogg"
const AUDIO_WEDDING_BGM_HOME := "res://assets/audio/wedding_bgm_home.ogg"
## 淡入淡出时长（秒）。
const AUDIO_FADE_SECONDS := 1.2

const SHAKE_SECONDS := 1.1
const SHAKE_MAX_PIXELS := 26.0

signal prologue_finished

var _events: Array[Dictionary] = []
var _event_index := 0
var _current_scene := ""
var _verify_mode := false
var _record_progress := false
var _endpoint_reached := false
var _visited_sources: Dictionary = {}
var _visited_modules: Dictionary = {}
var _interactions_done: Dictionary = {}
var _failures: PackedStringArray = []

var _dev_jump_overlay
var _pause_menu
var _pending_dev_jump: Dictionary = {}
var _dev_jump_active := false
var _dev_jump_requested_source := 0
var _dev_jump_actual_source := 0
var _current_source := 0

var _primary_font: Font
var _cjk_fallback_font: SystemFont
var _typography: UiTypographyScript
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

## 双层音频播放器：BGM（旋律音乐）+ 环境声（现实声场）各自独立淡入淡出、循环。
## 分开便于在重叠段（如婚礼 BGM 淡出、彩排环境声淡入）做交叉渐变。
var _bgm_player: AudioStreamPlayer
var _amb_player: AudioStreamPlayer
var _bgm_volume := 0.0
var _amb_volume := 0.0

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
	## --record-progress：允许 verify 跑把走过的节点写进存档。
	## 默认关着——headless 验证瞬间跑完全流程，默认打点会把整张回溯图点亮。
	## 打开它是为了用一次真实遍历生成「全进度存档」，节点确实被走到了，只是快进。
	_record_progress = "--record-progress" in OS.get_cmdline_user_args() or "--record-progress" in OS.get_cmdline_args()
	_configure_typography()
	_build_ui()
	_events = WeddingDataScript.build_events()
	_setup_dev_jump_chapters()
	_apply_pending_dev_jump()
	call_deferred("_run_events")


func _configure_typography() -> void:
	_typography = UiTypographyScript.new()
	_cjk_fallback_font = _typography.cjk_fallback
	_primary_font = _typography.body

	var app_theme := _typography.theme
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

	# 底图在 Label 之前：文字叠在图上；COVERED 保满屏，3:2→16:9 上下裁边。
	_scene_texture = TextureRect.new()
	_scene_texture.name = "WeddingSceneTexture"
	_scene_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scene_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scene_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_scene_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_scene_subtitle.text = "婚礼前段 · 场景切换中"
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

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.name = "WeddingBGMAudio"
	_bgm_player.bus = &"Master"
	_bgm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_player.volume_db = -80.0
	add_child(_bgm_player)

	_amb_player = AudioStreamPlayer.new()
	_amb_player.name = "WeddingAmbAudio"
	_amb_player.bus = &"Master"
	_amb_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_amb_player.volume_db = -80.0
	add_child(_amb_player)

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

	# ESC 暂停菜单。verify 模式不建：headless 验证不需要它，
	# 也免得它出现在各章的自检节点扫描里。
	if not _verify_mode:
		_pause_menu = PauseMenuScript.new()
		add_child(_pause_menu)
		_pause_menu.setup(DEV_JUMP_CHAPTER_ID)
		# 回溯跳转复用开发者跳转那条已经在跑的通路，不再写第二套切场景逻辑。
		_pause_menu.jump_requested.connect(_on_dev_jump_requested)


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
		{
			"id": "chapter3",
			"title": "典礼上的选择回溯",
			"scene": CHAPTER3_SCENE,
			"events": Chapter3DataScript.build_events(),
			"hint": "章节三（典礼上的选择）的 DOCX 行。选这一页会切到章节三场景并从该行开始。",
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
	# 回溯跳转不是开发者跳转：玩家是在正常重玩，结尾要照常切下一章、
	# 沿途也要照常打点。只有 F4 面板发来的 payload 才算 dev jump。
	_dev_jump_active = not bool(_pending_dev_jump.get("rollback", false))
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
	if OS.has_feature("editor") and key_event.keycode == KEY_F4:
		_toggle_dev_jump_panel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and _dev_jump_overlay != null and _dev_jump_overlay.is_open():
		_dev_jump_overlay.close_panel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and _pause_menu != null:
		_pause_menu.toggle()
		get_viewport().set_input_as_handled()
		return


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


func _unhandled_input(event: InputEvent) -> void:
	# 手机 / 微信 H5：点击或触屏推进当前对白。
	if _dev_jump_overlay != null and _dev_jump_overlay.is_open():
		return
	if _active_line_channel.is_empty():
		return
	var tapped := false
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		tapped = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	elif event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	if not tapped:
		return
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
	# 章节结束收尾音频，避免进入下一章后残留播放。
	_audio_stop_immediate("bgm")
	_audio_stop_immediate("amb")
	if _verify_mode:
		_report_verification()
		return
	# 小凌闭眼后先进入奇妙夜；project.godot 的主场景仍然是森林，现有 verify
	# 与打包入口不受影响。
	await get_tree().create_timer(2.0).timeout
	# 微信/网页试玩包：不继续加载后续章节，避免体积过大且便于分享。
	if OS.has_feature("web") or OS.has_feature("wedding_demo"):
		_scene_label.visible = true
		_scene_label.text = "试玩到此结束"
		_scene_subtitle.visible = true
		_scene_subtitle.text = "谢谢试玩 · 婚礼前夜"
		_narration_ui.hide()
		_dialogue_ui.hide()
		return
	ChapterTransitionScript.begin(get_tree(), MYSTIC_NIGHT_SCENE)


func _run_event(event: Dictionary) -> void:
	# 回溯打点：只有真正在玩的时候才记。verify 会瞬间跑完全流程，
	# 开发者跳转一次就能把整张图点亮，两者都不能算数。
	if (not _verify_mode or _record_progress) and not _dev_jump_active and ChapterIndexScript.is_anchor(event):
		ChapterProgress.visit(DEV_JUMP_CHAPTER_ID, int(event.get("source", 0)))
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
		"audio":
			await _apply_audio_event(event)
		"endpoint":
			_endpoint_reached = true
			_scene_label.visible = true
			_scene_subtitle.visible = true
			_scene_label.text = str(event.get("text", ""))
			_scene_subtitle.text = "下一段：%s" % str(event.get("next", ""))
		_:
			_failures.append("未知事件类型：%s" % str(event.get("type", "")))


func _set_scene(scene_name: String) -> void:
	_current_scene = scene_name
	_scene_label.text = scene_name
	var path := str(SCENE_TEXTURE_PATHS.get(scene_name, ""))
	var tex: Texture2D = null
	if not path.is_empty() and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if _scene_texture != null:
		_scene_texture.texture = tex
		_scene_texture.visible = tex != null
	if tex != null:
		_scene_label.visible = false
		_scene_subtitle.visible = false
		_scene_subtitle.text = ""
	else:
		_scene_label.visible = true
		_scene_subtitle.visible = true
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
		# 等入场后再开推进门，避免模块残留输入立刻跳过这句。
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
	if event.has("status"):
		_scene_subtitle.text = str(event["status"])
	if _verify_mode:
		return
	await get_tree().create_timer(seconds).timeout


## 处理 audio 事件。字段：
##   action: "start" 播放（循环，淡入）；"stop" 停止（淡出）；"stop_immediate" 立即停。
##   channel: "bgm"（旋律）或 "amb"（环境声）。缺省按资源类型自动判定。
##   stream: 语义名映射（wedding_bgm_opening 等），或直接 res:// 路径。
##   fade: 覆盖淡入淡出时长（秒）。
func _apply_audio_event(event: Dictionary) -> void:
	var action := str(event.get("action", ""))
	var stream_key := str(event.get("stream", ""))
	var channel := str(event.get("channel", ""))
	var fade := float(event.get("fade", AUDIO_FADE_SECONDS))
	# stop 类动作只按通道停，不需要 stream；start 才需要解析资源。
	if action == "stop" or action == "stop_immediate":
		if channel.is_empty():
			push_warning("婚礼前段 audio 事件缺 channel：%s" % str(event))
			return
		if action == "stop":
			await _audio_stop(channel, fade)
		else:
			_audio_stop_immediate(channel)
		return
	var path := _resolve_audio_path(stream_key)
	if path.is_empty():
		push_warning("婚礼前段 audio 事件缺 stream：%s" % str(event))
		return
	if channel.is_empty():
		channel = "amb" if path.ends_with(".mp3") else "bgm"
	match action:
		"start":
			await _audio_start(channel, path, fade)
		_:
			push_warning("婚礼前段未知 audio action：%s" % action)


## 把语义名映射到真实资源路径。换音频时只改这里，事件表不用动。
func _resolve_audio_path(key: String) -> String:
	match key:
		"wedding_bgm_opening":
			return AUDIO_WEDDING_BGM_OPENING
		"wedding_amb_rehearsal":
			return AUDIO_WEDDING_AMB_REHEARSAL
		"wedding_bgm_car":
			return AUDIO_WEDDING_BGM_CAR
		"wedding_bgm_home":
			return AUDIO_WEDDING_BGM_HOME
	return key


func _audio_player(channel: String) -> AudioStreamPlayer:
	return _amb_player if channel == "amb" else _bgm_player


func _audio_start(channel: String, path: String, fade: float) -> void:
	var player := _audio_player(channel)
	if _verify_mode:
		return
	var stream: AudioStream = load(path)
	if stream == null:
		push_warning("婚礼前段音频加载失败：%s" % path)
		return
	if player.stream == stream and player.playing:
		# 同一段已在放，不做重复淡入。
		return
	player.stream = stream
	if player is AudioStreamPlayer and player.stream is AudioStreamWAV:
		player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	if not player.playing:
		player.play()
	if channel == "amb":
		_amb_volume = 1.0
	else:
		_bgm_volume = 1.0
	await _fade_player_volume(player, channel, 1.0, fade)


func _audio_stop(channel: String, fade: float) -> void:
	var player := _audio_player(channel)
	if _verify_mode:
		return
	if channel == "amb":
		_amb_volume = 0.0
	else:
		_bgm_volume = 0.0
	await _fade_player_volume(player, channel, 0.0, fade)
	if player.playing:
		player.stop()
	player.stream = null


func _audio_stop_immediate(channel: String) -> void:
	var player := _audio_player(channel)
	player.stop()
	player.stream = null


func _fade_player_volume(player: AudioStreamPlayer, channel: String, target_vol: float, fade: float) -> void:
	if player == null:
		return
	var start_db := player.volume_db
	var end_db := _db_for_volume(target_vol)
	var tween := create_tween()
	tween.tween_property(player, "volume_db", end_db, fade if _verify_mode == false else 0.0)
	await tween.finished


func _db_for_volume(vol: float) -> float:
	if vol <= 0.0:
		return -80.0
	return linear_to_db(vol)


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
	# 模块结束后排空推进键，避免下一句对白被同一帧/下一帧的 Enter 跳过。
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
		_failures.append("F4 回溯面板不完整（婚礼前夜 / 奇妙夜 / 森林 / 章节三 四页缺失或行号范围为空）")
	elif _dev_jump_overlay.get_chapter_ids() != PackedStringArray([DEV_JUMP_CHAPTER_ID, "mystic_night", "forest", "chapter3"]):
		_failures.append("回溯面板章节页缺失或顺序异常：%s" % str(_dev_jump_overlay.get_chapter_ids()))
	elif _dev_jump_overlay.is_open():
		_failures.append("F4 回溯面板不应默认显示")
	if not _failures.is_empty():
		for failure in _failures:
			print("WEDDING_PROLOGUE_FAIL %s" % failure)
		get_tree().quit(1)
		return
	var scenes_with_art := 0
	for path_variant in SCENE_TEXTURE_PATHS.values():
		var art_path := str(path_variant)
		if not art_path.is_empty() and ResourceLoader.exists(art_path):
			scenes_with_art += 1
	var stage_mode := "text_only_stage=true"
	if scenes_with_art >= 4:
		stage_mode = "scene_art=true scenes_textured=%d" % scenes_with_art
	elif scenes_with_art > 0:
		stage_mode = "scene_art=partial scenes_textured=%d" % scenes_with_art
	print("WEDDING_PROLOGUE_PASS events=%d scenes=4 sources=%d modules=%d interactions=%d endpoint=%s narration_lines=%d dialogue_lines=%d font=Times_New_Roman cjk_fallback=SimSun %s advance_gated=true dev_docx_jump=true dev_jump_chapters=wedding_mystic_night_forest_chapter3 wedding_source_bounds=%s" % [
		_events.size(),
		_visited_sources.size(),
		_visited_modules.size(),
		_interactions_done.size(),
		str(_endpoint_reached),
		_narration_ui.get_layout_sample_count(),
		_dialogue_ui.get_presented_line_count(),
		stage_mode,
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
