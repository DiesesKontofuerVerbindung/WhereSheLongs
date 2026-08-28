extends BaseExplorationMap

enum Phase {
	APPROACH_LIGHT,
	DARK_WAIT,
	AMAI_APPEAR,
	INTRO_DIALOGUE,
	PATH_DIALOGUE,
	WALK_CHOICE,
	DARK_LOST,
	EXIT,
	DONE,
}

const LIGHT_POS := Vector2(720, 400)
const AMAI_POS := Vector2(560, 360)
const AMAI_WALK_POS := Vector2(750, 360)

var _phase := Phase.APPROACH_LIGHT
var _dist_light: PointLight2D
var _light_marker: Node2D
var _light_hover: Area2D
var _amai: Node2D
var _fireflies: Node2D
var _light_trigger: Area2D
var _amai_trigger: Area2D
var _dark_overlay: ColorRect
var _approach_progress := 0.0
var _hovering_light := false
var _choice_layer: CanvasLayer


func _build_environment() -> void:
	set_camera_bounds(Rect2(0, 0, 1200, 540))
	_add_fill_background(Color(0.02, 0.02, 0.04), Color(0.05, 0.08, 0.06))

	_dark_overlay = ColorRect.new()
	_dark_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dark_overlay.color = Color(0, 0, 0, 0.8)
	_dark_overlay.visible = false
	_dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui := CanvasLayer.new()
	ui.layer = 50
	ui.add_child(_dark_overlay)
	add_child(ui)

	_dist_light = PointLight2D.new()
	_dist_light.position = LIGHT_POS
	_dist_light.energy = 1.2
	_dist_light.texture_scale = 4.0
	_dist_light.color = Color(0.9, 0.85, 0.6)
	add_child(_dist_light)
	_create_light_marker()

	var flicker := Timer.new()
	flicker.wait_time = 0.8
	flicker.autostart = true
	flicker.timeout.connect(_flicker_light)
	add_child(flicker)

	_light_hover = Area2D.new()
	_light_hover.position = LIGHT_POS
	_light_hover.input_pickable = true
	var hover_shape := CollisionShape2D.new()
	var hover_rect := RectangleShape2D.new()
	hover_rect.size = Vector2(180, 180)
	hover_shape.shape = hover_rect
	_light_hover.add_child(hover_shape)
	_light_hover.mouse_entered.connect(func(): _hovering_light = true)
	_light_hover.mouse_exited.connect(func(): _hovering_light = false)
	add_child(_light_hover)

	_light_trigger = Area2D.new()
	_light_trigger.position = LIGHT_POS
	_light_trigger.collision_layer = 0
	_light_trigger.collision_mask = 1
	var lt_shape := CollisionShape2D.new()
	var lt_rect := RectangleShape2D.new()
	lt_rect.size = Vector2(240, 180)
	lt_shape.shape = lt_rect
	_light_trigger.add_child(lt_shape)
	_light_trigger.body_entered.connect(_on_near_light)
	add_child(_light_trigger)

	_player.set_light_enabled(false)
	_player.global_position = Vector2(200, 400)

	var hint := Label.new()
	hint.text = "方向键 / 鼠标移到右侧光点 · 靠近光源"
	hint.position = Vector2(20, 20)
	var hint_layer := CanvasLayer.new()
	hint_layer.add_child(hint)
	add_child(hint_layer)


func _create_light_marker() -> void:
	_light_marker = Node2D.new()
	_light_marker.position = LIGHT_POS
	_light_marker.z_index = 2
	for radius in [44.0, 30.0, 16.0]:
		var ring := Polygon2D.new()
		ring.polygon = _make_circle_polygon(radius, 32)
		ring.color = Color(1.0, 0.9, 0.5, 0.15 + radius * 0.01)
		_light_marker.add_child(ring)
	add_child(_light_marker)


func _make_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _flicker_light() -> void:
	if _phase != Phase.APPROACH_LIGHT:
		return
	_dist_light.energy = randf_range(0.6, 1.4)


