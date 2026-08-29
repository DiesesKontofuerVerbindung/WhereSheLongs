extends BaseExplorationMap

enum Phase { DARK, LIGHT_GONE, AMAI_APPEAR, PLANT, FIREFLIES, FREE_ROAM, DONE }

var _phase := Phase.DARK
var _dist_light: PointLight2D
var _light_marker: Node2D
var _amai: Node2D
var _fireflies: Node2D
var _light_trigger: Area2D
var _amai_trigger: Area2D
var _cricket_audio := true


func _build_environment() -> void:
	set_camera_bounds(Rect2(0, 0, 1200, 540))
	_add_fill_background(Color(0.02, 0.02, 0.04), Color(0.05, 0.08, 0.06))

	# Goal light on the player's route. Keep it aligned with the spawn lane and
	# inside the fixed 960x540 camera view so the player can clearly reach it.
	_dist_light = PointLight2D.new()
	_dist_light.position = Vector2(720, 400)
	_dist_light.energy = 1.2
	_dist_light.texture_scale = 4.0
	_dist_light.color = Color(0.9, 0.85, 0.6)
	add_child(_dist_light)
	_create_light_marker()

	# Flicker timer
	var flicker := Timer.new()
	flicker.wait_time = 0.8
	flicker.autostart = true
	flicker.timeout.connect(_flicker_light)
	add_child(flicker)

	# Light approach trigger
	_light_trigger = Area2D.new()
	_light_trigger.position = Vector2(720, 400)
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

	# Hint label
	var hint := Label.new()
	hint.text = "方向键移动 · 走向右侧的光"
	hint.position = Vector2(20, 20)
	var hint_layer := CanvasLayer.new()
	hint_layer.add_child(hint)
	add_child(hint_layer)


func _create_light_marker() -> void:
	_light_marker = Node2D.new()
	_light_marker.position = _dist_light.position
	_light_marker.z_index = 2

	# PointLight2D requires a texture to render, so use layered polygons for a
	# guaranteed visible beacon in the dark scene.
	var outer := Polygon2D.new()
	outer.polygon = _make_circle_polygon(44.0, 32)
	outer.color = Color(1.0, 0.82, 0.25, 0.22)
	_light_marker.add_child(outer)

	var mid := Polygon2D.new()
	mid.polygon = _make_circle_polygon(30.0, 32)
	mid.color = Color(1.0, 0.9, 0.45, 0.55)
	_light_marker.add_child(mid)

	var core := Polygon2D.new()
	core.polygon = _make_circle_polygon(16.0, 24)
	core.color = Color(1.0, 0.98, 0.8, 1.0)
	_light_marker.add_child(core)
	add_child(_light_marker)


func _make_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points


func _flicker_light() -> void:
	if _phase != Phase.DARK:
		return
	_dist_light.energy = randf_range(0.6, 1.4)


func _on_near_light(body: Node2D) -> void:
	if body != _player or _phase != Phase.DARK:
		return
	_phase = Phase.LIGHT_GONE
	_light_trigger.queue_free()
	if _light_marker:
		_light_marker.queue_free()
	_start_amai_sequence()


func _start_amai_sequence() -> void:
	_player.set_can_move(false)
	_dist_light.visible = false
	await get_tree().create_timer(1.0).timeout
	await CGManager.show_cg("amai_first_appear")
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "小凌走近，那束光突然消失了。周围一片漆黑。什么声音也没有。"},
		{"speaker": "旁白", "text": "……"},
		{"speaker": "旁白", "text": "阿麦站起身，一束微弱的光从他的心脏发出照亮了周围"},
		{"speaker": "阿麦", "text": "欢迎光临。"},
	], _on_amai_welcome)


func _on_amai_welcome() -> void:
	_spawn_amai()
	_spawn_plant_event()


func _spawn_amai() -> void:
	_amai = Node2D.new()
	_amai.position = Vector2(560, 360)
	var sprite := Sprite2D.new()
	sprite.texture = PlaceholderAssets.make_character_sprite(Color(0.3, 0.35, 0.55), "amai")
	sprite.position = Vector2(0, -16)
	_amai.add_child(sprite)
	var heart_light := PointLight2D.new()
	heart_light.energy = 1.0
	heart_light.texture_scale = 2.5
	heart_light.color = Color(0.8, 0.5, 0.9)
	_amai.add_child(heart_light)
	add_child(_amai)


