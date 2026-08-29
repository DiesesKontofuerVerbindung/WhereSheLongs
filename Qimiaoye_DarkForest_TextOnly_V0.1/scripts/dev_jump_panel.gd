extends ColorRect

## 开发者 DOCX 行回溯面板（双章节）。
##
## 森林正片和婚礼前段各有独立的事件表和独立的 DOCX 行号空间，但回溯这件事
## 是同一件事：输入行号 → 找到该行或其后第一条事件 → 带 payload 重进场景。
## 所以 UI、行号解析和跨场景 payload 协议都收在这里，章节由宿主注册进来，
## 面板本身不认识任何剧情内容。
##
## 同章节跳转走 reload_current_scene()，跨章节走 change_scene_to_file()；
## 两种都由宿主在 jump_requested 里执行，因为只有宿主知道自己的日志怎么写。

const META_KEY := "qimiaoye_dark_forest_dev_docx_jump"

const COLOR_TITLE := Color(0.96, 0.76, 0.42, 1.0)
const COLOR_TEXT := Color(0.88, 0.90, 0.94, 1.0)
const COLOR_MUTED := Color(0.62, 0.66, 0.74, 1.0)
const COLOR_ACCENT := Color(0.72, 0.86, 0.98, 1.0)

signal jump_requested(payload: Dictionary)

var _chapters: Array[Dictionary] = []
var _host_chapter_id := ""
var _selected_index := 0
## 宿主每次刷新时告诉面板它当前停在哪一行，submit 时写进 payload 的 from_source。
var _host_current_source := 0

var _tab_bar: TabBar
var _help_label: Label
var _range_label: Label
var _input: LineEdit
var _jump_button: Button
var _feedback: Label


## 章节描述：
##   id     章节标识，跨场景 payload 用它区分目标
##   title  tab 标题
##   scene  该章节的场景路径，跨章节跳转时 change_scene_to_file 的目标
##   events 事件表，用来解析 DOCX 行号
##   hint   说明文字
func setup(chapters: Array[Dictionary], host_chapter_id: String) -> void:
	_chapters = chapters
	_host_chapter_id = host_chapter_id
	_build_ui()
	var host_index := _index_of_chapter(host_chapter_id)
	_selected_index = maxi(0, host_index)
	_tab_bar.current_tab = _selected_index


func _build_ui() -> void:
	name = "DeveloperDocxJumpOverlay"
	color = Color(0.01, 0.015, 0.025, 0.88)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	visible = false

	var panel := PanelContainer.new()
	panel.name = "DeveloperDocxJumpPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -200
	panel.offset_bottom = 200
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("0b0f17fa")
	panel_style.border_color = Color("f4c36ad0")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.text = "开发者功能 · DOCX 行回溯"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	col.add_child(title)

	_tab_bar = TabBar.new()
	_tab_bar.name = "DeveloperDocxJumpTabs"
	_tab_bar.tab_alignment = TabBar.ALIGNMENT_CENTER
	_tab_bar.add_theme_font_size_override("font_size", 17)
	for chapter in _chapters:
		_tab_bar.add_tab(str(chapter.get("title", chapter.get("id", "章节"))))
	_tab_bar.tab_changed.connect(_on_tab_changed)
	col.add_child(_tab_bar)

	_help_label = Label.new()
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.add_theme_font_size_override("font_size", 15)
	_help_label.add_theme_color_override("font_color", COLOR_TEXT)
	col.add_child(_help_label)

	_range_label = Label.new()
	_range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_range_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_range_label.add_theme_font_size_override("font_size", 14)
	_range_label.add_theme_color_override("font_color", COLOR_MUTED)
	col.add_child(_range_label)

	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 12)
	col.add_child(input_row)

	_input = LineEdit.new()
	_input.name = "DeveloperDocxLineInput"
	_input.custom_minimum_size = Vector2(300, 46)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", 20)
	_input.text_changed.connect(_on_text_changed)
	_input.text_submitted.connect(_on_text_submitted)
	input_row.add_child(_input)

	_jump_button = Button.new()
	_jump_button.name = "DeveloperDocxJumpButton"
	_jump_button.text = "从此行开始"
	_jump_button.custom_minimum_size = Vector2(170, 46)
	_jump_button.pressed.connect(submit)
	input_row.add_child(_jump_button)

	_feedback = Label.new()
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.add_theme_font_size_override("font_size", 15)
	_feedback.add_theme_color_override("font_color", COLOR_ACCENT)
	_feedback.custom_minimum_size.y = 46
	col.add_child(_feedback)

	var close_button := Button.new()
	close_button.text = "取消 · Esc / F4"
	close_button.custom_minimum_size = Vector2(210, 38)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close_panel)
	col.add_child(close_button)


