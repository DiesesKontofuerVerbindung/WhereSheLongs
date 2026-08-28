extends BaseExplorationMap

var _heart_light: PointLight2D
var _amai: Node2D


func _build_environment() -> void:
	set_camera_bounds(Rect2(0, 0, 960, 540))
	_add_fill_background(Color(0.03, 0.08, 0.12), Color(0.05, 0.12, 0.18))
	var stream := Polygon2D.new()
	stream.polygon = PackedVector2Array([Vector2(0, 410), Vector2(240, 360), Vector2(520, 430), Vector2(760, 350), Vector2(960, 390), Vector2(960, 540), Vector2(0, 540)])
	stream.color = Color(0.18, 0.55, 0.68, 0.5)
	stream.z_index = -5
	add_child(stream)
	_player.global_position = Vector2(480, 400)
	_spawn_amai()
	await get_tree().process_frame
	_start_descent_end()


func _spawn_amai() -> void:
	_amai = Node2D.new()
	_amai.position = Vector2(560, 360)
	var sprite := Sprite2D.new()
	sprite.texture = PlaceholderAssets.make_character_sprite(Color(0.3, 0.35, 0.55), "amai")
	sprite.position = Vector2(0, -16)
	_amai.add_child(sprite)
	_heart_light = PointLight2D.new()
	_heart_light.energy = 1.0
	_heart_light.texture_scale = 2.0
	_heart_light.color = Color(0.85, 0.5, 0.95)
	_amai.add_child(_heart_light)
	add_child(_amai)
	var pulse := Timer.new()
	pulse.wait_time = 0.6
	pulse.autostart = true
	pulse.timeout.connect(_pulse_heart)
	_amai.add_child(pulse)


func _pulse_heart() -> void:
	if _heart_light:
		_heart_light.energy = randf_range(0.6, 1.3)


func _start_descent_end() -> void:
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "他们跳下了瀑布，落进了小溪里。"},
		{"speaker": "旁白", "text": "阿麦接住小凌，小凌看到他心脏闪烁的光，如同自己的呼吸一般，小凌忍不住触摸，光线散出一团光丝缠绕着小凌的手。"},
	], func(): _complete({"result": "success"}))
