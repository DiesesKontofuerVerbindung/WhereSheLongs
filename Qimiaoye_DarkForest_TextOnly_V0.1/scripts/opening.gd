extends Control

# 开场界面。分层顺序自下而上：
#   1 纯黑底              视频未就绪时不露白
#   2 标题背景 PNG        静态回退，始终在最底下垫着
#   3 标题背景 OGV        Theora 循环播放；载入失败时自动露出第 2 层
#   4 白色装饰            全幅柔光 + 底部藤蔓
#   5 女主前景
#   6 英文主标题 / 中文副标题 / 英文小字
#   7 开始游戏 / 结束游戏
# 美术资产按 2560x1440 交付，视口是 1280x720，正好 2:1，全部铺满即可对齐。

const UiTypographyScript := preload("res://scripts/ui_typography.gd")
const ChapterTransitionScript := preload("res://scripts/chapter_transition.gd")

const WEDDING_PROLOGUE_SCENE := "res://scenes/wedding/wedding_prologue.tscn"

const BACKGROUND_VIDEO_PATH := "res://assets/opening/title_background.ogv"
# 交付的「标题背景.png」实际是 JPEG 数据，按真实格式落成 .jpg，否则 Godot 的 PNG 导入器直接判损坏。
const BACKGROUND_IMAGE_PATH := "res://assets/opening/title_background.jpg"
const LAYER_PATHS := [
	"res://assets/opening/decor_white.png",
	"res://assets/opening/heroine_foreground.png",
	"res://assets/opening/title_where_she_longs.png",
	"res://assets/opening/title_subtitle_cn.png",
	"res://assets/opening/title_verse_en.png",
]

const DESIGN_SIZE := Vector2(1280.0, 720.0)
# 取自 开始游戏.png 的 alpha 边界（2560 空间 366x84 @ 346,972），换算到 1280 空间。
const MENU_ORIGIN := Vector2(173.0, 432.0)
const MENU_FONT_SIZE := 44
const MENU_SEPARATION := 12

var _typography: UiTypographyScript
var _video: VideoStreamPlayer
var _fallback_image: TextureRect
var _start_button: Button
var _quit_button: Button
var _layers: Array[TextureRect] = []
var _verify_mode := false
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_verify_mode = OS.get_cmdline_user_args().has("--verify")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_typography = UiTypographyScript.new()
	theme = _typography.theme

	_build_backdrop()
	_build_art_layers()
	_build_menu()

	if _verify_mode:
		_run_verification()
		return
	_start_button.grab_focus()


func _build_backdrop() -> void:
	var base := ColorRect.new()
	base.name = "BaseFill"
	base.color = Color.BLACK
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	_fallback_image = _make_layer(BACKGROUND_IMAGE_PATH, "BackgroundFallback")

	var stream: Resource = null
	if ResourceLoader.exists(BACKGROUND_VIDEO_PATH):
		stream = load(BACKGROUND_VIDEO_PATH)
	if stream is VideoStream:
		_video = VideoStreamPlayer.new()
		_video.name = "BackgroundVideo"
		_video.stream = stream as VideoStream
		_video.loop = true
		_video.autoplay = true
		_video.expand = true
		_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_video)
		_video.play()
	else:
		push_warning("开场视频缺失或不是 VideoStream，改用静态标题背景：%s" % BACKGROUND_VIDEO_PATH)


func _build_art_layers() -> void:
	for path in LAYER_PATHS:
		var layer := _make_layer(str(path), str(path).get_file().get_basename())
		if layer != null:
			_layers.append(layer)


func _make_layer(path: String, node_name: String) -> TextureRect:
	if not ResourceLoader.exists(path):
		push_error("开场美术资产缺失：%s" % path)
		return null
	var texture: Resource = load(path)
	if not (texture is Texture2D):
		push_error("开场美术资产不是 Texture2D：%s" % path)
		return null
	var rect := TextureRect.new()
	rect.name = node_name
	rect.texture = texture as Texture2D
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	return rect


