class_name Chapter3Stage
extends Control

## 章节三舞台：背景、人物立绘、场景标签、闪白/压暗/震动、视频播放定格。

const BG_OPENING_POSTER := "res://assets/backgrounds/opening_video_last_frame.png"
const BG_MOM_TRANSITION := "res://assets/backgrounds/场景转换后的妈妈.png"
const BG_FORMAL_WEDDING := "res://assets/backgrounds/正式婚礼现场.png"
const BG_CORRIDOR := "res://assets/backgrounds/静谧走廊.png"
const BG_WINDOW_TALK := "res://assets/backgrounds/小凌思羽窗边谈话.png"
const BG_WINDOW_TALK_1 := "res://assets/backgrounds/小凌思羽窗边谈话-1.png"
const BG_ENDING_A := "res://assets/backgrounds/scene_10_ending_a.png"
const BG_ENDING_BC := "res://assets/backgrounds/scene_11_ending_bc.png"
const BG_ENDING_A_VEIL := "res://assets/backgrounds/结局A带头纱的婚礼现场.jpg"
const BG_ENDING_A_NO_VEIL := "res://assets/backgrounds/结局A不带头纱结婚照.jpg"
const BG_ENDING_B_RUN_CARPET := "res://assets/backgrounds/结局B 光腿在地毯上奔跑.png"
const BG_ENDING_BC_SUN_RUN := "res://assets/backgrounds/结局BC阳光下奔跑.png"
const BG_WINDOW_TALK_2 := "res://assets/backgrounds/小凌思羽窗边谈话-2.png"
const BG_ENDING_B_RUN_CARPET_1 := "res://assets/backgrounds/结局B 光腿在地毯上奔跑-1.png"
const BG_ENDING_C_LEAVE := "res://assets/backgrounds/结局C女主离开，思羽看着她.png"

const VIDEO_OPENING := "res://assets/videos/opening_video.ogv"
# 开场视频实际时长（ffmpeg 实测 4.48s）。播放器的 get_stream_length() 拿得到就用它的，
# 拿不到就退回这个值，避免兜底上限太长把剧情拖住。
const VIDEO_OPENING_SECONDS := 4.5

const CHR_SIYU := "res://assets/characters/siyu.png"
const CHR_XIAOLING_BRIDE := "res://assets/characters/xiaoling_bride.png"
const CHR_MOM := "res://assets/characters/mom.png"

const COLOR_BG := Color(0.04, 0.04, 0.05, 1.0)
const COLOR_ACCENT := Color(0.90, 0.82, 0.66, 1.0)
const COLOR_MUTED := Color(0.62, 0.60, 0.66, 1.0)
const SHAKE_SECONDS := 1.1
const SHAKE_MAX_PIXELS := 26.0
# 拿不到视频时长时的兜底上限，防止解码失败把剧情卡死。
const VIDEO_FALLBACK_SECONDS := 30.0

var _bg: TextureRect
var _video_player: VideoStreamPlayer
var _left_chr: TextureRect
var _right_chr: TextureRect
var _flash_overlay: ColorRect
var _dim_overlay: ColorRect
var _vignette: ColorRect

var _shake_phase := 0.0
var _shake_intensity := 0.0
var _stage_root: Control
var _video_playing := false
var _video_skip_requested := false


func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _build_ui()


func _build_ui() -> void:
    _stage_root = Control.new()
    _stage_root.name = "StageRoot"
    _stage_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _stage_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_stage_root)

    _bg = TextureRect.new()
    _bg.name = "Background"
    _bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
    _bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    _stage_root.add_child(_bg)

    _video_player = VideoStreamPlayer.new()
    _video_player.name = "VideoPlayer"
    _video_player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _video_player.expand = true
    _video_player.autoplay = false
    _video_player.visible = false
    _video_player.paused = false
    _video_player.buffering_msec = 0
    _stage_root.add_child(_video_player)

    _left_chr = _make_character("LeftCharacter")
    _left_chr.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
    _left_chr.offset_left = -40
    _left_chr.offset_top = -620
    _left_chr.offset_right = 420
    _left_chr.offset_bottom = 60
    _stage_root.add_child(_left_chr)

    _right_chr = _make_character("RightCharacter")
    _right_chr.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
    _right_chr.offset_left = -420
    _right_chr.offset_top = -620
    _right_chr.offset_right = 40
    _right_chr.offset_bottom = 60
    _stage_root.add_child(_right_chr)

    _vignette = ColorRect.new()
    _vignette.name = "Vignette"
    _vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _vignette.color = Color.BLACK
    _vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _vignette.material = _make_vignette_material()
    add_child(_vignette)

    _dim_overlay = ColorRect.new()
    _dim_overlay.name = "DimOverlay"
    _dim_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _dim_overlay.color = Color.BLACK
    _dim_overlay.modulate.a = 0.0
    _dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_dim_overlay)

    _flash_overlay = ColorRect.new()
    _flash_overlay.name = "FlashOverlay"
    _flash_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _flash_overlay.color = Color.WHITE
    _flash_overlay.modulate.a = 0.0
    _flash_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_flash_overlay)

    set_background("")


func _make_character(node_name: String) -> TextureRect:
    var rect := TextureRect.new()
    rect.name = node_name
    rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
    rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
    rect.visible = false
    rect.modulate.a = 0.0
    rect.pivot_offset = rect.size * 0.5
    return rect


