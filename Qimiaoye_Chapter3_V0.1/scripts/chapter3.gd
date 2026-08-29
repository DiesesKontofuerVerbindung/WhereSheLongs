extends Control

## 章节三 · 典礼上的选择 主控制器。
##
## 事件驱动推进：scene / line / action / effect / wait / choice / label / ending。
## 按 DOCX 行号做开发者回溯（F4），支持 --verify 无头验证。

const NarrationUIScript := preload("res://scripts/narration_ui.gd")
const DialogueUIScript := preload("res://scripts/dialogue_ui.gd")
const Chapter3DataScript := preload("res://scripts/chapter3_data.gd")
const Chapter3StageScript := preload("res://scenes/chapter3/chapter3_stage.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")

const CHAPTER_ID := "chapter3"
const CHAPTER_SCENE := "res://scenes/chapter3/chapter3.tscn"
const FONT_PRIMARY_NAME := "Times New Roman"
const FONT_CJK_FALLBACK_NAME := "SimSun"

signal chapter_finished

var _events: Array[Dictionary] = []
var _label_to_index: Dictionary = {}
var _event_index := 0
var _current_scene_name := ""
var _current_source := 0
var _verify_mode := false
var _choice_arg := ""
var _endpoint_reached := false
## 调试用：--trace 打印事件流水与看门狗，--auto 自动推进对话。
var _trace_mode := false
var _auto_mode := false
var _watchdog_accum := 0.0

var _pending_dev_jump: Dictionary = {}
var _dev_jump_active := false
var _dev_jump_overlay
## 当前正在等待玩家推进的通道："" / "NARRATION" / "DIALOGUE"。
var _active_line_channel := ""

var _stage
var _narration_ui
var _dialogue_ui
var _advance_hint: Label

var _primary_font: SystemFont
var _cjk_fallback_font: SystemFont


func _ready() -> void:
    name = "Chapter3"
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    process_mode = Node.PROCESS_MODE_ALWAYS
    _pending_dev_jump = DevJumpPanelScript.take_pending_jump(get_tree().root, CHAPTER_ID)
    _verify_mode = "--verify" in OS.get_cmdline_user_args() or "--verify" in OS.get_cmdline_args()
    _trace_mode = "--trace" in OS.get_cmdline_user_args() or "--trace" in OS.get_cmdline_args()
    _auto_mode = "--auto" in OS.get_cmdline_user_args() or "--auto" in OS.get_cmdline_args()
    _choice_arg = _parse_choice_arg()
    if _verify_mode:
        GameState.reset()
    _configure_typography()
    _build_ui()
    _events = Chapter3DataScript.build_events()
    _build_label_index()
    _setup_dev_jump_chapters()
    _apply_pending_dev_jump()
    call_deferred("_run_events")


func _parse_choice_arg() -> String:
    var all_args := OS.get_cmdline_user_args()
    all_args.append_array(OS.get_cmdline_args())
    for arg in all_args:
        if str(arg).begins_with("--choice="):
            return str(arg).substr("--choice=".length()).strip_edges()
    return ""


func _configure_typography() -> void:
    _cjk_fallback_font = SystemFont.new()
    _cjk_fallback_font.font_names = PackedStringArray(["SimSun", "NSimSun", "宋体", "新宋体"])
    _cjk_fallback_font.allow_system_fallback = false

    _primary_font = SystemFont.new()
    _primary_font.font_names = PackedStringArray([FONT_PRIMARY_NAME])
    _primary_font.allow_system_fallback = false
    _primary_font.fallbacks = [_cjk_fallback_font]

    var app_theme := Theme.new()
    app_theme.default_font = _primary_font
    app_theme.default_font_size = 18
    theme = app_theme


