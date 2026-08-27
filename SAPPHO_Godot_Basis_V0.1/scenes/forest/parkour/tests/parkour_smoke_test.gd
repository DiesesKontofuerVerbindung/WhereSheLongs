extends SceneTree

const MOTOR_SCRIPT := preload("res://scenes/forest/parkour/parkour_motor.gd")
const MECHANICS_SCENE_PATH := "res://scenes/forest/parkour/parkour_mechanics_test.tscn"
const PROTOTYPE_SCENE_PATH := "res://scenes/forest/parkour/parkour_prototype.tscn"

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _test_motor_contract()
    await _test_mechanics_scene()
    await _test_continuous_parkour()
    if failures.is_empty():
        print("[PARKOUR V2 SMOKE PASS] Shared Player hand-off, J1-J4 route, right-edge eye transition, slide collider, vine choices, timed plant routes, checkpoints, Amai mimic, completion one-shot, and 10 full state cycles passed.")
        quit(0)
        return
    for failure in failures:
        push_error("[PARKOUR V2 SMOKE FAIL] %s" % failure)
    quit(1)


func _test_motor_contract() -> void:
    var motor = MOTOR_SCRIPT.new()
    root.add_child(motor)
    _check(is_equal_approx(motor.jump_velocity, -900.0), "Unified jump velocity is not -900")
    motor.step(0.016, 0.0, false, false, false, true)
    motor.step(0.050, 0.0, false, false, false, false)
    var coyote_velocity: Vector2 = motor.step(0.010, 0.0, true, true, false, false)
    _check(coyote_velocity.y == motor.jump_velocity, "Coyote jump failed")
    motor.reset_motion()
    motor.step(0.016, 0.0, true, true, false, false)
    var buffered_velocity: Vector2 = motor.step(0.050, 0.0, false, true, false, true)
    _check(buffered_velocity.y == motor.jump_velocity, "Jump buffer failed")
    motor.reset_motion()
    motor.velocity.x = 260.0
    motor.step(0.016, 0.0, false, false, false, true, true)
    _check(motor.is_sliding and motor.velocity.x > 0.0, "Ground slide did not preserve horizontal movement")
    motor.step(0.016, 0.0, false, false, false, false, true)
    _check(not motor.is_sliding, "Airborne slide was allowed")
    motor.queue_free()


func _test_mechanics_scene() -> void:
    var packed := load(MECHANICS_SCENE_PATH) as PackedScene
    _check(packed != null, "Mechanics scene failed to load")
    if packed == null:
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame
    var player = scene.get_node("Player")
    _check(player.scene_file_path == "res://shared/player/player.tscn", "Mechanics scene does not use the canonical Shared Player")
    _check(player.control_mode == player.ControlMode.EXTERNAL, "Mechanics scene did not enter EXTERNAL control")
    scene.respawn(false)
    _check(player.velocity == Vector2.ZERO and scene.get_node("ParkourMotor").velocity == Vector2.ZERO, "Respawn did not clear motion")
    scene.exit_parkour()
    _check(player.control_mode == player.ControlMode.NORMAL, "Parkour exit did not restore NORMAL control")
    scene.queue_free()
    await process_frame


