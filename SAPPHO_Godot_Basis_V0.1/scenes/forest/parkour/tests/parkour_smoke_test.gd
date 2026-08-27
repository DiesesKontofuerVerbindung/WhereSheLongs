extends SceneTree

const MOTOR_SCRIPT := preload("res://scenes/forest/parkour/parkour_motor.gd")
const AMAI_SCRIPT_PATH := "res://scenes/forest/parkour/amai_parkour_placeholder.gd"
const MECHANICS_SCENE_PATH := "res://scenes/forest/parkour/parkour_mechanics_test.tscn"
const PROTOTYPE_SCENE_PATH := "res://scenes/forest/parkour/parkour_prototype.tscn"
const SEGMENT01_ART_PATH := "res://scenes/forest/parkour/reference/segment01_layout_authority_20260828.jpg"
const SEGMENT02_BACKDROP_ART_PATH := "res://scenes/forest/parkour/art/segment02_backdrop.jpg"
const SEGMENT02_ROOT_ART_PATH := "res://scenes/forest/parkour/art/segment02_roots.png"
const SEGMENT02_FOREGROUND_ART_PATH := "res://scenes/forest/parkour/art/segment02_foreground.png"
const SEGMENT03_CLOSED_ART_PATH := "res://scenes/forest/parkour/art/segment03_backdrop_closed.jpg"
const SEGMENT03_OPEN_ART_PATH := "res://scenes/forest/parkour/art/segment03_backdrop_open.jpg"
const SEGMENT03_PLATFORM_ART_PATH := "res://scenes/forest/parkour/art/segment03_platforms.png"
const SEGMENT03_FOREGROUND_ART_PATH := "res://scenes/forest/parkour/art/segment03_foreground.png"

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _test_motor_contract()
    await _test_mechanics_scene()
    await _test_continuous_parkour()
    if failures.is_empty():
        print("[PARKOUR V2 SMOKE PASS] S2 root-arch echo, supplied S3 dual-route art with stompable flower heads, trailing Amai, checkpoints, completion one-shot, and shared-player hand-off passed.")
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
    var vine_echo = scene.get_node("VineEchoCoordinator")
    var amai_echo: CharacterBody2D = scene.get_node("AmaiEcho")
    var player_runner = scene.get_node("Player/RunnerActionController")
    var amai_runner = scene.get_node("AmaiEcho/RunnerActionController")
    var gate_01 = scene.get_node("Gameplay/Segment02_Vines/Gate01")
    var gate_04 = scene.get_node("Gameplay/Segment02_Vines/Gate04")
    var plant_a = scene.get_node("Gameplay/Segment03_PredatorPlant/PredatorPlant")
    var plant_b = scene.get_node("Gameplay/Segment03_PredatorPlant/PredatorPlantB")
    var plant_c = scene.get_node("Gameplay/Segment03_PredatorPlant/PredatorPlantC")
    var lower_exit_platform = scene.get_node("Gameplay/Segment03_PredatorPlant/LowerExitPlatform")
    var amai = scene.get_node("AmaiPlaceholder")
    var camera: Camera2D = scene.get_node("DesignCamera")
    var expected_route: Array[StringName] = [&"J1", &"J2", &"J3", &"J3_5", &"J4"]
    eye_transition.duration = 0.001

    _check(player.scene_file_path == "res://shared/player/player.tscn", "Prototype does not use the canonical Shared Player")
    _check(route.get_order() == expected_route, "Segment 01 route is not J1 → J2 → J3 → J3.5 → J4")
    _check(amai is CharacterBody2D, "Segment 01/03 Amai is not a physical CharacterBody2D")
    _check(amai.has_method("release_segment_three_exit") and amai.has_method("is_segment_three_exit_ready"), "Segment 03 shared Amai exit contract is missing")
    _check(lower_exit_platform.surface_size.x >= 300.0, "Segment 03 lower exit platform does not support the shared walk to the exit")
    _check(scene.get_platform(&"J5") == null, "J5 still exists")
    _check(not scene.has_signal("parkour_advanced_route_completed"), "Deprecated advanced-route signal still exists")
    var segment_01_art: Sprite2D = scene.get_node("Background/Art")
    _check(segment_01_art.texture != null, "Segment 01 art failed to load")
    _check(segment_01_art.texture.resource_path == SEGMENT01_ART_PATH, "Segment 01 still uses the superseded layout image")
    _check(segment_01_art.position == Vector2(960.0, 540.0), "Segment 01 art is not centered in its 1920x1080 segment")
    _check(segment_01_art.scale.is_equal_approx(Vector2(0.75, 0.75)), "Segment 01 art is not fitted from 2560x1440 to 1920x1080")

    var expected_segment_01_tops := {
        &"J1": 470.0,
        &"J2": 677.0,
        &"J3": 454.0,
        &"J3_5": 625.0,
        &"J4": 412.0,
    }
    for platform_id in expected_segment_01_tops:
        var platform = scene.get_platform(platform_id)
        var platform_shape := platform.body_shape.shape as RectangleShape2D
        var platform_top: float = platform.global_position.y + platform.static_body.position.y - platform_shape.size.y * 0.5
        _check(absf(platform_top - expected_segment_01_tops[platform_id]) <= 1.0, "%s is not aligned to the new external Segment 1 authority image" % platform_id)

    for index in range(expected_route.size() - 1):
        _check(_jump_is_reachable(scene, expected_route[index], expected_route[index + 1], motor), "%s → %s is outside the unified jump envelope" % [expected_route[index], expected_route[index + 1]])

    var original_capsule := player_shape_node.shape as CapsuleShape2D
    var original_height := original_capsule.height
    scene.debug_set_slide(true)
    var slide_capsule := player_shape_node.shape as CapsuleShape2D
    _check(slide_capsule.height < original_height, "Slide did not shorten the runtime collider")
    scene.debug_set_slide(false)
    _check(is_equal_approx((player_shape_node.shape as CapsuleShape2D).height, original_height), "Slide collider did not restore")

    _test_segment_02_geometry(scene, motor, original_height, slide_capsule.height)
    _test_segment_03_geometry(scene, motor)
    _test_guide_paths(scene, amai)
    _test_debug_overlay_coverage(scene)

    var completion_count := [0]
    scene.parkour_completed.connect(func(): completion_count[0] += 1)
    for run_index in range(3):
        scene.reset_run_for_test()
        for platform_id in expected_route:
            scene.debug_teleport_to_platform(platform_id)
        _check(scene.actual_route == expected_route, "Run %d recorded an invalid Segment 01 route" % [run_index + 1])

        await scene.debug_jump_to_segment(2)
        _check(scene.current_segment == 2 and camera.position.is_equal_approx(route.get_segment_center(2)), "Eye transition did not enter Segment 02")
        _check(vine_echo.is_active(), "Segment 02 did not activate the Gate-indexed echo coordinator")
        _check(not vine_echo.automatic_forward, "Segment 02 must preserve manual horizontal movement")
        _check(vine_echo.echo_waits_at_gates, "Amai Echo must run ahead to each Gate and wait for the Player")
        _check(player_runner.get_script() == amai_runner.get_script(), "Player and Amai Echo do not share RunnerActionController")
        _check(is_equal_approx(player_runner.run_speed, amai_runner.run_speed), "Player and Amai Echo movement speeds differ")
        _check(gate_01.has_first_round_echo_bypass(amai_echo), "Gate 01 must bypass Amai Echo's NONE action")
        _check(gate_04.gate_index == 3, "Segment 02 must contain four indexed Vine gates")
        vine_echo.debug_run_sequence([1, 2, 1, 2])
        _check(vine_echo.get_player_history() == [1, 2, 1, 2], "Vine Player sequence is not UP DOWN UP DOWN")
        _check(vine_echo.get_xiaomai_history() == [0, 1, 2, 1], "Vine Amai sequence is not NONE UP DOWN UP")
        vine_echo.reset_rounds()
        vine_echo.debug_enter_gate(0)
        _check(vine_echo.debug_submit_action(1), "First Vine action was not accepted")
        _check(not vine_echo.debug_submit_action(2), "A Gate accepted a second action after lock")
        vine_echo.debug_execute_gate(0)
        vine_echo.debug_pass_gate(0)
        root.get_tree().paused = true
        _check(vine_echo.current_gate_index == 1 and vine_echo.previous_player_action == 1, "Pause changed the Gate-indexed previous action")
        root.get_tree().paused = false
        scene._on_s2_checkpoint_entered(player)
        scene.debug_set_slide(true)
        scene.respawn(false)
        _check(player.velocity == Vector2.ZERO and motor.velocity == Vector2.ZERO, "S2 respawn did not clear player and motor velocity")
        _check(not motor.is_sliding and is_equal_approx((player_shape_node.shape as CapsuleShape2D).height, original_height), "S2 respawn did not restore the normal collider")

        await scene.debug_jump_to_segment(3)
        _check(scene.current_segment == 3 and camera.position.is_equal_approx(route.get_segment_center(3)), "Eye transition did not enter Segment 03")
        _check(not amai.is_segment_three_route_locked(), "Amai started Segment 3 before Xiaoling chose a route")
        _check(amai.segment_three_follow_speed < motor.move_speed, "Amai is not slower than Xiaoling in Segment 3")
        var hazards := [0]
        plant_a.hazard_triggered.connect(func(): hazards[0] += 1, CONNECT_ONE_SHOT)
        plant_a.set_state(plant_a.PlantState.OPEN)
        _check(plant_a.debug_trigger_hazard() and hazards[0] == 1, "Plant A OPEN state did not activate its hazard")
        plant_a.reset_choice()
        plant_a.set_state(plant_a.PlantState.CLOSED)
        plant_a._on_safe_route_entered(player)
        _check(plant_a.last_choice == &"WAIT" and amai.active_guide == &"Segment03SafeGuide", "Plant A CLOSED safe route did not select WAIT and the safe guide")
        plant_a.reset_choice()
        plant_a._on_risk_route_entered(player)
        _check(plant_a.last_choice == &"RISK_ROUTE" and amai.active_guide == &"Segment03SafeGuide", "Amai changed its fixed Segment 03 route after the first choice")
        plant_b.reset_choice()
        plant_b.set_state(plant_b.PlantState.CLOSED)
        plant_b._on_safe_route_entered(player)
        _check(plant_b.last_choice == &"WAIT", "Plant B CLOSED safe route did not record WAIT")
        plant_b.reset_choice()
        plant_b._on_risk_route_entered(player)
        _check(plant_b.last_choice == &"RISK_ROUTE", "Plant B upper route did not record RISK_ROUTE")
        plant_c.reset_choice()
        plant_c.set_state(plant_c.PlantState.CLOSED)
        plant_c._on_safe_route_entered(player)
        _check(plant_c.last_choice == &"WAIT", "Plant C CLOSED safe route did not record WAIT")
        plant_c.reset_choice()
        plant_c._on_risk_route_entered(player)
        _check(plant_c.last_choice == &"RISK_ROUTE", "Plant C upper route did not record RISK_ROUTE")

        await scene.debug_complete_parkour()
        await scene.debug_complete_parkour()
        _check(scene.current_segment == 4, "Segment 03 finish did not enter the Waterfall placeholder")
        _check(amai.visible and amai.global_position.x >= 5760.0, "Amai stayed behind at the Segment 3 exit")
        _check(absf(amai.global_position.x - player.global_position.x) <= 180.0, "Amai did not enter Waterfall Intro beside Xiaoling")
        _check(completion_count[0] == run_index + 1, "parkour_completed emitted more than once for run %d" % [run_index + 1])

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


