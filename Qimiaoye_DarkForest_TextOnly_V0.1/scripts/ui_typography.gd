extends RefCounted

# 共享 UI 字体入口。四个章节外壳原先各自复制一份 SystemFont 配置，
# 这里统一成三个角色：
#   body    正文。项目内置的天王星像素体，只有缺字时才回退 SimSun。
#   ui      标题 / 按钮 / 开发者面板。同一项目字体，缺字回退 SimSun。
#   display 英文品牌字样。项目内置 Ethereal Nymeria，仅覆盖拉丁字符，
#           因此挂 ui -> SimSun 作为后续回退，避免中文变豆腐块。
# 字体一律来自 res:// 资产，不依赖系统是否安装。

const DISPLAY_FONT_PATH := "res://assets/fonts/ethereal_nymeria.ttf"
const UI_FONT_PATH := "res://assets/fonts/uranus_pixel_11px.ttf"

const BODY_PRIMARY_NAME := "Uranus Pixel"
const CJK_FALLBACK_NAME := "SimSun"
const FONT_SOURCE_META := "qimiaoye_font_source"
## 末端中文回退的候选族名，按平台顺序排。allow_system_fallback 关着，所以这张表
## 必须覆盖目标平台：只写 Windows 的宋体家族时，macOS 上一个都命中不到，
## SystemFont 渲染不出任何汉字，opening / main 的自检会直接报
## 「中文宋体回退无法渲染中文」（CI run 33509121433 实测）。
## SimSun 保持第一位：各章节自检和 text_input 模块测试都断言链首是它。
const CJK_FALLBACK_NAMES := [
	# Windows
	"SimSun", "NSimSun", "宋体", "新宋体",
	# macOS：系统自带，无需额外安装
	"Songti SC", "STSong", "PingFang SC", "Heiti SC", "Hiragino Sans GB",
	# Linux 常见 CJK 字体
	"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Micro Hei",
]

var cjk_fallback: SystemFont
var body: Font
var ui: Font
var display: Font
var theme: Theme


func _init() -> void:
	cjk_fallback = SystemFont.new()
	cjk_fallback.font_names = PackedStringArray(CJK_FALLBACK_NAMES)
	cjk_fallback.allow_system_fallback = false

	body = _load_font(UI_FONT_PATH, [cjk_fallback])
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
		return cjk_fallback
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is Font):
		push_error("UI 字体资产无法作为 Font 载入：%s" % path)
		return cjk_fallback
	var font: Font = (loaded as Font).duplicate()
	font.fallbacks = chain
	font.set_meta(FONT_SOURCE_META, path)
	return font


func body_uses_project_font() -> bool:
	return (
		body != null
		and body != cjk_fallback
		and str(body.get_meta(FONT_SOURCE_META, "")) == UI_FONT_PATH
		and body.fallbacks.size() == 1
		and body.fallbacks[0] == cjk_fallback
	)


func has_project_fonts() -> bool:
	return body_uses_project_font() and ui != body and display != body