func open_panel(current_source: int) -> void:
	if _input == null:
		return
	visible = true
	_selected_index = _tab_bar.current_tab
	var chapter := _current_chapter()
	var bounds := source_bounds(_chapter_events(chapter))
	# 回到宿主章节的 tab 时默认填当前行，跨章节时默认填该章节的第一行。
	var suggested := current_source if (current_source > 0 and str(chapter.get("id", "")) == _host_chapter_id) else bounds.x
	_input.text = str(suggested)
	_input.select_all()
	_input.grab_focus()
	refresh_preview(current_source)


func close_panel() -> void:
	visible = false
	if _input != null:
		_input.release_focus()


func refresh_preview(current_source: int) -> void:
	if current_source > 0:
		_host_current_source = current_source
	if _input == null or _jump_button == null or _feedback == null:
		return
	var chapter := _current_chapter()
	var events := _chapter_events(chapter)
	var bounds := source_bounds(events)
	var is_host := str(chapter.get("id", "")) == _host_chapter_id
	_help_label.text = str(chapter.get("hint", ""))
	var current_text := "—（当前不在本章）"
	if is_host:
		current_text = str(current_source) if current_source > 0 else "等待启动"
	_range_label.text = "当前 DOCX 行：%s　|　%s 可跳转范围：%d–%d　|　F4 打开/关闭" % [
		current_text,
		str(chapter.get("title", "")),
		bounds.x,
		bounds.y,
	]
	var raw := _input.text.strip_edges()
	if raw.is_empty():
		_feedback.text = "请输入一个 DOCX 行号。"
		_jump_button.disabled = true
		return
	if not raw.is_valid_int() or int(raw) <= 0:
		_feedback.text = "行号必须是正整数。"
		_jump_button.disabled = true
		return
	var requested_source := int(raw)
	var resolved := resolve_source_line(events, requested_source)
	if resolved.is_empty():
		_feedback.text = "第 %d 行之后没有剧情事件；最后一个来源行是 %d。" % [requested_source, bounds.y]
		_jump_button.disabled = true
		return
	var actual_source := int(resolved.get("source", 0))
	var event: Dictionary = resolved.get("event", {})
	var event_id := event_debug_id(event)
	var prefix := "" if is_host else "切到《%s》　" % str(chapter.get("title", ""))
	if bool(resolved.get("exact", false)):
		_feedback.text = "%s精确落点：DOCX 第 %d 行 · %s / %s" % [prefix, actual_source, event.get("type", ""), event_id]
	else:
		_feedback.text = "%s第 %d 行没有事件，将从下一条：DOCX 第 %d 行 · %s / %s 开始" % [
			prefix,
			requested_source,
			actual_source,
			event.get("type", ""),
			event_id,
		]
	_jump_button.disabled = false


## 组装 payload、写进 root meta 并发信号。真正的场景切换交给宿主。
func submit() -> void:
	if _input == null:
		return
	var from_source := _host_current_source
	var raw := _input.text.strip_edges()
	if not raw.is_valid_int() or int(raw) <= 0:
		refresh_preview(from_source)
		return
	var chapter := _current_chapter()
	var events := _chapter_events(chapter)
	var requested_source := int(raw)
	var resolved := resolve_source_line(events, requested_source)
	if resolved.is_empty():
		refresh_preview(from_source)
		return
	var target_chapter := str(chapter.get("id", ""))
	var payload := {
		"chapter": target_chapter,
		"scene": str(chapter.get("scene", "")),
		"requested_source": requested_source,
		"actual_source": int(resolved.get("source", 0)),
		"target_index": int(resolved.get("index", -1)),
		"exact": bool(resolved.get("exact", false)),
		"from_chapter": _host_chapter_id,
		"from_source": from_source,
		"same_chapter": target_chapter == _host_chapter_id,
		"requested_at": Time.get_datetime_string_from_system(),
	}
	get_tree().root.set_meta(META_KEY, payload)
	_jump_button.disabled = true
	_feedback.text = "正在跳转到《%s》DOCX 第 %d 行……" % [
		str(chapter.get("title", "")),
		int(payload["actual_source"]),
	]
	jump_requested.emit(payload)