func _build_menu() -> void:
	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.alignment = BoxContainer.ALIGNMENT_BEGIN
	menu.add_theme_constant_override("separation", MENU_SEPARATION)
	menu.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# 按设计分辨率的比例定位，窗口拉伸时随 canvas_items 一起缩放。
	menu.anchor_left = MENU_ORIGIN.x / DESIGN_SIZE.x
	menu.anchor_top = MENU_ORIGIN.y / DESIGN_SIZE.y
	menu.anchor_right = menu.anchor_left
	menu.anchor_bottom = menu.anchor_top
	menu.offset_left = 0.0
	menu.offset_top = 0.0
	menu.grow_horizontal = Control.GROW_DIRECTION_END
	menu.grow_vertical = Control.GROW_DIRECTION_END
	add_child(menu)

	_start_button = _make_menu_button("开始游戏")
	_start_button.pressed.connect(_on_start_pressed)
	menu.add_child(_start_button)

	_quit_button = _make_menu_button("结束游戏")
	_quit_button.pressed.connect(_on_quit_pressed)
	menu.add_child(_quit_button)


func _make_menu_button(label: String) -> Button:
	var button := Button.new()
	button.name = label
	button.text = label
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_override("font", _typography.ui)
	button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
	# 美术上的按钮是带暗描边的白字，这里用同样的配色，悬停/聚焦只提亮不换形。
	button.add_theme_color_override("font_color", Color(0.95, 0.96, 0.97))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.93, 0.78))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.93, 0.78))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.85, 0.66))
	button.add_theme_color_override("font_outline_color", Color(0.05, 0.11, 0.15, 0.85))
	button.add_theme_constant_override("outline_size", 6)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	return button


func _on_start_pressed() -> void:
	# 从头开始：清掉上一轮的运行态，再进婚礼前夜。
	#
	# 之前是 change_scene_to_file 硬切：婚礼场景资源不少，切过去会卡一下。
	# 改走和「婚礼前夜 → 奇妙夜 → 森林」同一套章节转场——淡黑、后台线程加载、
	# 右下角显示 Where She Longs、黑屏至少 1.5s 再淡入。
	GameState.reset()
	# 转场期间禁掉两个按钮，避免连点触发第二次。
	if _start_button != null:
		_start_button.disabled = true
	if _quit_button != null:
		_quit_button.disabled = true
	ChapterTransitionScript.begin(
		get_tree(),
		WEDDING_PROLOGUE_SCENE,
		ChapterTransitionScript.GAMEPLAY_MINIMUM_BLACK_SECONDS
	)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _verify_mode:
		return
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_on_quit_pressed()


func _run_verification() -> void:
	if _video == null:
		_failures.append("开场背景视频未载入：%s" % BACKGROUND_VIDEO_PATH)
	if _fallback_image == null:
		_failures.append("开场静态回退图未载入：%s" % BACKGROUND_IMAGE_PATH)
	if _layers.size() != LAYER_PATHS.size():
		_failures.append("开场美术分层缺失：%d/%d" % [_layers.size(), LAYER_PATHS.size()])
	if not _typography.has_project_fonts():
		_failures.append("UI 字体未来自项目资产")
	for probe in ["开", "始", "游", "戏", "结", "束"]:
		if not _typography.ui.has_char(probe.unicode_at(0)):
			_failures.append("UI 字体无法渲染按钮字形：%s" % probe)
	if not _typography.display.has_char("W".unicode_at(0)):
		_failures.append("英文标题字体无法渲染拉丁字符")
	if not _typography.cjk_fallback.has_char("中".unicode_at(0)):
		_failures.append("中文宋体回退无法渲染中文")
	if not ResourceLoader.exists(WEDDING_PROLOGUE_SCENE):
		_failures.append("开始游戏目标场景缺失：%s" % WEDDING_PROLOGUE_SCENE)
	if _start_button == null or _start_button.text != "开始游戏":
		_failures.append("开始游戏按钮缺失")
	if _quit_button == null or _quit_button.text != "结束游戏":
		_failures.append("结束游戏按钮缺失")

	if not _failures.is_empty():
		for failure in _failures:
			print("OPENING_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("OPENING_PASS layers=%d video=%s fallback=%s font=Uranus_Pixel ui_font=%s display_font=%s cjk_fallback=SimSun start_target=%s" % [
		_layers.size(),
		BACKGROUND_VIDEO_PATH.get_file(),
		BACKGROUND_IMAGE_PATH.get_file(),
		UiTypographyScript.UI_FONT_PATH.get_file(),
		UiTypographyScript.DISPLAY_FONT_PATH.get_file(),
		WEDDING_PROLOGUE_SCENE,
	])
	get_tree().quit(0)
