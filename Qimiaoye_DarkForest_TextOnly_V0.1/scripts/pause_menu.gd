extends CanvasLayer

## ESC 暂停菜单 + 场景回溯。
##
## 画风沿用开场界面（opening.gd）：同一套 UiTypography 字体、扁平白字按钮、
## 暖色悬停、暗描边 outline_size=6、四个 StyleBoxEmpty。
##
## 布局与动效：
##   关闭回溯时  菜单列居中（anchor 0.25–0.75）
##   打开回溯后  菜单列左移（0.02–0.40），回溯列表从右侧滑入（1.02 → 0.42）
##   两列都用 anchor 补间而不是 position，跟着 canvas_items 缩放，分辨率无关。
##
## 暂停语义的边界（先写明白）：
##   get_tree().paused = true 能冻住玩法模块的 _process / _physics_process
##   （跑酷、跳水、星瓶）。但它**冻不住剧情节奏**：剧情里大量
##   get_tree().create_timer(t) 的 process_always 默认是 true，也就是「忽略暂停」。
##   彻底解决要把那些计时器收进统一的 StoryClock，属于后续步骤，这一版不做。
##
## 另一个必须自己处理的点：节点被暂停后 _input 不再被调用，宿主章节在暂停期间
## 收不到 ESC。菜单自己带 PROCESS_MODE_WHEN_PAUSED 并处理 ESC，
## 否则会「进得去出不来」。

signal resumed
## payload 结构与 dev_jump_panel 完全一致，多一个 rollback=true。
## 宿主章节直接接到已有的 _on_dev_jump_requested 上，不再写第二套切场景逻辑。
signal jump_requested(payload: Dictionary)

const UiTypographyScript := preload("res://scripts/ui_typography.gd")
const ChapterTransitionScript := preload("res://scripts/chapter_transition.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")
const ChapterIndexScript := preload("res://scripts/chapter_index.gd")
const OPENING_SCENE := "res://scenes/opening/opening.tscn"

const OVERLAY_LAYER := 128
## 有了背景模糊之后遮罩可以让一点，让底下的画面还能认出来，而不是糊成一片黑。
const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.62)
## 背景毛玻璃。复用 cutscene_player 那套盒式模糊的写法，改成采样屏幕纹理。
const BLUR_RADIUS := 0.0055
const TITLE_FONT_SIZE := 28
const MENU_FONT_SIZE := 38
const NODE_FONT_SIZE := 22
const CHAPTER_FONT_SIZE := 24
const MENU_SEPARATION := 10
const TITLE_GAP := 26

## 与开场界面的过场时长同源（BlinkConfiguration.fade_seconds = 0.28）。
const SLIDE_SECONDS := 0.28
## 唤起 / 收起。收起要比唤起快，按 ESC 退出得干脆。
const FADE_IN_SECONDS := 0.26
const FADE_OUT_SECONDS := 0.16
## 菜单整体从下方抬起。用 offset_top 而不是 position——
## 这两个面板是靠 anchor 定位的，直接改 position 会在下一次布局里被覆盖。
const MENU_RISE_PIXELS := 40.0
## 菜单项逐条入场的间隔。标题、五个按钮依次亮起，比整块一起淡入有层次。
## 按钮在 VBoxContainer 里，位置由容器算，所以只能动 modulate，不能动 position。
const ITEM_STAGGER_SECONDS := 0.05
const ITEM_FADE_SECONDS := 0.22

const MENU_ANCHOR_CENTER := Vector2(0.25, 0.75)
const MENU_ANCHOR_LEFT := Vector2(0.02, 0.40)
const ROLLBACK_ANCHOR_OFF := Vector2(1.02, 1.60)
const ROLLBACK_ANCHOR_ON := Vector2(0.42, 0.98)

## 与 opening.gd/_make_menu_button 完全一致的配色。
const COLOR_NORMAL := Color(0.95, 0.96, 0.97)
const COLOR_HOVER := Color(1.0, 0.93, 0.78)
const COLOR_PRESSED := Color(0.98, 0.85, 0.66)
const COLOR_DISABLED := Color(0.62, 0.66, 0.74, 0.7)
const COLOR_OUTLINE := Color(0.05, 0.11, 0.15, 0.85)
const COLOR_TITLE := Color(0.82, 0.86, 0.90, 0.9)
const COLOR_CHAPTER := Color(0.96, 0.76, 0.42, 1.0)
const OUTLINE_SIZE := 6

var _typography
var _root: Control
var _blur_rect: ColorRect
var _menu_pane: Control
var _rollback_pane: Control
var _rollback_list: VBoxContainer
var _stats_label: Label
var _rollback_button: Button
var _resume_button: Button
var _options_button: Button
var _home_button: Button
var _quit_button: Button
var _slide_tween: Tween
var _fade_tween: Tween
var _host_chapter_id := ""
var _open := false
var _rollback_open := false