func _build_ui() -> void:
    var root_bg := ColorRect.new()
    root_bg.name = "Chapter3Backdrop"
    root_bg.color = Color(0.04, 0.04, 0.05, 1.0)
    root_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root_bg)

    _stage = Chapter3StageScript.new()
    _stage.name = "CHAPTER3_STAGE"
    add_child(_stage)

    _narration_ui = NarrationUIScript.new()
    _narration_ui.name = "NARRATION_UI"
    _narration_ui.anchor_left = 0.12
    _narration_ui.anchor_top = 0.02
    _narration_ui.anchor_right = 0.88
    _narration_ui.anchor_bottom = 0.20
    add_child(_narration_ui)

    _dialogue_ui = DialogueUIScript.new()
    _dialogue_ui.name = "DIALOGUE_UI"
    add_child(_dialogue_ui)

    _advance_hint = Label.new()
    _advance_hint.name = "AdvanceHint"
    _advance_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
    _advance_hint.offset_left = 16
    _advance_hint.offset_top = 12
    _advance_hint.offset_right = 320
    _advance_hint.offset_bottom = 40
    _advance_hint.add_theme_font_size_override("font_size", 13)
    _advance_hint.add_theme_color_override("font_color", Color(0.72, 0.74, 0.78, 1.0))
    _advance_hint.text = "按 Enter / Space 继续"
    _advance_hint.visible = false
    add_child(_advance_hint)

    _dev_jump_overlay = DevJumpPanelScript.new()
    add_child(_dev_jump_overlay)
    _dev_jump_overlay.jump_requested.connect(_on_dev_jump_requested)


func _setup_dev_jump_chapters() -> void:
    if _dev_jump_overlay == null:
        return
    var chapters: Array[Dictionary] = [
        {
            "id": CHAPTER_ID,
            "title": "章节三 · 典礼上的选择",
            "scene": CHAPTER_SCENE,
            "events": _events,
            "hint": "章节三的 DOCX 行。输入行号将跳转到该行或之后的下一条事件。",
        },
    ]
    _dev_jump_overlay.setup(chapters, CHAPTER_ID)
    _dev_jump_overlay.refresh_preview(_current_source)


func _toggle_dev_jump_panel() -> void:
    if _dev_jump_overlay == null:
        return
    if _dev_jump_overlay.is_open():
        _dev_jump_overlay.close_panel()
    else:
        _dev_jump_overlay.open_panel(_current_source)


func _on_dev_jump_requested(payload: Dictionary) -> void:
    call_deferred("_reload_for_dev_jump")


func _reload_for_dev_jump() -> void:
    var err := get_tree().reload_current_scene()
    if err == OK:
        return
    get_tree().root.remove_meta(DevJumpPanelScript.META_KEY)
    if _dev_jump_overlay != null:
        _dev_jump_overlay.report_jump_failure("场景重载失败，错误码：%d" % err)


func _apply_pending_dev_jump() -> void:
    if _pending_dev_jump.is_empty():
        return
    var requested_source := int(_pending_dev_jump.get("requested_source", 0))
    var resolved := DevJumpPanelScript.resolve_source_line(_events, requested_source)
    if resolved.is_empty():
        push_warning("章节三开发跳转目标无效：DOCX 第 %d 行" % requested_source)
        return
    var target_index := int(resolved.get("index", -1))
    if target_index < 0 or target_index >= _events.size():
        push_warning("章节三开发跳转事件索引越界：%d" % target_index)
        return
    _dev_jump_active = true
    _event_index = target_index
    _restore_dev_jump_context(target_index)


func _restore_dev_jump_context(target_index: int) -> void:
    var last_event := {}
    for i in range(clampi(target_index, 0, _events.size())):
        var event: Dictionary = _events[i]
        var t := str(event.get("type", ""))
        if t == "scene" or t == "video":
            last_event = event.duplicate()
    if last_event.is_empty():
        return
    if str(last_event.get("type", "")) == "video":
        _current_scene_name = str(last_event.get("name", ""))
        _stage.set_background(str(last_event.get("poster", "")))
        _apply_scene_characters(_current_scene_name)
    else:
        _apply_scene_event(last_event)


func _build_label_index() -> void:
    _label_to_index.clear()
    for i in range(_events.size()):
        var event: Dictionary = _events[i]
        if str(event.get("type", "")) == "label":
            var label_id := str(event.get("id", ""))
            if not label_id.is_empty():
                _label_to_index[label_id] = i


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
        return


