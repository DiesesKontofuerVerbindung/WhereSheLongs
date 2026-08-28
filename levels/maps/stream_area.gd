extends BaseExplorationMap

var _heart_light: PointLight2D
var _amai: Node2D
var _choice_layer: CanvasLayer


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


func _start_descent_end() -> void:
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "阿麦接住了小凌。小凌看到他心脏中闪烁的光，如同自己的呼吸一般。"},
	], func(): _complete({"result": "success"}))