func _ready() -> void:
	name = "PauseMenu"
	layer = OVERLAY_LAYER
	# 暂停期间自己还要能收输入，否则按 ESC 出不去。
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_typography = UiTypographyScript.new()
	_build_ui()
	_root.visible = false


## 宿主章节告诉它「我是哪一章」，用来判断跳转是重载还是切场景。
func setup(host_chapter_id: String) -> void:
	_host_chapter_id = host_chapter_id


# ------------------------------------------------------------------ 构建

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Overlay"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 吃掉点击，别漏到底下的玩法去。
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = _typography.theme
	add_child(_root)

	# 毛玻璃在最底下：它采样的是屏幕上已经画好的游戏画面。
	_blur_rect = ColorRect.new()
	_blur_rect.name = "Blur"
	_blur_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	_blur_rect.material = _make_screen_blur_material()
	_blur_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_blur_rect)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM_COLOR
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_menu_pane = _make_pane("MenuPane", MENU_ANCHOR_CENTER)
	_root.add_child(_menu_pane)
	_build_menu(_menu_pane)

	_rollback_pane = _make_pane("RollbackPane", ROLLBACK_ANCHOR_OFF)
	_rollback_pane.modulate.a = 0.0
	_rollback_pane.visible = false
	_root.add_child(_rollback_pane)
	_build_rollback(_rollback_pane)


## 背景毛玻璃。与 cutscene_player._make_fill_blur_material 同一套盒式模糊，
## 只是把采样源从自身贴图换成屏幕纹理——暂停时底下的画面是静止的，
## 采一次就够，不会有性能负担。
func _make_screen_blur_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_radius : hint_range(0.0, 0.02) = 0.0;

void fragment() {
	vec4 accum = vec4(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			vec2 offset = vec2(float(x), float(y)) * blur_radius / 3.0;
			float weight = 1.0 - length(vec2(float(x), float(y))) / 5.0;
			weight = max(weight, 0.02);
			accum += texture(screen_tex, SCREEN_UV + offset) * weight;
			total += weight;
		}
	}
	COLOR = accum / total;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("blur_radius", 0.0)
	return material


func _make_pane(pane_name: String, anchors: Vector2) -> Control:
	var pane := Control.new()
	pane.name = pane_name
	pane.anchor_top = 0.0
	pane.anchor_bottom = 1.0
	pane.anchor_left = anchors.x
	pane.anchor_right = anchors.y
	pane.offset_left = 0.0
	pane.offset_right = 0.0
	pane.offset_top = 0.0
	pane.offset_bottom = 0.0
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pane


func _build_menu(pane: Control) -> void:
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(center)

	var menu := VBoxContainer.new()
	menu.name = "Menu"
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation", MENU_SEPARATION)
	center.add_child(menu)

	menu.add_child(_make_title("暂停"))

	var gap := Control.new()
	gap.name = "TitleGap"
	gap.custom_minimum_size = Vector2(0.0, float(TITLE_GAP))
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(gap)

	# 场景回溯放最上面：它是这个菜单里唯一「往前走」的入口，其余三项都是退出向。
	_rollback_button = _make_menu_button("场景回溯", MENU_FONT_SIZE)
	_rollback_button.pressed.connect(_on_rollback_pressed)
	menu.add_child(_rollback_button)

	_resume_button = _make_menu_button("返回游戏", MENU_FONT_SIZE)
	_resume_button.pressed.connect(_on_resume_pressed)
	menu.add_child(_resume_button)

	# 选项先占位：显示出来但不可点，免得玩家点了没反应以为坏了。
	_options_button = _make_menu_button("选项", MENU_FONT_SIZE)
	_options_button.disabled = true
	menu.add_child(_options_button)

	_home_button = _make_menu_button("返回主页面", MENU_FONT_SIZE)
	_home_button.pressed.connect(_on_home_pressed)
	menu.add_child(_home_button)

	_quit_button = _make_menu_button("退出游戏", MENU_FONT_SIZE)
	_quit_button.pressed.connect(_on_quit_pressed)
	menu.add_child(_quit_button)