func _spawn_plant_event() -> void:
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "阿麦身边长着奇怪绒毛的奇异草（或者藤蔓）在光的照亮下裹住了小凌的腿。"},
		{"speaker": "小凌", "text": "（警觉）这是什么地方。"},
		{"speaker": "旁白", "text": "阿麦没有看她，蹲下来挥了挥手，裹住小凌的奇异草退散"},
		{"speaker": "阿麦", "text": "你想让这里是什么地方，这里就是什么地方。"},
		{"speaker": "旁白", "text": "小凌后退了两步，看清了周围，"},
		{"speaker": "旁白", "text": "这里的树并不是笔直冲天的。"},
		{"speaker": "旁白", "text": "每棵树以奇怪的方式和其他树错综复杂地交织着。"},
		{"speaker": "旁白", "text": "脚边的地上铺满了腐叶，有类似刺猬的小动物从她脚边跑过。"},
		{"speaker": "旁白", "text": "远处……"},
		{"speaker": "旁白", "text": "小凌眨了眨眼，光太暗了，远处看不清。"},
		{"speaker": "旁白", "text": "阿麦冲着远处做了个手势。"},
		{"speaker": "旁白", "text": "萤火虫样的生物向远处排成一排，亮起一排灯指明了道路。"},
		{"speaker": "阿麦", "text": "走吧。"},
	], _on_forest_revealed)


func _on_forest_revealed() -> void:
	_reveal_forest()
	_show_firefly_dialogue()


func _reveal_forest() -> void:
	var trees := Node2D.new()
	for i in range(8):
		var t := Sprite2D.new()
		t.texture = PlaceholderAssets.make_color_texture(Color(0.08, 0.12, 0.08), Vector2i(24, 80))
		t.position = Vector2(100 + i * 100, 320 + randi_range(-20, 20))
		trees.add_child(t)
	add_child(trees)


func _show_firefly_dialogue() -> void:
	_show_inline_dialogue([
		{"speaker": "小凌", "text": "去哪儿？"},
		{"speaker": "旁白", "text": "阿麦没有回答，也没有看她，径直往前走。"},
		{"speaker": "旁白", "text": "小凌站在原地没动"},
		{"speaker": "小凌", "text": "我又不知道你是谁，我为什么要跟你去。"},
		{"speaker": "旁白", "text": "阿麦站住，终于回过头看她。"},
		{"speaker": "旁白", "text": "阿麦的脸颊在黑暗下棱角分明，但小凌仍然看不清他的脸。"},
		{"speaker": "旁白", "text": "他没有回答，"},
		{"speaker": "旁白", "text": "只是抬起手，"},
		{"speaker": "旁白", "text": "轻轻做了另一个手势。"},
		{"speaker": "旁白", "text": "刚才排成一列的萤火虫忽然散开，向森林深处飞去。"},
		{"speaker": "旁白", "text": "黑暗重新合拢，只有一颗萤火虫停在小凌面前，微弱地闪烁着。"},
		{"speaker": "阿麦", "text": "你说得对。"},
		{"speaker": "旁白", "text": "小凌有些意外。"},
		{"speaker": "阿麦", "text": "你不应该跟一个不知道是谁的人走。"},
		{"speaker": "小凌", "text": "那你还让我跟你走？"},
		{"speaker": "旁白", "text": "阿麦笑了一下。"},
		{"speaker": "阿麦", "text": "我只是带路。"},
		{"speaker": "旁白", "text": "他转过身，沿着萤火虫照亮的小路慢慢往前走。"},
		{"speaker": "旁白", "text": "走了几步，他停下来，没有回头。"},
		{"speaker": "阿麦", "text": "你可以不跟。"},
	], _on_firefly_choice)


func _on_firefly_choice() -> void:
	_spawn_fireflies()
	_phase = Phase.FREE_ROAM
	_player.set_can_move(true)
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "小凌站在原地。"},
		{"speaker": "旁白", "text": "森林里又传来窸窸窣窣的声音。"},
		{"speaker": "旁白", "text": "树枝上，一只眼睛圆溜溜的小动物探出脑袋，好奇地看着她。远处似乎有水源的痕迹，有什么东西在水里扑腾了一下。"},
		{"speaker": "旁白", "text": "阿麦继续往前走。"},
		{"speaker": "旁白", "text": "小凌看着他的背影。"},
		{"speaker": "旁白", "text": "不知道为什么，她突然觉得——这个地方好像没有人在催她。没有人告诉她应该去哪。也没有人告诉她，这条路才是正确的。"},
		{"speaker": "旁白", "text": "这样反而让小凌有些犹豫了……"},
		{"speaker": "旁白", "text": "小凌低头看了看脚边。"},
		{"speaker": "旁白", "text": "那只刚才缠住她的奇异草已经缩回了泥土里，露出一朵很小的白花。"},
	], _setup_amai_follow)


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
	if _amai:
		_amai.position = Vector2(750, 360)


func _setup_amai_follow() -> void:
	_amai_trigger = Area2D.new()
	_amai_trigger.position = _amai.position if _amai else Vector2(750, 360)
	_amai_trigger.collision_layer = 0
	_amai_trigger.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 40.0
	shape.shape = circle
	_amai_trigger.add_child(shape)
	_amai_trigger.body_entered.connect(_on_reach_amai)
	add_child(_amai_trigger)
	_player.set_can_move(true)


func _on_reach_amai(body: Node2D) -> void:
	if body != _player or _phase != Phase.FREE_ROAM:
		return
	_phase = Phase.DONE
	_amai_trigger.queue_free()
	_player.set_can_move(false)
	_complete({"result": "success"})