func _test_segment_02_geometry(scene: Node, motor: Node, normal_height: float, slide_height: float) -> void:
    var segment := scene.get_node("Gameplay/Segment02_Vines")
    for removed_name in ["StartPlatform", "RaisedStepA", "LowRunPlatform", "RaisedStepB", "ExitPlatform", "OptionalNarrowShortcut"]:
        _check(segment.get_node_or_null(removed_name) == null, "Segment 02 still contains obsolete platform %s" % removed_name)
    var roots := scene.get_node("Gameplay/Segment02_Vines/RootObstacles")
    var segment_art := segment.get_node("Segment02Art")
    _check(segment_art.get_node("Backdrop").texture.resource_path == SEGMENT02_BACKDROP_ART_PATH, "Segment 02 backdrop art is missing")
    _check(segment_art.get_node("Roots").texture.resource_path == SEGMENT02_ROOT_ART_PATH, "Segment 02 supplied root art is missing")
    _check(segment_art.get_node("Foreground").texture.resource_path == SEGMENT02_FOREGROUND_ART_PATH, "Segment 02 foreground art is missing")
    _check(segment_art.get_node("Foreground").z_index > scene.get_node("Player").z_index, "Segment 02 foreground does not pass in front of the characters")
    _check(roots.get_child_count() == 5, "Segment 02 must contain five reusable RootObstacle collision instances")
    var expected_sizes := ["MEDIUM", "SMALL", "LARGE", "MEDIUM", "SMALL"]
    var previous_right := -INF
    for index in roots.get_child_count():
        var root_obstacle := roots.get_child(index) as Node2D
        var width: float = root_obstacle.get_outer_width()
        var height: float = root_obstacle.get_outer_height()
        var size_class := "LARGE" if width >= 200.0 else ("SMALL" if width <= 130.0 else "MEDIUM")
        _check(size_class == expected_sizes[index], "%s breaks the MEDIUM-SMALL-LARGE rhythm" % root_obstacle.name)
        var left_edge: float = root_obstacle.global_position.x - width * 0.5
        _check(left_edge - previous_right >= 65.0, "%s has no independent landing/run-up space" % root_obstacle.name)
        previous_right = root_obstacle.global_position.x + width * 0.5
        _check(height >= 70.0, "%s has collapsed into a flat bar" % root_obstacle.name)
        _check(root_obstacle.scene_file_path == "res://scenes/forest/parkour/root_obstacle.tscn", "%s does not reuse root_obstacle.tscn" % root_obstacle.name)
        _check(not root_obstacle.visual_enabled, "%s still draws development art over the supplied root layer" % root_obstacle.name)

    var floor = scene.get_node("Gameplay/Segment02_Vines/VineRunFloor") as StaticBody2D
    var floor_shape_node: CollisionShape2D = scene.get_node("Gameplay/Segment02_Vines/VineRunFloor/CollisionShape2D")
    var floor_shape := floor_shape_node.shape as RectangleShape2D
    var root_shape_node: CollisionShape2D = scene.get_node("Gameplay/Segment02_Vines/RootObstacles/Root01/UpperCollision/CollisionShape2D")
    var root_shape := root_shape_node.shape as RectangleShape2D
    var floor_top: float = floor.global_position.y - floor_shape.size.y * 0.5
    var under_clearance: float = floor_top - (root_shape_node.global_position.y + root_shape.size.y * 0.5)
    _check(normal_height > under_clearance and slide_height < under_clearance, "A Root arch must block standing movement while allowing the slide collider")
    _check((scene.get_node("Player") as CollisionObject2D).collision_mask & 8 != 0, "Player does not collide with RootObstacle layer")
    _check((scene.get_node("AmaiEcho") as CollisionObject2D).collision_mask & 8 == 0, "Amai fixed route is blocked by RootObstacle layer")
    for gate_index in 4:
        var gate := scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (gate_index + 1)) as Node2D
        var root_obstacle := roots.get_child(gate_index) as Node2D
        _check(is_equal_approx(gate.global_position.x, root_obstacle.global_position.x), "Gate %d is detached from its Root obstacle" % (gate_index + 1))
    _check(scene.get_node("Gameplay/Checkpoints/S2AfterVine") != null, "S2_AFTER_VINE checkpoint is missing")