func _build_rollback(pane: Control) -> void:
	var column := VBoxContainer.new()
	column.name = "RollbackColumn"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_top = 64.0
	column.offset_bottom = -64.0
	column.offset_right = -32.0
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(column)

	column.add_child(_make_title("场景回溯"))

	_stats_label = Label.new()
	_stats_label.name = "Stats"
	_stats_label.add_theme_font_override("font", _typography.ui)
	_stats_label.add_theme_font_size_override("font_size", NODE_FONT_SIZE)
	_stats_label.add_theme_color_override("font_color", COLOR_TITLE)
	_stats_label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	_stats_label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	column.add_child(_stats_label)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_child(scroll)

	_rollback_list = VBoxContainer.new()
	_rollback_list.name = "Nodes"
	_rollback_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rollback_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_rollback_list)

	var back := _make_menu_button("返回", CHAPTER_FONT_SIZE)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_on_rollback_back_pressed)
	column.add_child(back)


func _make_title(text: String) -> Label:
	var label := Label.new()
	label.name = text
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_override("font", _typography.ui)
	label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	label.add_theme_color_override("font_color", COLOR_TITLE)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return label


## 与 opening.gd/_make_menu_button 保持一致：带暗描边的白字，悬停/聚焦只提亮不换形。
func _make_menu_button(label: String, font_size: int) -> Button:
	var button := Button.new()
	button.name = label
	button.text = label
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", _typography.ui)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_NORMAL)
	button.add_theme_color_override("font_hover_color", COLOR_HOVER)
	button.add_theme_color_override("font_focus_color", COLOR_HOVER)
	button.add_theme_color_override("font_pressed_color", COLOR_PRESSED)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	button.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	button.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	return button


# ---------------------------------------------------------------- 回溯列表

## 每次打开都重建：访问记录会在游玩过程中变，缓存了就会显示旧的 ???。
func _rebuild_rollback_list() -> void:
	for child in _rollback_list.get_children():
		child.queue_free()

	for chapter in ChapterIndexScript.chapters_with_nodes():
		var chapter_id := str(chapter["id"])
		var header := Label.new()
		header.text = str(chapter["title"])
		header.add_theme_font_override("font", _typography.ui)
		header.add_theme_font_size_override("font_size", CHAPTER_FONT_SIZE)
		header.add_theme_color_override("font_color", COLOR_CHAPTER)
		header.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
		header.add_theme_constant_override("outline_size", OUTLINE_SIZE)
		_rollback_list.add_child(header)

		for node in (chapter["nodes"] as Array):
			var source := int(node["source"])
			var visited: bool = ChapterProgress.is_visited(chapter_id, source)
			# 没走过的只露一个 ???：既不剧透，又能让玩家看见「还有几格没点亮」。
			var text := str(node["display_name"]) if visited else "???"
			var button := _make_menu_button(text, NODE_FONT_SIZE)
			button.name = "%s_%d" % [chapter_id, source]
			button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			button.disabled = not visited
			if visited:
				button.pressed.connect(_on_node_pressed.bind(chapter_id, source))
			_rollback_list.add_child(button)

	var stats: Dictionary = ChapterProgress.stats()
	_stats_label.text = "已解锁 %d / %d" % [int(stats["unlocked"]), int(stats["total"])]


# ------------------------------------------------------------------ 动效

func _slide(to_rollback: bool) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	if to_rollback:
		_rollback_pane.visible = true
	var menu_anchors := MENU_ANCHOR_LEFT if to_rollback else MENU_ANCHOR_CENTER
	var rollback_anchors := ROLLBACK_ANCHOR_ON if to_rollback else ROLLBACK_ANCHOR_OFF
	# 暂停时 tween 必须忽略暂停，否则整段动画不会走。
	_slide_tween = create_tween().set_parallel(true)
	_slide_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_slide_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide_tween.tween_property(_menu_pane, "anchor_left", menu_anchors.x, SLIDE_SECONDS)
	_slide_tween.tween_property(_menu_pane, "anchor_right", menu_anchors.y, SLIDE_SECONDS)
	_slide_tween.tween_property(_rollback_pane, "anchor_left", rollback_anchors.x, SLIDE_SECONDS)
	_slide_tween.tween_property(_rollback_pane, "anchor_right", rollback_anchors.y, SLIDE_SECONDS)
	_slide_tween.tween_property(_rollback_pane, "modulate:a", 1.0 if to_rollback else 0.0, SLIDE_SECONDS)
	if not to_rollback:
		_slide_tween.chain().tween_callback(func() -> void: _rollback_pane.visible = false)


## 测试用：跳过补间直接落到终态。
func snap_to_state(rollback_open: bool) -> void:
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	var menu_anchors := MENU_ANCHOR_LEFT if rollback_open else MENU_ANCHOR_CENTER
	var rollback_anchors := ROLLBACK_ANCHOR_ON if rollback_open else ROLLBACK_ANCHOR_OFF
	_menu_pane.anchor_left = menu_anchors.x
	_menu_pane.anchor_right = menu_anchors.y
	_menu_pane.offset_top = 0.0
	_rollback_pane.anchor_left = rollback_anchors.x
	_rollback_pane.anchor_right = rollback_anchors.y
	_rollback_pane.modulate.a = 1.0 if rollback_open else 0.0
	_rollback_pane.visible = rollback_open


