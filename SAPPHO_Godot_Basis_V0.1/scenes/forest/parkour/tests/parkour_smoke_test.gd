extends SceneTree

const MOTOR_SCRIPT := preload("res://scenes/forest/parkour/parkour_motor.gd")
const MECHANICS_SCENE_PATH := "res://scenes/forest/parkour/parkour_mechanics_test.tscn"
const PROTOTYPE_SCENE_PATH := "res://scenes/forest/parkour/parkour_prototype.tscn"

var failures: Array[String] = []
var physical_route_failure := ""


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _test_motor_contract()
    await _test_mechanics_scene()
    await _test_forest_prototype()

    if failures.is_empty():
        print("[PARKOUR SMOKE PASS] Motor timing, Shared Player hand-off, foreground layering, landing guard, respawn, 10 physical A-D runs, 10 forest route cycles, completion one-shots, normalized fixed-art route, and debug toggles passed.")
        quit(0)
        return

    for failure in failures:
        push_error("[PARKOUR SMOKE FAIL] %s" % failure)
    quit(1)


func _test_motor_contract() -> void:
    var motor = MOTOR_SCRIPT.new()
    root.add_child(motor)
    _check(is_equal_approx(motor.move_speed, 300.0), "MOVE_SPEED export default changed")
    _check(is_equal_approx(motor.gravity, 1700.0), "GRAVITY export default changed")
    _check(is_equal_approx(motor.jump_velocity, -900.0), "JUMP_VELOCITY export default changed")

    motor.step(0.016, 0.0, false, false, false, true)
    motor.step(0.050, 0.0, false, false, false, false)
    var coyote_velocity: Vector2 = motor.step(0.010, 0.0, true, true, false, false)
    _check(coyote_velocity.y == motor.jump_velocity, "Coyote jump did not fire inside the 0.12 s window")

    motor.reset_motion()
    motor.step(0.016, 0.0, true, true, false, false)
    var buffered_velocity: Vector2 = motor.step(0.050, 0.0, false, true, false, true)
    _check(buffered_velocity.y == motor.jump_velocity, "Buffered jump did not fire on landing")

    var full_jump_speed := buffered_velocity.y
    var cut_velocity: Vector2 = motor.step(0.016, 0.0, false, false, true, false)
    _check(absf(cut_velocity.y) < absf(full_jump_speed), "Variable jump release did not shorten ascent")
    motor.queue_free()


func _test_mechanics_scene() -> void:
    var packed_scene := load(MECHANICS_SCENE_PATH) as PackedScene
    _check(packed_scene != null, "Mechanics scene failed to load")
    if packed_scene == null:
        return
    var scene := packed_scene.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var player = scene.get_node("Player")
    var controller = scene
    _check(player.scene_file_path == "res://shared/player/player.tscn", "Mechanics scene does not instantiate the canonical Shared Player")
    _check(player.control_mode == player.ControlMode.EXTERNAL, "Mechanics scene did not enter EXTERNAL control")
    _check(not player.interaction_enabled, "Shared interaction remained enabled during parkour")
    _check(scene.get_node("Background") is ColorRect, "Mechanics test improperly uses forest art")
    _check(player.z_index > scene.get_node("Background").z_index, "Mechanics Player is not rendered above the background")

    var previous_ticks := Engine.physics_ticks_per_second
    var previous_time_scale := Engine.time_scale
    Engine.physics_ticks_per_second = 240
    Engine.time_scale = 4.0
    var physical_runs_ok := await _exercise_physical_route(scene, [&"A", &"B", &"C", &"D"], 10)
    Engine.physics_ticks_per_second = previous_ticks
    Engine.time_scale = previous_time_scale
    _check(physical_runs_ok, "Mechanics A → B → C → D did not complete 10 physical input-driven runs: %s" % physical_route_failure)

    var landing_count := [0]
    var platform_a = scene.get_node("Gameplay/Platforms/A")
    platform_a.reset_landing_guard()
    platform_a.platform_landed.connect(func(_id): landing_count[0] += 1)
    platform_a.debug_register_landing(player)
    platform_a.debug_register_landing(player)
    _check(landing_count[0] == 1, "One physical landing emitted more than one platform_landed event")

    controller.respawn(false)
    _check(player.velocity == Vector2.ZERO, "Respawn did not clear Shared Player velocity")
    _check(scene.get_node("ParkourMotor").velocity == Vector2.ZERO, "Respawn did not clear ParkourMotor velocity")
    controller.exit_parkour()
    _check(player.control_mode == player.ControlMode.NORMAL, "Parkour exit did not restore NORMAL control")
    _check(player.interaction_enabled, "Parkour exit did not restore shared interaction")
    controller.enter_parkour()

    scene.queue_free()
    await process_frame