func _test_segment_03_geometry(scene: Node, motor: Node) -> void:
    var lower_route := [
        "Gameplay/Segment03_PredatorPlant/StartPlatform",
        "Gameplay/Segment03_PredatorPlant/LowerPlatform01",
        "Gameplay/Segment03_PredatorPlant/LowerPlatform02",
        "Gameplay/Segment03_PredatorPlant/LowerPlatform03",
        "Gameplay/Segment03_PredatorPlant/LowerExitPlatform",
    ]
    var flower_head_route := [
        "Gameplay/Segment03_PredatorPlant/StartPlatform",
        "Gameplay/Segment03_PredatorPlant/UpperApproach",
        "Gameplay/Segment03_PredatorPlant/PredatorPlant/HeadPlatform",
        "Gameplay/Segment03_PredatorPlant/UpperPlatform01",
        "Gameplay/Segment03_PredatorPlant/PredatorPlantB/HeadPlatform",
        "Gameplay/Segment03_PredatorPlant/UpperPlatform02",
        "Gameplay/Segment03_PredatorPlant/PredatorPlantC/HeadPlatform",
        "Gameplay/Segment03_PredatorPlant/UpperExitPlatform",
    ]
    _check(_surfaces_have_multiple_heights(scene, lower_route, 5), "Segment 03 lower route does not preserve the supplied terrain rhythm")
    _check(_surface_route_is_reachable(scene, lower_route, motor), "Segment 03 lower route contains an unreachable jump")
    _check(_surface_route_is_reachable(scene, flower_head_route, motor), "Segment 03 flower-head route contains an unreachable jump")
    _check(scene.get_node("Gameplay/Segment03_PredatorPlant/PredatorPlantB") != null, "Segment 03 is missing Plant B")
    _check(scene.get_node("Gameplay/Segment03_PredatorPlant/PredatorPlantC") != null, "Segment 03 is missing Plant C")
    for plant_name in ["PredatorPlant", "PredatorPlantB", "PredatorPlantC"]:
        var head = scene.get_node("Gameplay/Segment03_PredatorPlant/%s/HeadPlatform" % plant_name)
        _check(head.collision_shape.one_way_collision, "%s head is not a one-way landing surface" % plant_name)
    var segment_art := scene.get_node("Gameplay/Segment03_PredatorPlant/Segment03Art")
    _check(segment_art.get_node("BackdropClosed").texture.resource_path == SEGMENT03_CLOSED_ART_PATH, "Segment 03 closed backdrop is missing")
    _check(segment_art.get_node("BackdropOpen").texture.resource_path == SEGMENT03_OPEN_ART_PATH, "Segment 03 open backdrop is missing")
    _check(segment_art.get_node("Platforms").texture.resource_path == SEGMENT03_PLATFORM_ART_PATH, "Segment 03 platform art is missing")
    _check(segment_art.get_node("Foreground").texture.resource_path == SEGMENT03_FOREGROUND_ART_PATH, "Segment 03 foreground art is missing")
    _check(scene.get_node("Gameplay/Checkpoints/S3AfterPlant") != null, "Segment 03 recovery checkpoint is missing")


