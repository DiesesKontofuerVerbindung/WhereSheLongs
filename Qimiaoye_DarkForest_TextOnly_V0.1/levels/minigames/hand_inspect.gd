extends Control

signal finished(result: Dictionary)

const VIEW_SIZE := Vector2(1280.0, 720.0)
const HOTSPOT_IDS: Array[String] = ["ring", "palm_lines", "scar"]

const COLOR_BG := Color("05070c")
const COLOR_PANEL := Color("111827f2")
const COLOR_BORDER := Color("7598b8")
const COLOR_TEXT := Color("edf1f7")
const COLOR_MUTED := Color("9aa8ba")
const COLOR_ACCENT := Color("a8d8ff")
const COLOR_HAND := Color("3a4250")
const COLOR_HAND_SHADE := Color("2a313c")
const COLOR_HOTSPOT := Color("a8d8ff")
const COLOR_HOTSPOT_DONE := Color("74dab5")

const SPOT_TITLES := {
	"ring": "戒指",
	"palm_lines": "掌纹",
	"scar": "伤疤",
}
const SPOT_DETAIL := {
	"ring": "一枚旧戒指，内壁刻着早已磨平的字母。",
	"palm_lines": "掌纹交叠如旧路，有一道分叉偏离了所有人。",
	"scar": "腕间一道浅疤，形状像被谁轻轻攥过。",
}

# Normalized (0..1) hotspot rects in logical space; multiplied by size at runtime.
# Geometry derived from _draw_hand() at size 1280x720 (cx=640, cy=374.4, palm_w=256, palm_h=216):
#   palm body:        x 0.40..0.60, y 0.37..0.61
#   shade/wrist band: x 0.404..0.596, y 0.610..0.646
#   fingers (4):       base y 0.37, tip y 0.205; width ~0.024 at base (~0.020 at tip),
#                      centers x 0.432 / 0.476 / 0.520 / 0.564  (fx = cx - palm_w*0.34 + i*palm_w*0.22)
#   thumb (left):      x 0.396..0.456, y 0.430..0.484
# ring       -> a finger (drawn above palm); rect sits on finger ~0.50..0.59 wide, y 0.24..0.38
# palm_lines -> palm body; rect fully inside palm (x 0.42..0.58, y 0.44..0.56)
# scar       -> wrist/heel of hand (palm-bottom + shade band), y 0.58..0.66, on the drawn hand near wrist
const NORM_RECTS := {
	"ring": Rect2(0.49, 0.24, 0.10, 0.14),
	"palm_lines": Rect2(0.42, 0.44, 0.16, 0.12),
	"scar": Rect2(0.44, 0.58, 0.12, 0.065),
}

var _source := 353
var _event: Dictionary = {}
var _inspected: Dictionary = {}  # spot_id -> bool
var _emit_count := 0
var _finished_emitted := false
var _hotspot_rects: Dictionary = {}  # spot_id -> Rect2 in pixel space
var _hotspot_nodes: Dictionary = {}  # spot_id -> Control
var _status_label: Label
var _detail_label: Label
var _finish_button: Button


func setup(event: Dictionary) -> void:
	_event = event if event != null else {}
	_source = int(_event.get("source", 353))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = VIEW_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = COLOR_BG
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var title := Label.new()
	title.name = "TitleLabel"
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -500.0
	title.offset_right = 500.0
	title.offset_top = 48.0
	title.offset_bottom = 96.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", COLOR_MUTED)
	title.add_theme_font_size_override("font_size", 26)
	title.text = "小凌握着那只手，借着微光仔细看。"
	add_child(title)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status_label.offset_left = -560.0
	_status_label.offset_right = 560.0
	_status_label.offset_top = -88.0
	_status_label.offset_bottom = -40.0
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_color_override("font_color", COLOR_TEXT)
	_status_label.add_theme_font_size_override("font_size", 19)
	_status_label.text = "看清三处细节：戒指、掌纹、伤疤。"
	add_child(_status_label)

	_detail_label = Label.new()
	_detail_label.name = "DetailLabel"
	_detail_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_label.add_theme_color_override("font_color", COLOR_TEXT)
	_detail_label.add_theme_font_size_override("font_size", 19)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.text = "借着微光，看看这只手的三个细节。"
	add_child(_detail_label)

	_finish_button = Button.new()
	_finish_button.name = "FinishButton"
	_finish_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_finish_button.text = "看清楚了"
	_finish_button.disabled = true
	_finish_button.pressed.connect(request_finish)
	add_child(_finish_button)

	_build_hotspots()
	resized.connect(_on_resized)
	_on_resized()
	queue_redraw()