func _test_continuous_parkour() -> void:
    var packed := load(PROTOTYPE_SCENE_PATH) as PackedScene
    _check(packed != null, "Parkour prototype failed to load")
    if packed == null:
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var route = scene.get_node("ParkourRoute")
    var motor = scene.get_node("ParkourMotor")
    var player: CharacterBody2D = scene.get_node("Player")
    var player_shape_node: CollisionShape2D = player.get_node("CollisionShape2D")
    var eye_transition = scene.get_node("EyeTransition")
    var vine = scene.get_node("Gameplay/Segment02_Vines/VineGate")
    var plant = scene.get_node("Gameplay/Segment03_PredatorPlant/PredatorPlant")
    var amai = scene.get_node("AmaiPlaceholder")
    var camera: Camera2D = scene.get_node("DesignCamera")
    var expected_route: Array[StringName] = [&"J1", &"J2", &"J3", &"J3_5", &"J4"]
    eye_transition.duration = 0.001

    _check(player.scene_file_path == "res://shared/player/player.tscn", "Prototype does not use the canonical Shared Player")
    _check(route.get_order() == expected_route, "Segment 01 route is not J1 → J2 → J3 → J3.5 → J4")
    _check(scene.get_platform(&"J5") == null, "J5 still exists")
    _check(not scene.has_signal("parkour_advanced_route_completed"), "Deprecated advanced-route signal still exists")
    _check(scene.get_node("Background/Art").texture != null, "Segment 01 art failed to load")

    for index in range(expected_route.size() - 1):
        _check(_jump_is_reachable(scene, expected_route[index], expected_route[index + 1], motor), "%s → %s is outside the unified jump envelope" % [expected_route[index], expected_route[index + 1]])

    var original_capsule := player_shape_node.shape as CapsuleShape2D
    var original_height := original_capsule.height
    scene.debug_set_slide(true)
    var slide_capsule := player_shape_node.shape as CapsuleShape2D
    _check(slide_capsule.height < original_height, "Slide did not shorten the runtime collider")
    scene.debug_set_slide(false)
    _check(is_equal_approx((player_shape_node.shape as CapsuleShape2D).height, original_height), "Slide collider did not restore")

    var floor_shape := scene.get_node("Gameplay/Segment02_Vines/Ground/CollisionShape2D").shape as RectangleShape2D
    var vine_shape := scene.get_node("Gameplay/Segment02_Vines/VineGate/StaticBody2D/CollisionShape2D").shape as RectangleShape2D
    var floor_top := 950.0 - floor_shape.size.y * 0.5
    var vine_bottom := 811.0 + vine_shape.size.y * 0.5
    var under_gap := floor_top - vine_bottom
    _check(original_height > under_gap and slide_capsule.height < under_gap, "Vine gate geometry does not block run while allowing slide")
    var jump_apex: float = motor.jump_velocity * motor.jump_velocity / (2.0 * motor.gravity)
    _check(jump_apex > floor_top - (811.0 - vine_shape.size.y * 0.5), "Vine gate cannot be cleared by the unified jump")

    plant.set_state(plant.PlantState.OPEN)
    _check(plant.get_state_name() == "OPEN", "Plant OPEN state failed")
    plant.set_state(plant.PlantState.CLOSED)
    _check(plant.get_state_name() == "CLOSED", "Plant CLOSED state failed")

    var counts := [0, 0, 0, 0]
    scene.segment_01_completed.connect(func(): counts[0] += 1)
    scene.segment_02_completed.connect(func(_choice): counts[1] += 1)
    scene.segment_03_completed.connect(func(_choice): counts[2] += 1)
    scene.parkour_completed.connect(func(): counts[3] += 1)

    for run_index in range(10):
        scene.reset_run_for_test()
        for platform_id in expected_route:
            scene.debug_teleport_to_platform(platform_id)
        _check(scene.actual_route == expected_route, "Run %d recorded an invalid Segment 01 route" % [run_index + 1])
        _check(counts[3] == run_index, "J4 completed the whole Parkour")

        await scene.debug_jump_to_segment(2)
        _check(scene.current_segment == 2 and camera.position.is_equal_approx(route.get_segment_center(2)), "Eye transition did not enter Segment 02")
        vine.reset_choice()
        var vine_choice: StringName = &"SLIDE" if run_index % 2 == 0 else &"JUMP"
        vine.debug_choose(vine_choice)
        _check(vine.last_choice == vine_choice, "Vine choice was not recorded")
        if vine_choice == &"SLIDE":
            scene.debug_set_slide(true)
            scene.respawn(false)
            _check(is_equal_approx((player_shape_node.shape as CapsuleShape2D).height, original_height), "Respawn did not restore collider after slide")

        await scene.debug_jump_to_segment(3)
        _check(scene.current_segment == 3 and camera.position.is_equal_approx(route.get_segment_center(3)), "Eye transition did not enter Segment 03")
        plant.reset_choice()
        var plant_choice: StringName = &"WAIT" if run_index % 2 == 0 else &"RISK_ROUTE"
        plant.debug_choose(plant_choice)
        _check(amai.last_mimicked_choice == plant_choice, "Amai did not mimic the latest player choice")

        await scene.debug_complete_parkour()
        await scene.debug_complete_parkour()
        _check(scene.current_segment == 4, "Parkour did not enter Waterfall placeholder")

    _check(counts == [10, 10, 10, 10], "Segment or completion signals were not one-shot across 10 runs: %s" % [counts])
    _check(player.control_mode == player.ControlMode.LOCKED, "Waterfall intro placeholder did not lock control")

    scene.reset_run_for_test()
    var art: Sprite2D = scene.get_node("Background/Art")
    var layout: Sprite2D = scene.get_node("Background/LayoutReference")
    scene.toggle_reference_background()
    _check(layout.visible and not art.visible, "F6 did not show the annotated reference")
    scene.toggle_reference_background()
    _check(art.visible and not layout.visible, "F6 did not restore clean art")

    scene.queue_free()
    await process_frame


func _jump_is_reachable(scene: Node, from_id: StringName, to_id: StringName, motor: Node) -> bool:
    var source = scene.get_platform(from_id)
    var target = scene.get_platform(to_id)
    var source_shape := source.body_shape.shape as RectangleShape2D
    var target_shape := target.body_shape.shape as RectangleShape2D
    var source_y: float = source.global_position.y + source.static_body.position.y - source_shape.size.y * 0.5
    var target_y: float = target.global_position.y + target.static_body.position.y - target_shape.size.y * 0.5
    var discriminant: float = motor.jump_velocity * motor.jump_velocity + 2.0 * motor.gravity * (target_y - source_y)
    if discriminant < 0.0:
        return false
    var flight_time: float = (-motor.jump_velocity + sqrt(discriminant)) / motor.gravity
    var center_gap: float = absf(target.global_position.x - source.global_position.x)
    var edge_gap: float = maxf(0.0, center_gap - source_shape.size.x * 0.5 - target_shape.size.x * 0.5)
    return edge_gap <= motor.move_speed * flight_time


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