func _test_guide_paths(scene: Node, amai: Node) -> void:
    var guide_names: Array[StringName] = [
        &"Segment01Guide",
        &"Segment02MainGuide",
        &"Segment02JumpGuide",
        &"Segment02SlideGuide",
        &"Segment03SafeGuide",
        &"Segment03RiskGuide",
    ]
    for guide_name in guide_names:
        _check(amai.has_guide(guide_name), "Amai guide %s is missing" % guide_name)
        var guide = scene.get_node("Gameplay/AmaiGuides/%s" % guide_name)
        _check(guide.get_child_count() >= 3, "Amai guide %s has too few anchors" % guide_name)
    var amai_script := load(AMAI_SCRIPT_PATH) as GDScript
    var amai_source := amai_script.source_code
    _check("player.global_position +" not in amai_source and "lead_distance" not in amai_source, "Amai still uses direct player-position lead following")
    _check("guide_root" in amai_source and "_guide_points" in amai_source, "Amai is not driven by predefined guide anchors")
    _check("move_and_slide()" in amai_source and "jump_impulse" in amai_source, "Amai fixed guides do not use real jump physics")
    _check("global_position.move_toward" not in amai_source, "Amai still floats directly between guide anchors")
    _check("segment_three_follow_distance" in amai_source and "segment_three_follow_speed" in amai_source, "Amai lacks the Segment 3 trailing-follow contract")


