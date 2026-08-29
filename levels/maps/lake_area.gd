extends BaseExplorationMap

var _choice_layer: CanvasLayer


func _build_environment() -> void:
	set_camera_bounds(Rect2(0, 0, 960, 540))
	_add_fill_background(Color(0.03, 0.02, 0.08), Color(0.08, 0.03, 0.12))
	var lake := Polygon2D.new()
	lake.polygon = PackedVector2Array([Vector2(80, 330), Vector2(880, 330), Vector2(960, 540), Vector2(0, 540)])
	lake.color = Color(0.12, 0.18, 0.42, 0.7)
	lake.z_index = -5
	add_child(lake)
	_player.global_position = Vector2(200, 420)
	GameState.set_checkpoint("part3_stone_jump", "lake_area", Vector2(200, 420))
	await get_tree().process_frame
	_start_lake_intro()


func _start_lake_intro() -> void:
	_player.set_can_move(false)
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "阿麦走到岸边。"},
		{"speaker": "小凌", "text": "你干什么？"},
		{"speaker": "旁白", "text": "阿麦没有回答。他踩上一块石头。再跳到下一块。轻轻松松地到了湖面中央。"},
		{"speaker": "小凌", "text": "那里很滑。"},
		{"speaker": "旁白", "text": "（动作：回头。）"},
		{"speaker": "阿麦", "text": "所以呢？"},
		{"speaker": "小凌", "text": "会掉下去。"},
		{"speaker": "阿麦", "text": "那就掉下去。"},
		{"speaker": "小凌", "text": "……"},
		{"speaker": "旁白", "text": "（动作：站在水中央，张开双臂。）"},
		{"speaker": "阿麦", "text": "你不想试试吗？"},
	], _show_try_choice)


func _show_try_choice() -> void:
	_choice_layer = CanvasLayer.new()
	add_child(_choice_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = -100
	panel.offset_bottom = -20
	_choice_layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var want_btn := Button.new()
	want_btn.text = "想"
	want_btn.pressed.connect(_on_want_try)
	box.add_child(want_btn)
	var no_btn := Button.new()
	no_btn.text = "不想"
	no_btn.pressed.connect(_on_dont_want)
	box.add_child(no_btn)


func _clear_choice() -> void:
	if _choice_layer:
		_choice_layer.queue_free()
		_choice_layer = null


func _on_want_try() -> void:
	_clear_choice()
	_complete({"result": "success"})


func _on_dont_want() -> void:
	_clear_choice()
	_show_inline_dialogue([
		{"speaker": "小凌", "text": "不想。"},
		{"speaker": "阿麦", "text": "真的？"},
		{"speaker": "小凌", "text": "真的。"},
		{"speaker": "旁白", "text": "阿麦突然跳进水里。"},
		{"speaker": "旁白", "text": "“扑通。”"},
		{"speaker": "旁白", "text": "下一秒——阿麦从水里冒出来，头发湿漉漉地贴在脸上"},
		{"speaker": "阿麦", "text": "不来试试吗？"},
		{"speaker": "旁白", "text": "小凌看着他，踏入了湖里。"},
	], func(): _complete({"result": "success"}))