func _test_forest_prototype() -> void:
    var packed_scene := load(PROTOTYPE_SCENE_PATH) as PackedScene
    _check(packed_scene != null, "Forest prototype scene failed to load")
    if packed_scene == null:
        return
    var scene := packed_scene.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var route = scene.get_node("ParkourRoute")
    var motor = scene.get_node("ParkourMotor")
    var player = scene.get_node("Player")
    var art: Sprite2D = scene.get_node("Background/Art")
    var layout: Sprite2D = scene.get_node("Background/LayoutReference")
    var expected_order: Array[StringName] = [&"J1", &"J2", &"J3", &"J3_5", &"J4", &"J5"]

    _check(player.scene_file_path == "res://shared/player/player.tscn", "Prototype does not instantiate the canonical Shared Player")
    _check(art.texture != null and layout.texture != null, "One or both authoritative forest images failed to load")
    _check(is_equal_approx(art.scale.x, art.scale.y), "Forest art is stretched non-uniformly")
    _check(is_equal_approx(layout.scale.x, layout.scale.y), "Layout reference is stretched non-uniformly")
    _check(art.visible and not layout.visible, "Annotated layout reference is visible in normal gameplay")
    _check(player.z_index > scene.get_node("Background").z_index, "Prototype Player is not rendered above the forest art")

    for platform_id in expected_order:
        var platform = scene.get_platform(platform_id)
        var data: Dictionary = route.get_platform_data(platform_id)
        _check(platform != null, "Missing platform node %s" % platform_id)
        if platform != null:
            var expected_position: Vector2 = data["normalized_position"] * route.DESIGN_SIZE
            _check(platform.position.is_equal_approx(expected_position), "%s is not positioned from its normalized route anchor" % platform_id)

    for index in range(4):
        _check(_jump_is_reachable(scene, expected_order[index], expected_order[index + 1], motor), "%s → %s is outside the common jump envelope" % [expected_order[index], expected_order[index + 1]])
    _check(not _jump_is_reachable(scene, &"J4", &"J5", motor), "J5 unexpectedly became reachable by inflating the common jump envelope")

    var completion_counts := [0, 0]
    scene.parkour_main_route_completed.connect(func(): completion_counts[0] += 1)
    scene.parkour_advanced_route_completed.connect(func(): completion_counts[1] += 1)
    for run_index in range(10):
        scene.reset_run_for_test()
        for platform_id in expected_order.slice(0, 5):
            scene.debug_teleport_to_platform(platform_id)
        scene.debug_teleport_to_platform(&"J4")
        scene.debug_teleport_to_platform(&"J5")
        scene.debug_teleport_to_platform(&"J5")
        _check(scene.actual_route == expected_order, "Route cycle %d recorded an unstable actual_route" % [run_index + 1])
        _check(scene.highest_progress == 5, "Route cycle %d did not reach J5 progress" % [run_index + 1])
    _check(completion_counts[0] == 10, "Main completion was not one-shot per route cycle")
    _check(completion_counts[1] == 10, "Advanced completion was not one-shot per route cycle")

    var debug = scene.get_node("ParkourDebug")
    debug.toggle_debug()
    debug.toggle_collision()
    debug.toggle_labels()
    scene.toggle_reference_background()
    _check(layout.visible and not art.visible, "F6 background state did not switch to annotated layout")
    scene.toggle_reference_background()
    _check(art.visible and not layout.visible, "F6 background state did not switch back to clean art")

    scene.queue_free()
    await process_frame


func _jump_is_reachable(scene: Node, from_id: StringName, to_id: StringName, motor: Node) -> bool:
    var source = scene.get_platform(from_id)
    var target = scene.get_platform(to_id)
    var source_shape := source.body_shape.shape as RectangleShape2D
    var target_shape := target.body_shape.shape as RectangleShape2D
    var source_surface_y: float = source.global_position.y + source.static_body.position.y - source_shape.size.y * 0.5
    var target_surface_y: float = target.global_position.y + target.static_body.position.y - target_shape.size.y * 0.5
    var delta_y := target_surface_y - source_surface_y
    var discriminant: float = motor.jump_velocity * motor.jump_velocity + 2.0 * motor.gravity * delta_y
    if discriminant < 0.0:
        return false
    var descending_time: float = (-motor.jump_velocity + sqrt(discriminant)) / motor.gravity
    var center_gap: float = absf(target.global_position.x - source.global_position.x)
    var edge_gap: float = maxf(0.0, center_gap - source_shape.size.x * 0.5 - target_shape.size.x * 0.5)
    return edge_gap <= motor.move_speed * descending_time