func report_jump_failure(message: String) -> void:
	if _jump_button != null:
		_jump_button.disabled = false
	if _feedback != null:
		_feedback.text = message


func is_open() -> bool:
	return visible


## 面板结构完整、双章节都注册上了、而且每个章节的事件表都能解析出行号范围。
func verify_contract() -> bool:
	if _tab_bar == null or _input == null or _jump_button == null or _feedback == null:
		return false
	if _chapters.size() < 2 or _tab_bar.tab_count != _chapters.size():
		return false
	if _index_of_chapter(_host_chapter_id) < 0:
		return false
	for chapter in _chapters:
		if str(chapter.get("scene", "")).is_empty():
			return false
		if source_bounds(_chapter_events(chapter)) == Vector2i.ZERO:
			return false
	return true


func get_chapter_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for chapter in _chapters:
		ids.append(str(chapter.get("id", "")))
	return ids


func select_chapter(chapter_id: String) -> bool:
	var index := _index_of_chapter(chapter_id)
	if index < 0:
		return false
	_tab_bar.current_tab = index
	return true


func set_input_text(text: String) -> void:
	if _input != null:
		_input.text = text


func has_focus_on_input() -> bool:
	return _input != null and _input.has_focus()


func _on_text_changed(_new_text: String) -> void:
	refresh_preview(_host_current_source)


func _on_text_submitted(_submitted_text: String) -> void:
	submit()


func _on_tab_changed(tab_index: int) -> void:
	_selected_index = tab_index
	var chapter := _current_chapter()
	var bounds := source_bounds(_chapter_events(chapter))
	if _input != null:
		_input.text = str(bounds.x)
	refresh_preview(0)


func _current_chapter() -> Dictionary:
	if _chapters.is_empty():
		return {}
	return _chapters[clampi(_selected_index, 0, _chapters.size() - 1)]


func _chapter_events(chapter: Dictionary) -> Array:
	var events = chapter.get("events", [])
	return events if events is Array else []


func _index_of_chapter(chapter_id: String) -> int:
	for i in range(_chapters.size()):
		if str(_chapters[i].get("id", "")) == chapter_id:
			return i
	return -1


## 从 root meta 取出并清掉待处理的跳转。目标章节不是 self_chapter_id 时返回空，
## 让 payload 留给真正的目标场景消费。
static func take_pending_jump(root: Window, self_chapter_id: String) -> Dictionary:
	if root == null or not root.has_meta(META_KEY):
		return {}
	var raw = root.get_meta(META_KEY)
	if typeof(raw) != TYPE_DICTIONARY:
		root.remove_meta(META_KEY)
		return {}
	var payload: Dictionary = raw
	# 没有 chapter 字段的是旧版 payload，按森林处理。
	var target_chapter := str(payload.get("chapter", "forest"))
	if target_chapter != self_chapter_id:
		return {}
	root.remove_meta(META_KEY)
	return payload.duplicate(true)


static func source_bounds(events: Array) -> Vector2i:
	var min_source := 2147483647
	var max_source := 0
	for event in events:
		var source := int(event.get("source", 0))
		if source <= 0:
			continue
		min_source = mini(min_source, source)
		max_source = maxi(max_source, source)
	if max_source == 0:
		return Vector2i.ZERO
	return Vector2i(min_source, max_source)


static func resolve_source_line(events: Array, requested_source: int) -> Dictionary:
	if requested_source <= 0:
		return {}
	var best_index := -1
	var best_source := 2147483647
	for i in range(events.size()):
		var event: Dictionary = events[i]
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
		"event": events[best_index],
	}


static func event_debug_id(event: Dictionary) -> String:
	return str(event.get("id", event.get("name", event.get("type", "event"))))