# ------------------------------------------------------------------ 开关

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_ESCAPE:
		return
	# ESC 逐层退：先收回溯列表，再关整个菜单。
	if _rollback_open:
		_close_rollback()
	else:
		close()
	get_viewport().set_input_as_handled()


func open() -> void:
	if _open:
		return
	_open = true
	_root.visible = true
	get_tree().paused = true
	_rollback_button.grab_focus()


func close() -> void:
	if not _open:
		return
	if _rollback_open:
		_close_rollback()
	_open = false
	_root.visible = false
	get_tree().paused = false
	resumed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func is_open() -> bool:
	return _open


func is_rollback_open() -> bool:
	return _rollback_open


func _on_rollback_pressed() -> void:
	if _rollback_open:
		return
	_rollback_open = true
	_rebuild_rollback_list()
	_slide(true)


func _close_rollback() -> void:
	if not _rollback_open:
		return
	_rollback_open = false
	_slide(false)
	_rollback_button.grab_focus()


func _on_rollback_back_pressed() -> void:
	_close_rollback()


func _on_node_pressed(chapter_id: String, source: int) -> void:
	var events := ChapterIndexScript.events_of(chapter_id)
	var resolved := DevJumpPanelScript.resolve_source_line(events, source)
	if resolved.is_empty():
		push_warning("回溯目标解析失败：%s:%d" % [chapter_id, source])
		return
	var payload := {
		"chapter": chapter_id,
		"scene": ChapterIndexScript.scene_of(chapter_id),
		"requested_source": source,
		"actual_source": int(resolved.get("source", 0)),
		"target_index": int(resolved.get("index", -1)),
		"exact": bool(resolved.get("exact", false)),
		"from_chapter": _host_chapter_id,
		"from_source": 0,
		"same_chapter": chapter_id == _host_chapter_id,
		"requested_at": Time.get_datetime_string_from_system(),
		# 这一条把回溯和 F4 开发者跳转区分开：宿主据此决定不进 dev jump 模式。
		"rollback": true,
	}
	get_tree().root.set_meta(DevJumpPanelScript.META_KEY, payload)
	# 切场景前必须解除暂停，否则新场景一进来就是停住的。
	_open = false
	_rollback_open = false
	_root.visible = false
	get_tree().paused = false
	jump_requested.emit(payload)


func _on_resume_pressed() -> void:
	close()


func _on_home_pressed() -> void:
	# paused 是 SceneTree 级别的，不清掉会原样带进开场界面。
	_open = false
	_rollback_open = false
	_root.visible = false
	get_tree().paused = false
	# 和「开始游戏」用同一套章节转场，别再硬切回标题。
	ChapterTransitionScript.begin(get_tree(), OPENING_SCENE)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


## 供 headless 测试用。
func verify_contract() -> bool:
	return (
		_root != null
		and _menu_pane != null
		and _rollback_pane != null
		and _rollback_list != null
		and _typography != null
		and layer == OVERLAY_LAYER
		and process_mode == Node.PROCESS_MODE_WHEN_PAUSED
		and _rollback_button != null and _rollback_button.text == "场景回溯"
		and _resume_button != null and _resume_button.text == "返回游戏"
		and _options_button != null and _options_button.text == "选项" and _options_button.disabled
		and _home_button != null and _home_button.text == "返回主页面"
		and _quit_button != null and _quit_button.text == "退出游戏"
		and _resume_button.get_theme_font("font") == _typography.ui
		and ResourceLoader.exists(OPENING_SCENE)
	)


func get_menu_labels() -> PackedStringArray:
	return PackedStringArray([
		_rollback_button.text,
		_resume_button.text,
		_options_button.text,
		_home_button.text,
		_quit_button.text,
	])


## 回溯列表里每个节点按钮的 (名字, 是否可点)，测试用。
func get_rollback_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for child in _rollback_list.get_children():
		if child is Button:
			entries.append({"text": (child as Button).text, "enabled": not (child as Button).disabled})
	return entries


func get_menu_anchors() -> Vector2:
	return Vector2(_menu_pane.anchor_left, _menu_pane.anchor_right)


func get_rollback_anchors() -> Vector2:
	return Vector2(_rollback_pane.anchor_left, _rollback_pane.anchor_right)


func debug_open_rollback() -> void:
	_on_rollback_pressed()
	snap_to_state(true)


func debug_close_rollback() -> void:
	_close_rollback()
	snap_to_state(false)
