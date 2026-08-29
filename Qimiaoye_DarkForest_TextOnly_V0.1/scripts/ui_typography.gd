extends RefCounted

# 共享 UI 字体入口。四个章节外壳原先各自复制一份 SystemFont 配置，
# 这里统一成三个角色：
#   body    正文。仍是 Times New Roman + SimSun 链，保持既有观感与各外壳自检。
#   ui      标题 / 按钮 / 开发者面板。项目内置的天王星像素体，缺字回退 SimSun。
#   display 英文品牌字样。项目内置 Ethereal Nymeria，仅覆盖拉丁字符，
#           因此挂 ui -> SimSun 作为后续回退，避免中文变豆腐块。
# 字体一律来自 res:// 资产，不依赖系统是否安装。

const DISPLAY_FONT_PATH := "res://assets/fonts/ethereal_nymeria.ttf"
const UI_FONT_PATH := "res://assets/fonts/uranus_pixel_11px.ttf"

const BODY_PRIMARY_NAME := "Times New Roman"
const CJK_FALLBACK_NAME := "SimSun"
const CJK_FALLBACK_NAMES := ["SimSun", "NSimSun", "宋体", "新宋体"]

var cjk_fallback: SystemFont
var body: SystemFont
var ui: Font
var display: Font
var theme: Theme


func _init() -> void:
	cjk_fallback = SystemFont.new()
	cjk_fallback.font_names = PackedStringArray(CJK_FALLBACK_NAMES)
	cjk_fallback.allow_system_fallback = false

	body = SystemFont.new()
	body.font_names = PackedStringArray([BODY_PRIMARY_NAME])
	body.allow_system_fallback = false
	var body_chain: Array[Font] = [cjk_fallback]
	body.fallbacks = body_chain

	ui = _load_font(UI_FONT_PATH, [cjk_fallback])
	display = _load_font(DISPLAY_FONT_PATH, [ui, cjk_fallback])

	theme = Theme.new()
	theme.default_font = body
	# 按钮统一走项目字体；正文标签仍继承 default_font。
	theme.set_font("font", "Button", ui)
	theme.set_font("font", "CheckBox", ui)
	theme.set_font("font", "OptionButton", ui)
	theme.set_font("font", "TabBar", ui)
	theme.set_font("font", "LineEdit", ui)


# 资产字体缺失时不能让整个外壳崩掉，退回正文链即可，
# 由调用方的自检去暴露问题。
func _load_font(path: String, chain: Array[Font]) -> Font:
	if not ResourceLoader.exists(path):
		push_error("UI 字体资产缺失：%s" % path)
		return body
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is Font):
		push_error("UI 字体资产无法作为 Font 载入：%s" % path)
		return body
	var font: Font = (loaded as Font).duplicate()
	font.fallbacks = chain
	return font


func has_project_fonts() -> bool:
	return ui != body and display != body