func _build_hotspots() -> void:
	for id in HOTSPOT_IDS:
		var spot := Control.new()
		spot.name = "Hotspot_" + id
		spot.mouse_filter = Control.MOUSE_FILTER_STOP
		spot.gui_input.connect(_on_hotspot_input.bind(id))
		add_child(spot)
		_hotspot_nodes[id] = spot


func _on_resized() -> void:
	_hotspot_rects.clear()
	for id in HOTSPOT_IDS:
		var r: Rect2 = NORM_RECTS[id]
		var rect := Rect2(r.position * size, r.size * size)
		_hotspot_rects[id] = rect
		var node := _hotspot_nodes.get(id, null) as Control
		if node != null:
			# 锚点归到左上角，offset 即绝对像素矩形，避免 FULL_RECT 把
			# anchor=1 的父尺寸叠加进来导致点击区域膨胀到几乎全屏。
			node.set_anchors_preset(Control.PRESET_TOP_LEFT)
			node.offset_left = rect.position.x
			node.offset_top = rect.position.y
			node.offset_right = rect.end.x
			node.offset_bottom = rect.end.y

	var detail_rect := Rect2(Vector2(size.x * 0.30, size.y * 0.30), Vector2(size.x * 0.40, size.y * 0.34))
	_detail_label.offset_left = detail_rect.position.x
	_detail_label.offset_top = detail_rect.position.y
	_detail_label.offset_right = detail_rect.end.x
	_detail_label.offset_bottom = detail_rect.end.y

	var btn_w := size.x * 0.16
	var btn_h := size.y * 0.07
	var btn_x := (size.x - btn_w) * 0.5
	var btn_y := size.y * 0.88
	_finish_button.offset_left = btn_x
	_finish_button.offset_top = btn_y
	_finish_button.offset_right = btn_x + btn_w
	_finish_button.offset_bottom = btn_y + btn_h
	queue_redraw()


func _on_hotspot_input(event: InputEvent, spot_id: String) -> void:
	if _finished_emitted:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		inspect_spot(spot_id)


func inspect_spot(spot_id: String) -> bool:
	if _finished_emitted:
		return false
	if not (spot_id in HOTSPOT_IDS):
		return false
	if _inspected.has(spot_id) and _inspected[spot_id]:
		return false
	_inspected[spot_id] = true
	_refresh_status()
	queue_redraw()
	return true


func _refresh_status() -> void:
	if _status_label == null:
		return
	if is_complete():
		_status_label.add_theme_color_override("font_color", COLOR_ACCENT)
		_status_label.text = "三处都看清了。那只手，好像属于很久以前的人。"
	else:
		var remaining := 3 - get_inspect_count()
		_status_label.add_theme_color_override("font_color", COLOR_TEXT)
		_status_label.text = "还有 %d 处没看清。" % remaining

	if _finish_button != null:
		_finish_button.disabled = not is_complete()

	if _detail_label != null:
		var lines := PackedStringArray()
		for id in HOTSPOT_IDS:
			var done: bool = _inspected.has(id) and bool(_inspected[id])
			if done:
				var title: String = SPOT_TITLES.get(id, "")
				var detail: String = SPOT_DETAIL.get(id, "")
				lines.append("【%s】%s" % [title, detail])
		if lines.is_empty():
			_detail_label.text = "借着微光，看看这只手的三个细节。"
		else:
			_detail_label.text = "\n".join(lines)


func get_inspected_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in HOTSPOT_IDS:
		if _inspected.has(id) and _inspected[id]:
			out.append(id)
	return out


func get_inspect_count() -> int:
	return get_inspected_ids().size()


func is_complete() -> bool:
	return get_inspect_count() >= HOTSPOT_IDS.size()


func can_finish() -> bool:
	return is_complete()


