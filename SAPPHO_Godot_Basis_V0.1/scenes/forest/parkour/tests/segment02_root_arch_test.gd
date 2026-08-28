extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const BACKDROP_ART := "res://scenes/forest/parkour/art/segment02_backdrop_v2.png"
const ROOT_ART := "res://scenes/forest/parkour/art/segment02_roots_v2.png"
const FOREGROUND_ART := "res://scenes/forest/parkour/art/segment02_foreground.png"
const AUTHORITY_ART := "res://scenes/forest/parkour/reference/segment02_layout_authority_20260828_v2.png"
const FLOOR_Y := 584.0
const MAX_CROSS_FRAMES := 150
const EXPECTED_ROOT_X := [2228.0, 2649.0, 3069.0, 3495.0]
const EXPECTED_COLLISION_X := [2212.0, 2628.0, 3036.0, 3461.0]
const EXPECTED_COLLISION_WIDTH := [135.0, 132.0, 160.0, 226.0]
const EXPECTED_ACTION_ZONE_X := [2112.0, 2528.0, 2936.0, 3313.0]
const EXPECTED_PASS_ZONE_X := [2272.0, 2688.0, 3096.0, 3636.0]

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
    var camera := scene.get_node("DesignCamera") as Camera2D
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
            _check(sprite.texture.resource_path == expected_art[sprite_name], "%s is not connected to the supplied Segment 2 art" % sprite_name)
    _check(ResourceLoader.exists(AUTHORITY_ART), "Segment 2 authority composite was not preserved")
    for sprite_name in ["Backdrop", "Roots", "Foreground"]:
        var sprite: Sprite2D = art.get_node(sprite_name)
        _check(sprite.position == Vector2(2880.0, 340.0), "%s is not vertically aligned to the playable floor" % sprite_name)
        _check(sprite.scale.is_equal_approx(Vector2(0.75, 0.75)), "%s is not fitted from 2560x1440" % sprite_name)
        if sprite.texture != null:
            _check(sprite.texture.get_width() == 2560 and sprite.texture.get_height() == 1440, "%s lost the 2560x1440 source resolution" % sprite_name)
    _check(art.get_node("Roots").z_index > scene.get_node("Player").z_index, "Segment 2 front root layer does not occlude the characters")
    _check(art.get_node("Foreground").z_index > art.get_node("Roots").z_index, "Segment 2 foreground layering no longer matches the supplied composite")
    _check(camera.global_position.is_equal_approx(art.get_node("Backdrop").global_position), "Segment 2 camera is not centered on the supplied art and exposes empty space")

    _check(roots.get_child_count() == 4, "Expected four supplied RootObstacle collision instances")
    var signatures: Dictionary = {}
    for index in roots.get_child_count():
        var obstacle := roots.get_child(index)
        var collision_shape := obstacle.get_node("UpperCollision/CollisionShape2D") as CollisionShape2D
        var rectangle := collision_shape.shape as RectangleShape2D
        signatures[obstacle.get_perspective_signature()] = true
        _check(is_equal_approx(obstacle.global_position.x, EXPECTED_ROOT_X[index]), "%s is detached from the supplied root silhouette" % obstacle.name)
        _check(is_equal_approx(collision_shape.global_position.x, EXPECTED_COLLISION_X[index]), "%s collision is detached from its visible opening" % obstacle.name)
        _check(is_equal_approx(rectangle.size.x, EXPECTED_COLLISION_WIDTH[index]), "%s collision width no longer follows its visible opening" % obstacle.name)
        _check(not obstacle.visual_enabled, "%s still draws the development placeholder over supplied art" % obstacle.name)
        _check(collision_shape.shape is RectangleShape2D, "%s does not use a stable rectangle collision" % obstacle.name)
        _check(obstacle.get_node("SlideOpening") != null, "%s has no SlideOpening hook" % obstacle.name)
        _check(obstacle.get_node("DebugMarker") != null, "%s has no DebugMarker" % obstacle.name)
    _check(signatures.size() == 4, "Root collision profiles repeat the same silhouette configuration")

    for index in roots.get_child_count():
        var obstacle := roots.get_child(index)
        var gate := scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (index + 1))
        var root_shape_node := obstacle.get_node("UpperCollision/CollisionShape2D") as CollisionShape2D
        var root_rectangle := root_shape_node.shape as RectangleShape2D
        var action_shape_node := gate.get_node("ActionZone/CollisionShape2D") as CollisionShape2D
        var action_rectangle := action_shape_node.shape as RectangleShape2D
        var root_left := root_shape_node.global_position.x - root_rectangle.size.x * 0.5
        var action_right := action_shape_node.global_position.x + action_rectangle.size.x * 0.5
        _check(is_equal_approx(action_shape_node.global_position.x, EXPECTED_ACTION_ZONE_X[index]), "Gate%02d action line drifted from its root approach" % (index + 1))
        _check(is_equal_approx(gate.get_node("PassZone/CollisionShape2D").global_position.x, EXPECTED_PASS_ZONE_X[index]), "Gate%02d pass line drifted from its root exit" % (index + 1))
        _check(action_right <= root_left - 4.0, "Gate%02d action line overlaps its root collision" % (index + 1))

    for index in roots.get_child_count():
        var obstacle := roots.get_child(index)
        var gate := scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (index + 1))
        var jump_result := await _cross_obstacle(player, runner, obstacle, gate, 1)
        _check(jump_result, "%s could not be crossed with a physical jump" % obstacle.name)
    for index in roots.get_child_count():
        var obstacle := roots.get_child(index)
        var gate := scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (index + 1))
        var slide_result := await _cross_obstacle(player, runner, obstacle, gate, 2)
        _check(slide_result, "%s could not be crossed with the shortened slide collider" % obstacle.name)

    for line in run_log:
        print("[S2 ROOT ARCH] %s" % line)
    scene.queue_free()
    await process_frame
    if failures.is_empty():
        print("[S2 ROOT ARCH PASS] New 2560x1440 layered art and four aligned roots passed by both Jump and Slide on continuous ground.")
        quit(0)
        return
    for failure in failures:
        push_error("[S2 ROOT ARCH FAIL] %s" % failure)
    quit(1)