func _physics_process(delta: float) -> void:
	match _phase:
		Phase.APPROACH_LIGHT:
			if _hovering_light or Input.is_action_pressed("move_right"):
				_approach_progress += delta * 0.35
				_player.global_position.x = minf(_player.global_position.x + delta * 80.0, LIGHT_POS.x - 40.0)
			if _approach_progress >= 1.0 or _player.global_position.distance_to(LIGHT_POS) < 80.0:
				_on_near_light(_player)
		Phase.WALK_CHOICE:
			if Input.is_action_pressed("move_left") and _player.global_position.x < 300.0:
				_trigger_dark_lost()
			elif Input.is_action_pressed("move_right") and _player.global_position.x > 600.0:
				_on_choose_walk()


func _on_near_light(body: Node2D) -> void:
	if body != _player or _phase != Phase.APPROACH_LIGHT:
		return
	_phase = Phase.DARK_WAIT
	_light_trigger.queue_free()
	_light_trigger = null
	if _light_marker:
		_light_marker.queue_free()
		_light_marker = null
	_dist_light.visible = false
	_player.set_can_move(false)
	_dark_overlay.visible = true
	_dark_overlay.color = Color(0, 0, 0, 0.8)
	await get_tree().create_timer(2.5).timeout
	_start_amai_sequence()


func _start_amai_sequence() -> void:
	_phase = Phase.AMAI_APPEAR
	_spawn_amai()
	_dark_overlay.color = Color(0, 0, 0, 0.6)
	await get_tree().create_timer(0.5).timeout
	_show_intro_dialogue()


func _spawn_amai() -> void:
	if _amai:
		return
	_amai = Node2D.new()
	_amai.position = AMAI_POS
	var sprite := Sprite2D.new()
	sprite.texture = PlaceholderAssets.make_character_sprite(Color(0.3, 0.35, 0.55), "amai")
	sprite.position = Vector2(0, -16)
	sprite.modulate = Color(0.4, 0.4, 0.45, 1.0)
	_amai.add_child(sprite)
	var heart_light := PointLight2D.new()
	heart_light.energy = 1.0
	heart_light.texture_scale = 2.5
	heart_light.color = Color(0.8, 0.5, 0.9)
	_amai.add_child(heart_light)
	add_child(_amai)


func _show_intro_dialogue() -> void:
	_phase = Phase.INTRO_DIALOGUE
	_show_inline_dialogue([
		{"speaker": "小凌", "text": "（心理：警觉）这是什么地方。"},
		{"speaker": "阿麦", "text": "你想让这里是什么地方，这里就是什么地方。"},
		{"speaker": "旁白", "text": "这里的树并不是笔直冲天的，每棵树以奇怪的方式和其他树错综复杂地交织着。脚边的地上铺满了腐叶，有类似刺猬的小动物从她脚边跑过，远处……小凌眨了眨眼，光太暗了，远处看不清"},
		{"speaker": "阿麦", "text": "（动作：冲着远处做了个手势，萤火虫样的生物向远处排成一排，亮起一排灯指明了道路）"},
	], _show_path_dialogue)