func _make_vignette_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type canvas_item;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    float dist = length(uv) * 1.6;
    float alpha = smoothstep(0.4, 1.1, dist);
    COLOR = vec4(0.0, 0.0, 0.0, alpha * 0.55);
}
"""
    var mat := ShaderMaterial.new()
    mat.shader = shader
    return mat


func set_background(res_path: String) -> void:
    _stop_video()
    _bg.visible = true
    if res_path != null and not res_path.is_empty() and ResourceLoader.exists(res_path):
        _bg.texture = load(res_path) as Texture2D
    else:
        _bg.texture = null
    if "--trace" in OS.get_cmdline_user_args() or "--trace" in OS.get_cmdline_args():
        var tex := _bg.texture as Texture2D
        print("[BG] %s -> %s" % [res_path, ("%dx%d" % [tex.get_width(), tex.get_height()]) if tex != null else "NULL"])


func is_video_playing() -> bool:
    return _video_playing


## 玩家按键跳过视频。视频没在放的时候调用无副作用。
func request_video_skip() -> void:
    if _video_playing:
        _video_skip_requested = true


func play_video(res_path: String, poster_path: String) -> void:
    # 无头环境没有渲染后端，视频解码不会推进，直接落到尾帧，避免挂起。
    if DisplayServer.get_name() == "headless":
        set_background(poster_path)
        return

    var stream: VideoStream = null
    if ResourceLoader.exists(res_path):
        stream = load(res_path) as VideoStream
    if stream == null:
        push_warning("视频资源不存在或无法载入：%s，直接显示尾帧" % res_path)
        set_background(poster_path)
        return

    _video_skip_requested = false
    _video_playing = true
    _bg.visible = false
    _video_player.visible = true
    _video_player.stream = stream
    _video_player.paused = false
    _video_player.play()

    # 时长优先问播放器，问不到就用常量。
    var duration := VIDEO_OPENING_SECONDS
    if _video_player.has_method("get_stream_length"):
        var queried := float(_video_player.call("get_stream_length"))
        if queried > 0.0:
            duration = queried
    # 别信 finished 信号和 is_playing()：Theora 在 4.7 上实测两者都不可靠——
    # 播完了信号不发、is_playing() 一直为真，靠它们判断就会白等一大截。
    # 直接用已知时长走真实时钟（不是 delta 累加，掉帧/切后台都不会拖死）。
    var trace := "--trace" in OS.get_cmdline_user_args() or "--trace" in OS.get_cmdline_args()
    var started_at := Time.get_ticks_msec()
    var saw_finished := false
    _video_player.finished.connect(func() -> void: saw_finished = true)

    var play_ms := int(duration * 1000.0)
    var grace_ms := 350
    var bail_ms := 1200
    var deadline := started_at + play_ms + grace_ms
    # 起播需要一两帧，先看到 is_playing() 为真才认它是「播过又停了」。
    var started := false
    if trace:
        print("[VIDEO] start %s duration=%.3f budget_ms=%d" % [res_path, duration, play_ms + grace_ms])

    while Time.get_ticks_msec() < deadline:
        await get_tree().process_frame
        if _video_skip_requested or saw_finished:
            break
        if _video_player.is_playing():
            started = true
        elif started:
            break
        elif Time.get_ticks_msec() - started_at > bail_ms:
            # 一直没起播，解码失败，别干等着，直接落尾帧。
            break

    if trace:
        print("[VIDEO] end elapsed_ms=%d finished=%s started=%s skip=%s" % [
            Time.get_ticks_msec() - started_at, str(saw_finished), str(started), str(_video_skip_requested)
        ])

    _video_player.stop()
    _video_player.stream = null
    _video_player.visible = false
    _video_playing = false
    _video_skip_requested = false
    # 定格在尾帧图。
    if poster_path != null and not poster_path.is_empty() and ResourceLoader.exists(poster_path):
        _bg.texture = load(poster_path) as Texture2D
    _bg.visible = true


func _stop_video() -> void:
    if _video_player != null and _video_player.is_playing():
        _video_player.stop()
    if _video_player != null:
        _video_player.visible = false
    _video_playing = false
    _video_skip_requested = false


func set_left_character(res_path: String, visible := true) -> void:
    _set_character(_left_chr, res_path, visible)


func set_right_character(res_path: String, visible := true) -> void:
    _set_character(_right_chr, res_path, visible)


func _set_character(rect: TextureRect, res_path: String, show: bool) -> void:
    if res_path != null and not res_path.is_empty() and ResourceLoader.exists(res_path):
        rect.texture = load(res_path) as Texture2D
    if not show or rect.texture == null:
        rect.visible = false
        return
    rect.visible = true
    rect.modulate.a = 1.0


func hide_characters() -> void:
    _left_chr.visible = false
    _right_chr.visible = false


func fade_character(side: String, target_alpha: float, duration: float) -> void:
    var rect := _left_chr if side == "left" else _right_chr
    var tween := create_tween()
    tween.tween_property(rect, "modulate:a", target_alpha, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func flash_screen(seconds := 0.35) -> void:
    var tween := create_tween()
    tween.tween_property(_flash_overlay, "modulate:a", 1.0, 0.08).set_trans(Tween.TRANS_LINEAR)
    tween.tween_property(_flash_overlay, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func dim_screen(level: float, duration := 0.4) -> void:
    level = clampf(level, 0.0, 0.85)
    var tween := create_tween()
    tween.tween_property(_dim_overlay, "modulate:a", level, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func fade_to_black(seconds := 1.2) -> void:
    var tween := create_tween()
    tween.tween_property(_dim_overlay, "modulate:a", 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func fade_from_black(seconds := 1.2) -> void:
    var tween := create_tween()
    tween.tween_property(_dim_overlay, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func shake(intensity := 0.5, seconds := SHAKE_SECONDS) -> void:
    _shake_intensity = intensity
    _shake_phase = 0.0
    var tween := create_tween()
    tween.tween_property(self, "_shake_intensity", 0.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func set_character_scale(side: String, scale: float) -> void:
    var rect := _left_chr if side == "left" else _right_chr
    rect.scale = Vector2.ONE * scale


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