func _cross_obstacle(player: CharacterBody2D, runner: Node, obstacle: Node2D, gate: Node2D, action: int) -> bool:
    runner.stop_run()
    var collision_shape := obstacle.get_node("UpperCollision/CollisionShape2D") as CollisionShape2D
    var rectangle := collision_shape.shape as RectangleShape2D
    var action_shape := gate.get_node("ActionZone/CollisionShape2D") as CollisionShape2D
    var start_x: float = action_shape.global_position.x - 18.0
    var target_x: float = collision_shape.global_position.x + rectangle.size.x * 0.5 + 42.0
    player.global_position = Vector2(start_x, FLOOR_Y)
    player.velocity = Vector2.ZERO
    runner.start_run(0.0)
    await physics_frame
    runner.perform_action(action)
    runner.set_horizontal_input(1.0)

    var crossed := false
    var action_seen := false
    var root_contact_seen := false
    var minimum_y := player.global_position.y
    for frame in MAX_CROSS_FRAMES:
        await physics_frame
        minimum_y = minf(minimum_y, player.global_position.y)
        for collision_index in player.get_slide_collision_count():
            var collision := player.get_slide_collision(collision_index)
            if collision != null and collision.get_collider() == obstacle.get_node("UpperCollision"):
                root_contact_seen = true
        if action == 1:
            action_seen = action_seen or player.velocity.y < -1.0 or minimum_y < FLOOR_Y - 35.0
        else:
            action_seen = action_seen or runner.is_sliding
        if player.global_position.x >= target_x:
            crossed = true
            break
        if frame > 35 and absf(player.velocity.x) < 1.0:
            break

    run_log.append("%s action=%s start=%.1f crossed=%s x=%.1f target=%.1f min_y=%.1f action_seen=%s root_contact=%s" % [
        obstacle.name,
        "UP" if action == 1 else "DOWN",
        start_x,
        str(crossed),
        player.global_position.x,
        target_x,
        minimum_y,
        str(action_seen),
        str(root_contact_seen),
    ])
    runner.stop_run()
    return crossed and action_seen and not root_contact_seen


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