func _test_debug_overlay_coverage(scene: Node) -> void:
    var debug = scene.get_node("ParkourDebug")
    var required_shapes := [
        ^"../Gameplay/Segment02_Vines/RootObstacles/Root01/UpperCollision/CollisionShape2D",
        ^"../Gameplay/Segment02_Vines/RootObstacles/Root05/UpperCollision/CollisionShape2D",
        ^"../Gameplay/Segment02_Vines/Gate01/DecisionZone/CollisionShape2D",
        ^"../Gameplay/Segment02_Vines/Gate01/ActionZone/CollisionShape2D",
        ^"../Gameplay/Segment02_Vines/Gate04/PassZone/CollisionShape2D",
        ^"../Gameplay/Segment03_PredatorPlant/PredatorPlant/HazardArea/CollisionShape2D",
        ^"../Gameplay/Segment03_PredatorPlant/PredatorPlant/HeadPlatform/CollisionShape2D",
        ^"../Gameplay/Segment03_PredatorPlant/PredatorPlantB/HazardArea/CollisionShape2D",
        ^"../Gameplay/Segment03_PredatorPlant/PredatorPlantB/HeadPlatform/CollisionShape2D",
        ^"../Gameplay/Segment03_PredatorPlant/PredatorPlantC/HazardArea/CollisionShape2D",
        ^"../Gameplay/Segment03_PredatorPlant/PredatorPlantC/HeadPlatform/CollisionShape2D",
        ^"../Gameplay/Checkpoints/S2AfterVine/CollisionShape2D",
        ^"../Gameplay/Checkpoints/S3AfterPlant/CollisionShape2D",
    ]
    for shape_path in required_shapes:
        _check(shape_path in debug.EXTRA_SHAPE_PATHS, "F4 overlay is missing %s" % shape_path)
    _check(root.get_tree().get_nodes_in_group("parkour_greybox_surface").size() >= 5, "F4 overlay cannot find the Segment 01/03 greybox surfaces")
    _check(root.get_tree().get_nodes_in_group("segment02_root_obstacle").size() == 5, "F4 overlay cannot find all five Segment 02 Root obstacles")