func _show_path_dialogue() -> void:
	_reveal_forest()
	_spawn_fireflies()
	_dark_overlay.visible = false
	_phase = Phase.PATH_DIALOGUE
	_show_inline_dialogue([
		{"speaker": "阿麦", "text": "走吧。"},
		{"speaker": "小凌", "text": "去哪儿？"},
		{"speaker": "旁白", "text": "阿麦没有回答，也没有看她，径直往前走"},
		{"speaker": "小凌", "text": "我又不知道你是谁，我为什么要跟你去。"},
		{"speaker": "旁白", "text": "阿麦站住，终于回过头看她。"},
		{"speaker": "旁白", "text": "阿麦的脸颊在黑暗下棱角分明，但你仍然看不清他的脸。"},
		{"speaker": "旁白", "text": "（动作：只是抬起手，轻轻做了另一个手势）"},
		{"speaker": "旁白", "text": "刚才排成一列的萤火虫忽然散开，向森林深处飞去。黑暗重新合拢，只有一颗萤火虫停在你面前，微弱地闪烁着。"},
		{"speaker": "阿麦", "text": "你说得对。"},
		{"speaker": "小凌", "text": "（心理：有些意外）"},
		{"speaker": "阿麦", "text": "你不应该跟一个不知道是谁的人走。"},
		{"speaker": "小凌", "text": "那你还让我跟你走？"},
		{"speaker": "旁白", "text": "（动作：笑）"},
		{"speaker": "阿麦", "text": "我只是带路。"},
		{"speaker": "旁白", "text": "他转过身，萤火虫重新排列成一条线，阿麦沿着萤火虫照亮的小路慢慢往前走。走了几步，他停下来，没有回头。"},
		{"speaker": "阿麦", "text": "你可以不跟。"},
		{"speaker": "旁白", "text": "森林里又传来窸窸窣窣的声音。树枝上，一只眼睛圆溜溜的小动物探出脑袋，好奇地看着她。森林深处似乎有水源的痕迹，有什么东西在水里扑腾了一下。"},
		{"speaker": "小凌", "text": "（动作：看着他的背影）"},
		{"speaker": "小凌", "text": "（心理：不知道为什么，她突然觉得——这个地方好像没有人在催她。没有人告诉她应该去哪。也没有人告诉她，这条路才是正确的。）"},
		{"speaker": "小凌", "text": "（心理：犹豫…）"},
	], _show_walk_choice)


func _reveal_forest() -> void:
	var trees := Node2D.new()
	for i in range(8):
		var t := Sprite2D.new()
		t.texture = PlaceholderAssets.make_color_texture(Color(0.08, 0.12, 0.08), Vector2i(24, 80))
		t.position = Vector2(100 + i * 100, 320 + randi_range(-20, 20))
		trees.add_child(t)
	add_child(trees)


func _show_walk_choice() -> void:
	_phase = Phase.WALK_CHOICE
	_player.set_can_move(true)
	if _amai:
		_amai.position = AMAI_WALK_POS
	_choice_layer = CanvasLayer.new()
	add_child(_choice_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -120
	panel.offset_bottom = -20
	_choice_layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "【走 / 不走？】按 → 走向阿麦，按 ← 离开"
	box.add_child(title)
	var walk_btn := Button.new()
	walk_btn.text = "走"
	walk_btn.pressed.connect(_on_choose_walk)
	box.add_child(walk_btn)
	var stay_btn := Button.new()
	stay_btn.text = "不走"
	stay_btn.pressed.connect(_trigger_dark_lost)
	box.add_child(stay_btn)


func _trigger_dark_lost() -> void:
	if _phase != Phase.WALK_CHOICE:
		return
	_phase = Phase.DARK_LOST
	_player.set_can_move(false)
	if _choice_layer:
		_choice_layer.queue_free()
		_choice_layer = null
	_dark_overlay.visible = true
	_dark_overlay.color = Color(0, 0, 0, 0.92)
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "重新陷入黑暗"},
		{"speaker": "旁白", "text": "森林入口不复存在"},
	], _retry_walk_choice)


func _retry_walk_choice() -> void:
	_dark_overlay.visible = false
	_player.global_position = Vector2(480, 400)
	_show_walk_choice()


func _on_choose_walk() -> void:
	if _phase != Phase.WALK_CHOICE and _phase != Phase.DARK_LOST:
		return
	_phase = Phase.EXIT
	if _choice_layer:
		_choice_layer.queue_free()
		_choice_layer = null
	_player.set_can_move(false)
	_complete({"result": "success"})


func _spawn_fireflies() -> void:
	_fireflies = Node2D.new()
	for i in range(12):
		var p := PointLight2D.new()
		p.position = Vector2(300 + i * 40, 350 + sin(i * 0.5) * 20)
		p.energy = 0.4
		p.texture_scale = 0.8
		p.color = Color(0.7, 0.9, 0.4)
		_fireflies.add_child(p)
	add_child(_fireflies)


func _on_reach_amai(body: Node2D) -> void:
	pass