func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey:
        return
    var key_event := event as InputEventKey
    if not key_event.pressed or key_event.echo:
        return
    if _dev_jump_overlay != null and _dev_jump_overlay.is_open():
        return
    if key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
        # 视频播放中按任意推进键直接跳过，别让玩家被动画绑架。
        if _stage != null and _stage.is_video_playing():
            _stage.request_video_skip()
            get_viewport().set_input_as_handled()
            return
        # 只能推给真正在等推进的那条通道。按鼠标位置猜会推错对象，
        # 旁白就会永远等不到推进，剧情卡死。
        if _active_line_channel == "NARRATION":
            _narration_ui.request_advance()
        elif _active_line_channel == "DIALOGUE":
            _dialogue_ui.request_advance()
        get_viewport().set_input_as_handled()
    elif key_event.keycode == KEY_ESCAPE and _stage != null and _stage.is_video_playing():
        _stage.request_video_skip()
        get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
    if not _trace_mode:
        return
    _watchdog_accum += delta
    if _watchdog_accum < 2.0:
        return
    _watchdog_accum = 0.0
    var video_state := false
    if _stage != null and _stage.has_method("is_video_playing"):
        video_state = bool(_stage.call("is_video_playing"))
    print("[WATCHDOG] idx=%d src=%d channel=%s video=%s" % [
        _event_index, _current_source, _active_line_channel, str(video_state)
    ])


func _schedule_auto_advance(ui) -> void:
    await get_tree().create_timer(0.2).timeout
    if ui != null and is_instance_valid(ui):
        ui.request_advance()


func _run_events() -> void:
    while _event_index < _events.size():
        var event := _events[_event_index]
        _event_index += 1
        await _run_event(event)
    _endpoint_reached = true
    chapter_finished.emit()
    if _verify_mode:
        _report_verification()
        return
    await get_tree().create_timer(1.5).timeout
    get_tree().quit()


func _run_event(event: Dictionary) -> void:
    var source := int(event.get("source", 0))
    if source > 0:
        _current_source = source
        if _dev_jump_overlay != null and _dev_jump_overlay.is_open():
            _dev_jump_overlay.refresh_preview(source)

    if _trace_mode:
        print("[TRACE] idx=%d src=%d type=%s" % [_event_index - 1, source, str(event.get("type", ""))])

    match str(event.get("type", "")):
        "scene":
            await _apply_scene_event(event)
            await _brief_pause()
        "video":
            await _run_video(event)
            await _brief_pause()
        "line":
            await _show_line(event)
        "action":
            await _apply_action(event)
        "effect":
            await _apply_effect(event)
        "wait":
            await _run_wait(event)
        "choice":
            await _run_choice(event)
        "label":
            pass
        "ending":
            await _apply_ending(event)
        _:
            push_warning("章节三未知事件类型：%s" % str(event.get("type", "")))


func _apply_scene_event(event: Dictionary) -> void:
    var scene_name := str(event.get("name", _current_scene_name))
    _current_scene_name = scene_name
    _stage.set_background(_scene_to_bg_path(scene_name))
    _apply_scene_characters(scene_name)


func _run_video(event: Dictionary) -> void:
    var scene_name := str(event.get("name", _current_scene_name))
    var video_path := str(event.get("video", ""))
    var poster_path := str(event.get("poster", ""))
    _current_scene_name = scene_name
    _apply_scene_characters(scene_name)
    if _verify_mode:
        _stage.set_background(poster_path)
        return
    await _stage.play_video(video_path, poster_path)