func request_finish() -> bool:
	if _finished_emitted:
		return false
	if not is_complete():
		return false
	_finished_emitted = true
	_emit_count += 1
	finished.emit({
		"result": "success",
		"inspected": Array(get_inspected_ids()),
		"source": _source,
		"spot_count": get_inspect_count(),
	})
	return true


func get_hotspot_rects() -> Dictionary:
	return _hotspot_rects.duplicate()


func get_source() -> int:
	return _source


func get_emit_count() -> int:
	return _emit_count


func verify_contract() -> bool:
	if _status_label == null:
		return false
	if _hotspot_nodes.size() != HOTSPOT_IDS.size():
		return false
	if _hotspot_rects.size() != HOTSPOT_IDS.size():
		return false
	for id in HOTSPOT_IDS:
		var rect: Variant = _hotspot_rects.get(id, null)
		if rect == null or not (rect is Rect2):
			return false
		if rect.position.x < -0.5 or rect.position.y < -0.5:
			return false
		if rect.end.x > size.x + 0.5 or rect.end.y > size.y + 0.5:
			return false
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			return false
		if not _hotspot_nodes.has(id):
			return false
	return true


func _draw() -> void:
	_draw_hand()
	for id in HOTSPOT_IDS:
		var rect: Rect2 = _hotspot_rects.get(id, Rect2())
		if rect == Rect2():
			continue
		var done: bool = _inspected.has(id) and bool(_inspected[id])
		var center := rect.get_center()
		var radius := minf(rect.size.x, rect.size.y) * 0.42
		var base_color := COLOR_HOTSPOT if not done else COLOR_HOTSPOT_DONE
		draw_arc(center, radius, 0.0, TAU, 48, base_color * Color(1, 1, 1, 0.5), 2.0, true)
		draw_arc(center, radius * 0.55, 0.0, TAU, 40, base_color * Color(1, 1, 1, 0.28), 1.0, true)
		if done:
			var tri := PackedVector2Array([
				center + Vector2(-radius * 0.28, 0.0),
				center + Vector2(-radius * 0.04, radius * 0.24),
				center + Vector2(radius * 0.34, -radius * 0.24),
			])
			draw_colored_polygon(tri, base_color * Color(1, 1, 1, 0.9))


func _draw_hand() -> void:
	var cx := size.x * 0.5
	var cy := size.y * 0.52
	var palm_w := size.x * 0.20
	var palm_h := size.y * 0.30
	var palm := PackedVector2Array([
		Vector2(cx - palm_w * 0.5, cy - palm_h * 0.5),
		Vector2(cx + palm_w * 0.5, cy - palm_h * 0.5),
		Vector2(cx + palm_w * 0.52, cy + palm_h * 0.30),
		Vector2(cx - palm_w * 0.52, cy + palm_h * 0.30),
	])
	draw_colored_polygon(palm, COLOR_HAND)
	var shade := PackedVector2Array([
		Vector2(cx - palm_w * 0.52, cy + palm_h * 0.30),
		Vector2(cx + palm_w * 0.52, cy + palm_h * 0.30),
		Vector2(cx + palm_w * 0.48, cy + palm_h * 0.42),
		Vector2(cx - palm_w * 0.48, cy + palm_h * 0.42),
	])
	draw_colored_polygon(shade, COLOR_HAND_SHADE)
	var finger_len := palm_h * 0.55
	for i in range(4):
		var fx := cx - palm_w * 0.34 + float(i) * palm_w * 0.22
		var fy := cy - palm_h * 0.5
		var finger := PackedVector2Array([
			Vector2(fx - palm_w * 0.06, fy),
			Vector2(fx + palm_w * 0.06, fy),
			Vector2(fx + palm_w * 0.05, fy - finger_len),
			Vector2(fx - palm_w * 0.05, fy - finger_len),
		])
		draw_colored_polygon(finger, COLOR_HAND)
	var thumb := PackedVector2Array([
		Vector2(cx - palm_w * 0.52, cy - palm_h * 0.08),
		Vector2(cx - palm_w * 0.30, cy - palm_h * 0.12),
		Vector2(cx - palm_w * 0.26, cy - palm_h * 0.30),
		Vector2(cx - palm_w * 0.50, cy - palm_h * 0.22),
	])
	draw_colored_polygon(thumb, COLOR_HAND)
