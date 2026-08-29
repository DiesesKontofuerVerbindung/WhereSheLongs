extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const BACKDROP_ART := "res://scenes/forest/parkour/art/segment02_backdrop_v2.png"
const ROOT_ART := "res://scenes/forest/parkour/art/segment02_roots_v2.png"
const FOREGROUND_ART := "res://scenes/forest/parkour/art/segment02_foreground.png"
const FLOOR_Y := 584.0
const MAX_CROSS_FRAMES := 150
const EXPECTED_ROOT_X := [2228.0, 2649.0, 3069.0, 3495.0]
const EXPECTED_COLLISION_X := [2212.0, 2628.0, 3036.0, 3461.0]
const EXPECTED_COLLISION_WIDTH := [135.0, 132.0, 160.0, 226.0]

var failures: Array[String] = []
var run_log: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(PARKOUR_SCENE) as PackedScene
	_check(packed != null, "ForestRun failed to load")
	if packed == null:
		quit(1)
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	await scene.debug_jump_to_segment(2)
	await physics_frame

	var player: CharacterBody2D = scene.get_node("Player")
	var runner = scene.get_node("Player/RunnerActionController")
	var coordinator = scene.get_node("VineEchoCoordinator")
	var roots := scene.get_node("Gameplay/Segment02_Vines/RootObstacles")
	var art := scene.get_node("Gameplay/Segment02_Vines/Segment02Art")
	coordinator.stop_run(false)
	scene.set_physics_process(false)

	var expected_art := {
		"Backdrop": BACKDROP_ART,
		"Roots": ROOT_ART,
		"Foreground": FOREGROUND_ART,
	}
	for sprite_name in expected_art:
		var sprite: Sprite2D = art.get_node(sprite_name)
		_check(sprite.texture != null, "%s texture failed to load" % sprite_name)
		if sprite.texture != null:
			_check(sprite.texture.resource_path == expected_art[sprite_name], "%s is not connected to Segment 02 art" % sprite_name)
			_check(sprite.texture.get_width() == 2560 and sprite.texture.get_height() == 1440, "%s lost the 2560x1440 source resolution" % sprite_name)
		_check(sprite.position == Vector2(2880.0, 340.0), "%s is detached from the playable floor" % sprite_name)
		_check(sprite.scale.is_equal_approx(Vector2(0.75, 0.75)), "%s is not fitted from 2560x1440" % sprite_name)
	_check(art.get_node("Roots").z_index > scene.get_node("Player").z_index, "Front root layer does not occlude the characters")
	_check(art.get_node("Foreground").z_index > art.get_node("Roots").z_index, "Segment 02 supplied layer order changed")

	_check(roots.get_child_count() == 4, "Segment 02 must contain four roots")
	var signatures: Dictionary = {}
	for index in roots.get_child_count():
		var obstacle := roots.get_child(index)
		var collision_shape := obstacle.get_node("UpperCollision/CollisionShape2D") as CollisionShape2D
		var rectangle := collision_shape.shape as RectangleShape2D
		signatures[obstacle.get_perspective_signature()] = true
		_check(is_equal_approx(obstacle.global_position.x, EXPECTED_ROOT_X[index]), "%s is detached from the supplied silhouette" % obstacle.name)
		_check(is_equal_approx(collision_shape.global_position.x, EXPECTED_COLLISION_X[index]), "%s collision is detached from its opening" % obstacle.name)
		_check(is_equal_approx(rectangle.size.x, EXPECTED_COLLISION_WIDTH[index]), "%s collision width changed" % obstacle.name)
		_check(not obstacle.visual_enabled, "%s still draws development art" % obstacle.name)
		var gate := scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (index + 1)) as Node2D
		_check(is_equal_approx(gate.global_position.x, collision_shape.global_position.x), "Gate %d is detached from Root opening" % (index + 1))
	_check(signatures.size() == 4, "Four roots do not retain independent collision profiles")

	for obstacle in roots.get_children():
		_check(await _cross_obstacle(player, runner, obstacle, 1), "%s cannot be crossed by Jump" % obstacle.name)
	for obstacle in roots.get_children():
		_check(await _cross_obstacle(player, runner, obstacle, 2), "%s cannot be crossed by Slide" % obstacle.name)

	for line in run_log:
		print("[GESPIELT S2] %s" % line)
	scene.queue_free()
	await process_frame
	if failures.is_empty():
		print("FOREST_SEGMENT02_PASS art=2560x1440 roots=4 jump_each=true slide_each=true gates_aligned=true")
		quit(0)
		return
	for failure in failures:
		push_error("FOREST_SEGMENT02_FAIL %s" % failure)
	quit(1)


func _cross_obstacle(player: CharacterBody2D, runner: Node, obstacle: Node2D, action: int) -> bool:
	runner.stop_run()
	var collision_shape := obstacle.get_node("UpperCollision/CollisionShape2D") as CollisionShape2D
	var rectangle := collision_shape.shape as RectangleShape2D
	var start_x: float = collision_shape.global_position.x - rectangle.size.x * 0.5 - 62.0
	var target_x: float = collision_shape.global_position.x + rectangle.size.x * 0.5 + 42.0
	player.global_position = Vector2(start_x, FLOOR_Y)
	player.velocity = Vector2.ZERO
	runner.start_run(0.0)
	await physics_frame
	runner.perform_action(action)
	runner.set_horizontal_input(1.0)

	var crossed := false
	var action_seen := false
	var minimum_y := player.global_position.y
	for frame in MAX_CROSS_FRAMES:
		await physics_frame
		minimum_y = minf(minimum_y, player.global_position.y)
		if action == 1:
			action_seen = action_seen or player.velocity.y < -1.0 or minimum_y < FLOOR_Y - 35.0
		else:
			action_seen = action_seen or runner.is_sliding
		if player.global_position.x >= target_x:
			crossed = true
			break
		if frame > 35 and absf(player.velocity.x) < 1.0:
			break

	run_log.append("%s action=%s crossed=%s x=%.1f target=%.1f min_y=%.1f action_seen=%s" % [
		obstacle.name,
		"UP" if action == 1 else "DOWN",
		str(crossed),
		player.global_position.x,
		target_x,
		minimum_y,
		str(action_seen),
	])
	runner.stop_run()
	return crossed and action_seen


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
