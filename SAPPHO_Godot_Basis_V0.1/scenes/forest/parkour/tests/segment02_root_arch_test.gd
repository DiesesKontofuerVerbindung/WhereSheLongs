extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const BACKDROP_ART := "res://scenes/forest/parkour/art/segment02_backdrop.jpg"
const ROOT_ART := "res://scenes/forest/parkour/art/segment02_roots.png"
const FOREGROUND_ART := "res://scenes/forest/parkour/art/segment02_foreground.png"
const AUTHORITY_ART := "res://scenes/forest/parkour/reference/segment02_layout_authority_20260828.jpg"
const FLOOR_Y := 584.0
const MAX_CROSS_FRAMES := 150

var failures: Array[String] = []
var run_log: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load(PARKOUR_SCENE) as PackedScene
    _check(packed != null, "Parkour Prototype failed to load")
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

    _check(art.get_node("Backdrop").texture.resource_path == BACKDROP_ART, "Supplied Segment 2 backdrop is not connected")
    _check(art.get_node("Roots").texture.resource_path == ROOT_ART, "Supplied Segment 2 root layer is not connected")
    _check(art.get_node("Foreground").texture.resource_path == FOREGROUND_ART, "Supplied Segment 2 foreground is not connected")
    _check(ResourceLoader.exists(AUTHORITY_ART), "Segment 2 authority composite was not preserved")
    for sprite_name in ["Backdrop", "Roots", "Foreground"]:
        var sprite: Sprite2D = art.get_node(sprite_name)
        _check(sprite.position == Vector2(2880.0, 340.0), "%s is not vertically aligned to the playable floor" % sprite_name)
        _check(sprite.scale.is_equal_approx(Vector2(0.75, 0.75)), "%s is not fitted from 2560x1440" % sprite_name)
    _check(art.get_node("Foreground").z_index > scene.get_node("Player").z_index, "Segment 2 foreground does not occlude the characters")

    _check(roots.get_child_count() == 5, "Expected five supplied RootObstacle collision instances")
    var expected_x := [2179.0, 2552.0, 2871.0, 3200.0, 3513.0]
    var signatures: Dictionary = {}
    for index in roots.get_child_count():
        var obstacle := roots.get_child(index)
        signatures[obstacle.get_perspective_signature()] = true
        _check(is_equal_approx(obstacle.global_position.x, expected_x[index]), "%s is detached from the supplied root art" % obstacle.name)
        _check(not obstacle.visual_enabled, "%s still draws the development placeholder over supplied art" % obstacle.name)
        _check(obstacle.get_node("UpperCollision/CollisionShape2D").shape is RectangleShape2D, "%s does not use a stable rectangle collision" % obstacle.name)
        _check(obstacle.get_node("SlideOpening") != null, "%s has no SlideOpening hook" % obstacle.name)
        _check(obstacle.get_node("DebugMarker") != null, "%s has no DebugMarker" % obstacle.name)
    _check(signatures.size() == 5, "Root collision profiles repeat the same silhouette configuration")

    for obstacle in roots.get_children():
        var jump_result := await _cross_obstacle(player, runner, obstacle, 1)
        _check(jump_result, "%s could not be crossed with a physical jump" % obstacle.name)
    for obstacle in roots.get_children():
        var slide_result := await _cross_obstacle(player, runner, obstacle, 2)
        _check(slide_result, "%s could not be crossed with the shortened slide collider" % obstacle.name)

    for line in run_log:
        print("[S2 ROOT ARCH] %s" % line)
    scene.queue_free()
    await process_frame
    if failures.is_empty():
        print("[S2 ROOT ARCH PASS] Supplied layered art and five aligned roots passed by both Jump and Slide on continuous ground.")
        quit(0)
        return
    for failure in failures:
        push_error("[S2 ROOT ARCH FAIL] %s" % failure)
    quit(1)


func _cross_obstacle(player: CharacterBody2D, runner: Node, obstacle: Node2D, action: int) -> bool:
    runner.stop_run()
    var collision_shape := obstacle.get_node("UpperCollision/CollisionShape2D") as CollisionShape2D
    var rectangle := collision_shape.shape as RectangleShape2D
    var start_x: float = obstacle.global_position.x - rectangle.size.x * 0.5 - 62.0
    var target_x: float = obstacle.global_position.x + rectangle.size.x * 0.5 + 42.0
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