func _scene_to_bg_path(scene_name: String) -> String:
    match scene_name:
        "场景转换后的妈妈":
            return Chapter3StageScript.BG_MOM_TRANSITION
        "正式婚礼现场":
            return Chapter3StageScript.BG_FORMAL_WEDDING
        "静谧走廊":
            return Chapter3StageScript.BG_CORRIDOR
        "小凌思羽窗边谈话":
            return Chapter3StageScript.BG_WINDOW_TALK
        "小凌思羽窗边谈话-1":
            return Chapter3StageScript.BG_WINDOW_TALK_1
        "小凌思羽窗边谈话-2":
            return Chapter3StageScript.BG_WINDOW_TALK_2
        Chapter3DataScript.SCENE_ENDING_BC:
            return Chapter3StageScript.BG_ENDING_BC
        Chapter3DataScript.SCENE_ENDING_A_VEIL:
            return Chapter3StageScript.BG_ENDING_A_VEIL
        Chapter3DataScript.SCENE_ENDING_A_NO_VEIL:
            return Chapter3StageScript.BG_ENDING_A_NO_VEIL
        Chapter3DataScript.SCENE_ENDING_B_RUN_CARPET:
            return Chapter3StageScript.BG_ENDING_B_RUN_CARPET
        Chapter3DataScript.SCENE_ENDING_BC_SUN_RUN:
            return Chapter3StageScript.BG_ENDING_BC_SUN_RUN
        Chapter3DataScript.SCENE_ENDING_B_RUN_CARPET_1:
            return Chapter3StageScript.BG_ENDING_B_RUN_CARPET_1
        Chapter3DataScript.SCENE_ENDING_C_LEAVE:
            return Chapter3StageScript.BG_ENDING_C_LEAVE
    return ""


func _apply_scene_characters(scene_name: String) -> void:
    match scene_name:
        Chapter3DataScript.SCENE_BEDROOM:
            _stage.set_left_character(Chapter3StageScript.CHR_MOM, true)
            _stage.set_right_character(Chapter3StageScript.CHR_XIAOLING_BRIDE, true)
            _stage.set_character_scale("left", 0.55)
            _stage.set_character_scale("right", 0.55)
        "卧室视频", "场景转换后的妈妈":
            _stage.hide_characters()
        "正式婚礼现场", "静谧走廊", "小凌思羽窗边谈话", "小凌思羽窗边谈话-1":
            _stage.hide_characters()
        _:
            _stage.hide_characters()


func _show_line(event: Dictionary) -> void:
    var speaker := str(event.get("speaker", ""))
    var text := str(event.get("text", ""))
    _highlight_speaker(speaker)

    if speaker == "旁白":
        _dialogue_ui.hide_dialogue()
        await _narration_ui.present(text, _verify_mode)
        if _verify_mode:
            return
        _active_line_channel = "NARRATION"
        _narration_ui.set_advance_waiting(true)
        _set_advance_hint(true)
        if _auto_mode:
            _schedule_auto_advance(_narration_ui)
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
        if _auto_mode:
            _schedule_auto_advance(_dialogue_ui)
        await _dialogue_ui.advance_requested
        _set_advance_hint(false)
        _dialogue_ui.set_advance_waiting(false)
    _active_line_channel = ""


func _highlight_speaker(speaker: String) -> void:
    if speaker == "思雨":
        _stage.fade_character("left", 1.0, 0.25)
        _stage.fade_character("right", 0.45, 0.25)
    elif speaker == "小凌":
        _stage.fade_character("right", 1.0, 0.25)
        _stage.fade_character("left", 0.45, 0.25)
    elif speaker == "妈妈":
        _stage.fade_character("left", 1.0, 0.25)
        _stage.fade_character("right", 0.45, 0.25)
    else:
        _stage.fade_character("left", 1.0, 0.25)
        _stage.fade_character("right", 1.0, 0.25)


func _apply_action(event: Dictionary) -> void:
    var action_id := str(event.get("id", ""))
    match action_id:
        "flash":
            _stage.flash_screen(0.35)
        "shake":
            _stage.shake(0.6, 1.0)
    await _brief_pause()


func _apply_effect(event: Dictionary) -> void:
    var effect_id := str(event.get("id", ""))
    match effect_id:
        "flash":
            _stage.flash_screen(float(event.get("duration", 0.35)))
        "screen_dim":
            _stage.dim_screen(float(event.get("level", 0.5)), float(event.get("duration", 0.8)))
        "screen_bright":
            _stage.dim_screen(0.0, float(event.get("duration", 0.6)))
    await _brief_pause()