func _surfaces_have_multiple_heights(scene: Node, paths: Array, minimum_count: int) -> bool:
    var heights: Array[float] = []
    for path in paths:
        var surface = scene.get_node(path) as Node2D
        var top := _surface_top(surface)
        var found := false
        for height in heights:
            if is_equal_approx(height, top):
                found = true
                break
        if not found:
            heights.append(top)
    return heights.size() >= minimum_count


func _surface_route_is_reachable(scene: Node, paths: Array, motor: Node) -> bool:
    for index in range(paths.size() - 1):
        var source = scene.get_node(paths[index]) as Node2D
        var target = scene.get_node(paths[index + 1]) as Node2D
        if not _surface_is_reachable(source, target, motor):
            return false
    return true


func _surface_is_reachable(source: Node2D, target: Node2D, motor: Node) -> bool:
    var discriminant: float = motor.jump_velocity * motor.jump_velocity + 2.0 * motor.gravity * (_surface_top(target) - _surface_top(source))
    if discriminant < 0.0:
        return false
    var flight_time: float = (-motor.jump_velocity + sqrt(discriminant)) / motor.gravity
    var center_gap: float = absf(target.global_position.x - source.global_position.x)
    var source_size: Vector2 = source.get("surface_size")
    var target_size: Vector2 = target.get("surface_size")
    var edge_gap: float = maxf(0.0, center_gap - source_size.x * 0.5 - target_size.x * 0.5)
    return edge_gap <= motor.move_speed * flight_time


func _surface_top(surface: Node2D) -> float:
    var surface_size: Vector2 = surface.get("surface_size")
    return surface.global_position.y - surface_size.y * 0.5


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