func _exercise_physical_route(scene: Node, platform_ids: Array[StringName], run_count: int) -> bool:
    var player: CharacterBody2D = scene.get_node("Player")
    var motor = scene.get_node("ParkourMotor")
    for _run_index in range(run_count):
        _release_test_input()
        scene.reset_run_for_test()
        if not await _wait_for_platform(scene, platform_ids[0], 180):
            physical_route_failure = "run %d never landed on %s" % [_run_index + 1, platform_ids[0]]
            _release_test_input()
            return false

        for index in range(platform_ids.size() - 1):
            var source = scene.get_platform(platform_ids[index])
            var target = scene.get_platform(platform_ids[index + 1])
            var source_shape := source.body_shape.shape as RectangleShape2D
            var target_shape := target.body_shape.shape as RectangleShape2D
            var source_surface_y: float = source.global_position.y + source.static_body.position.y - source_shape.size.y * 0.5
            var target_surface_y: float = target.global_position.y + target.static_body.position.y - target_shape.size.y * 0.5
            var delta_y := target_surface_y - source_surface_y
            var discriminant: float = motor.jump_velocity * motor.jump_velocity + 2.0 * motor.gravity * delta_y
            if discriminant < 0.0:
                physical_route_failure = "run %d %s → %s has no ballistic solution" % [_run_index + 1, platform_ids[index], platform_ids[index + 1]]
                _release_test_input()
                return false
            var flight_time: float = (-motor.jump_velocity + sqrt(discriminant)) / motor.gravity
            var direction := signf(target.global_position.x - source.global_position.x)
            var target_entry_x: float = target.global_position.x - direction * (target_shape.size.x * 0.5 - 28.0)
            var launch_x: float = target_entry_x - direction * motor.move_speed * flight_time * 0.88
            var source_left: float = source.global_position.x - source_shape.size.x * 0.5 + 24.0
            var source_right: float = source.global_position.x + source_shape.size.x * 0.5 - 24.0
            launch_x = clampf(launch_x, source_left, source_right)

            _set_horizontal_input(direction)
            var launch_ready := false
            for _frame in range(240):
                if (direction > 0.0 and player.global_position.x >= launch_x) or (direction < 0.0 and player.global_position.x <= launch_x):
                    launch_ready = true
                    break
                await physics_frame
            if not launch_ready:
                physical_route_failure = "run %d could not reach launch point for %s → %s" % [_run_index + 1, platform_ids[index], platform_ids[index + 1]]
                _release_test_input()
                return false

            var jump_count_before: int = motor.jump_count
            var jump_released := false
            Input.action_press("jump")
            await physics_frame
            var fall_count_before_jump: int = scene.fall_count
            var max_x: float = player.global_position.x
            var min_y: float = player.global_position.y
            for _frame in range(360):
                max_x = maxf(max_x, player.global_position.x)
                min_y = minf(min_y, player.global_position.y)
                if not jump_released and motor.jump_count > jump_count_before and player.velocity.y >= 0.0:
                    Input.action_release("jump")
                    jump_released = true
                var target_delta_x: float = target.global_position.x - player.global_position.x
                if absf(target_delta_x) > target_shape.size.x * 0.28:
                    _set_horizontal_input(signf(target_delta_x))
                else:
                    _set_horizontal_input(0.0)
                if scene.current_platform == platform_ids[index + 1]:
                    break
                if scene.fall_count > fall_count_before_jump:
                    break
                await physics_frame
            Input.action_release("jump")
            if scene.current_platform != platform_ids[index + 1]:
                physical_route_failure = "run %d missed %s → %s at position %s, max_x=%.1f, min_y=%.1f, jumps=%d, falls=%d" % [_run_index + 1, platform_ids[index], platform_ids[index + 1], player.global_position, max_x, min_y, motor.jump_count, scene.fall_count]
                _release_test_input()
                return false

        _release_test_input()
        if scene.actual_route != platform_ids:
            physical_route_failure = "run %d recorded %s" % [_run_index + 1, scene.actual_route]
            return false
    return true


func _wait_for_platform(scene: Node, platform_id: StringName, frame_limit: int) -> bool:
    for _frame in range(frame_limit):
        if scene.current_platform == platform_id:
            return true
        await physics_frame
    return false


func _set_horizontal_input(direction: float) -> void:
    Input.action_release("move_left")
    Input.action_release("move_right")
    if direction < 0.0:
        Input.action_press("move_left")
    elif direction > 0.0:
        Input.action_press("move_right")


func _release_test_input() -> void:
    Input.action_release("move_left")
    Input.action_release("move_right")
    Input.action_release("jump")


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