func _run_wait(event: Dictionary) -> void:
    if _verify_mode:
        return
    await get_tree().create_timer(float(event.get("seconds", 1.0))).timeout


func _run_choice(event: Dictionary) -> void:
    var options: Array = event.get("options", []) as Array
    if _verify_mode:
        # 验证模式下根据 --choice= 参数或默认 A 自动跳转。
        var chosen_id := _choice_arg if _choice_arg in ["A", "B", "C"] else ""
        for option in options:
            var opt: Dictionary = option
            if chosen_id.is_empty() or str(opt.get("id", "")) == chosen_id:
                var jump_to := str(opt.get("jump_to", ""))
                if _label_to_index.has(jump_to):
                    _event_index = _label_to_index[jump_to] + 1
                    return
        if options.is_empty():
            return
        var first: Dictionary = options[0]
        var jump_to := str(first.get("jump_to", ""))
        if _label_to_index.has(jump_to):
            _event_index = _label_to_index[jump_to] + 1
        return
    if _auto_mode:
        if options.is_empty():
            return
        var auto_opt: Dictionary = options[0]
        _dialogue_ui.hide_dialogue()
        _jump_to_choice(str(auto_opt.get("id", "")), options)
        return
    _dialogue_ui.show_choice(str(event.get("prompt", "你的选择？")), options)
    var choice_id: String = await _dialogue_ui.choice_selected
    _dialogue_ui.hide_dialogue()
    _jump_to_choice(choice_id, options)


func _jump_to_choice(choice_id: String, options: Array) -> void:
    for option in options:
        var opt: Dictionary = option
        if str(opt.get("id", "")) == choice_id:
            var jump_to := str(opt.get("jump_to", ""))
            if _label_to_index.has(jump_to):
                _event_index = _label_to_index[jump_to] + 1
            else:
                push_warning("章节三分支跳转目标不存在：%s" % jump_to)
            return
    push_warning("章节三未匹配到选项：%s" % choice_id)


func _apply_ending(event: Dictionary) -> void:
    var ending_id := str(event.get("ending_id", ""))
    GameState.unlock_ending(ending_id)
    _endpoint_reached = true
    # 结束本章，防止串到其它分支。
    _event_index = _events.size()
    # 结局标题走顶部旁白，屏幕中间不再显示任何占位文字。
    var ending_text := str(event.get("text", "结局 %s" % ending_id))
    _dialogue_ui.hide_dialogue()
    await _narration_ui.present(ending_text, _verify_mode)
    if _verify_mode:
        return
    _narration_ui.set_advance_waiting(true)
    _set_advance_hint(true)
    if _auto_mode:
        _schedule_auto_advance(_narration_ui)
    await _narration_ui.advance_requested
    _set_advance_hint(false)
    _narration_ui.set_advance_waiting(false)


func _brief_pause() -> void:
    if _verify_mode:
        return
    await get_tree().create_timer(0.25).timeout


func _set_advance_hint(enabled: bool) -> void:
    if _advance_hint != null:
        _advance_hint.visible = enabled and not _verify_mode


func _report_verification() -> void:
    var failures: PackedStringArray = []
    if _events.is_empty():
        failures.append("事件表为空")
    if _label_to_index.size() != 3:
        failures.append("分支标签数量异常，期望 3，实际 %d" % _label_to_index.size())
    for label_id in ["ending_a", "ending_b", "ending_c"]:
        if not _label_to_index.has(label_id):
            failures.append("缺失分支标签：%s" % label_id)
    if _dev_jump_overlay == null or not _dev_jump_overlay.verify_contract():
        failures.append("F4 回溯面板不完整")
    if not failures.is_empty():
        for failure in failures:
            print("CHAPTER3_FAIL %s" % failure)
        get_tree().quit(1)
        return
    var bounds := DevJumpPanelScript.source_bounds(_events)
    print("CHAPTER3_PASS events=%d source_bounds=%s labels=%d last_ending=%s unlocked_endings=%d verify_mode=true" % [
        _events.size(),
        str(bounds),
        _label_to_index.size(),
        GameState.last_ending,
        GameState.ending_count(),
    ])
    get_tree().quit(0)
