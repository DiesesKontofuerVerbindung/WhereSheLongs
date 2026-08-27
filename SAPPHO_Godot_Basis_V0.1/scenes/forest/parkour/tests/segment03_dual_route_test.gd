extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const CLOSED_ART := "res://scenes/forest/parkour/art/segment03_backdrop_closed.jpg"
const OPEN_ART := "res://scenes/forest/parkour/art/segment03_backdrop_open.jpg"
const PLATFORM_ART := "res://scenes/forest/parkour/art/segment03_platforms.png"
const FOREGROUND_ART := "res://scenes/forest/parkour/art/segment03_foreground.png"
const AUTHORITY_ART := "res://scenes/forest/parkour/reference/segment03_layout_authority_20260828.jpg"

var failures: Array[String] = []
var report: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load(PARKOUR_SCENE) as PackedScene
    _check(packed != null, "Parkour Prototype failed to load")
    if packed == null:
        _finish()
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame
    scene.active = false

    var segment := scene.get_node("Gameplay/Segment03_PredatorPlant")
    var motor := scene.get_node("ParkourMotor")
    var art := segment.get_node("Segment03Art")
    var closed_backdrop: Sprite2D = art.get_node("BackdropClosed")
    var open_backdrop: Sprite2D = art.get_node("BackdropOpen")
    var platforms: Sprite2D = art.get_node("Platforms")
    var foreground: Sprite2D = art.get_node("Foreground")
    _check(closed_backdrop.texture.resource_path == CLOSED_ART, "Closed-mouth Segment 3 backdrop is not connected")
    _check(open_backdrop.texture.resource_path == OPEN_ART, "Open-mouth Segment 3 backdrop is not connected")
    _check(platforms.texture.resource_path == PLATFORM_ART, "Segment 3 platform art is not connected")
    _check(foreground.texture.resource_path == FOREGROUND_ART, "Segment 3 foreground art is not connected")
    _check(ResourceLoader.exists(AUTHORITY_ART), "External Segment 3 authority image was not preserved")
    for sprite in [closed_backdrop, open_backdrop, platforms, foreground]:
        _check(sprite.position == Vector2(4800.0, 540.0), "%s is not centered in Segment 3" % sprite.name)
        _check(sprite.scale.is_equal_approx(Vector2(0.75, 0.75)), "%s is not fitted from 2560x1440 to 1920x1080" % sprite.name)
    _check(foreground.z_index > scene.get_node("Player").z_index, "Segment 3 foreground does not pass in front of the characters")

    var lower_route := [
        "StartPlatform",
        "LowerPlatform01",
        "LowerPlatform02",
        "LowerPlatform03",
        "LowerExitPlatform",
    ]
    var upper_route := [
        "StartPlatform",
        "UpperApproach",
        "PredatorPlant/HeadPlatform",
        "UpperPlatform01",
        "PredatorPlantB/HeadPlatform",
        "UpperPlatform02",
        "PredatorPlantC/HeadPlatform",
        "UpperExitPlatform",
    ]
    for platform_name in [
        "StartPlatform",
        "UpperApproach",
        "UpperPlatform01",
        "UpperPlatform02",
        "UpperExitPlatform",
        "LowerPlatform01",
        "LowerPlatform02",
        "LowerPlatform03",
        "LowerExitPlatform",
    ]:
        var platform: ParkourOneWaySurface = segment.get_node(platform_name)
        _check(platform.collision_shape.one_way_collision, "%s blocks jumps from below" % platform_name)
    _check(_route_is_reachable(segment, lower_route, motor), "Lower Segment 3 route contains an unreachable jump")
    _check(_route_is_reachable(segment, upper_route, motor), "Flower-head Segment 3 route contains an unreachable jump")

    var plant_a: ParkourPredatorPlant = segment.get_node("PredatorPlant")
    var plant_b: ParkourPredatorPlant = segment.get_node("PredatorPlantB")
    var plant_c: ParkourPredatorPlant = segment.get_node("PredatorPlantC")
    var heads: Array[ParkourOneWaySurface] = [
        plant_a.get_node("HeadPlatform"),
        plant_b.get_node("HeadPlatform"),
        plant_c.get_node("HeadPlatform"),
    ]
    var expected_head_centers := [
        Vector2(4380.0, 407.0),
        Vector2(4815.0, 311.0),
        Vector2(5284.0, 437.0),
    ]
    for head_index in heads.size():
        var head := heads[head_index]
        _check(head.collision_shape != null and head.collision_shape.one_way_collision, "%s is not a one-way stomp surface" % head.get_parent().name)
        _check(head.collision_layer == 8, "%s head is not isolated on the upper-route collision layer" % head.get_parent().name)
        _check(head.global_position.distance_to(expected_head_centers[head_index]) <= 1.0, "%s landing surface is not aligned to the visible red cap" % head.get_parent().name)
        var hazard_shape: CollisionShape2D = head.get_parent().get_node("HazardArea/CollisionShape2D")
        var hazard_rectangle := hazard_shape.shape as RectangleShape2D
        var head_top := head.global_position.y - head.surface_size.y * 0.5
        var hazard_top := hazard_shape.global_position.y - hazard_rectangle.size.y * 0.5
        _check(hazard_top - head_top >= 35.0, "%s mouth hazard reaches too close to the stomp surface" % head.get_parent().name)
        _check(absf(hazard_shape.global_position.x - head.global_position.x) <= 1.0, "%s mouth hazard is not centered under the visible head" % head.get_parent().name)

    plant_a.set_state(plant_a.PlantState.CLOSED)
    await process_frame
    _check(closed_backdrop.visible and not open_backdrop.visible, "Closed plant phase does not show the closed backdrop")
    _check(plant_b.state == plant_a.PlantState.CLOSED and plant_c.state == plant_a.PlantState.CLOSED, "Plant states drift away from the supplied full-scene art")
    plant_a.set_state(plant_a.PlantState.OPEN)
    await process_frame
    _check(open_backdrop.visible and not closed_backdrop.visible, "Open plant phase does not show the open backdrop")

    for head in heads:
        var hazard_events := [0]
        head.get_parent().hazard_triggered.connect(func() -> void: hazard_events[0] += 1)
        _check(await _drop_probe_on_head(head), "%s could not be landed on from above" % head.get_parent().name)
        _check(hazard_events[0] == 0, "%s mouth hazard falsely ate a runner standing on its cap" % head.get_parent().name)

    var amai: AmaiParkourPlaceholder = scene.get_node("AmaiPlaceholder")
    amai.reset_to_segment(3)
    _check(not amai.is_segment_three_route_locked(), "Amai chose a Segment 3 route before Xiaoling")
    amai.record_choice(&"RISK_ROUTE")
    _check(amai.active_guide == &"Segment03RiskGuide" and amai.is_segment_three_route_locked(), "Amai did not follow Xiaoling onto the flower-head route")
    _check(amai.collision_mask & 8 != 0, "Amai cannot collide with flower heads after choosing the upper route")
    amai.reset_to_segment(3)
    amai.record_choice(&"WAIT")
    _check(amai.active_guide == &"Segment03SafeGuide" and amai.is_segment_three_route_locked(), "Amai did not follow Xiaoling onto the lower route")
    _check(amai.collision_mask & 8 == 0, "Amai lower route still collides with upper-route platforms")

    report.append("lower_nodes=%d upper_nodes=%d head_surfaces=%d art=open/closed/platform/foreground" % [
        lower_route.size(),
        upper_route.size(),
        heads.size(),
    ])
    scene.queue_free()
    await process_frame
    _finish()


func _drop_probe_on_head(head: ParkourOneWaySurface) -> bool:
    var probe := CharacterBody2D.new()
    probe.collision_layer = 1
    probe.collision_mask = 8
    probe.floor_snap_length = 6.0
    var shape_node := CollisionShape2D.new()
    var capsule := CapsuleShape2D.new()
    capsule.radius = 10.0
    capsule.height = 32.0
    shape_node.shape = capsule
    probe.add_child(shape_node)
    root.add_child(probe)
    probe.global_position = head.global_position + Vector2(0.0, -130.0)
    probe.velocity = Vector2.ZERO
    var landed_on_head := false
    for frame in 180:
        probe.velocity.y = minf(probe.velocity.y + 1700.0 / 60.0, 1100.0)
        probe.move_and_slide()
        if probe.is_on_floor():
            for collision_index in probe.get_slide_collision_count():
                var collision := probe.get_slide_collision(collision_index)
                if collision != null and collision.get_collider() == head:
                    landed_on_head = true
                    break
            break
        await physics_frame
    probe.queue_free()
    await process_frame
    return landed_on_head


func _route_is_reachable(segment: Node, paths: Array, motor: ParkourMotor) -> bool:
    for index in range(paths.size() - 1):
        var source := segment.get_node(paths[index]) as Node2D
        var target := segment.get_node(paths[index + 1]) as Node2D
        if not _surface_is_reachable(source, target, motor):
            return false
    return true


func _surface_is_reachable(source: Node2D, target: Node2D, motor: ParkourMotor) -> bool:
    var source_size: Vector2 = source.get("surface_size")
    var target_size: Vector2 = target.get("surface_size")
    var source_top := source.global_position.y - source_size.y * 0.5
    var target_top := target.global_position.y - target_size.y * 0.5
    var discriminant: float = motor.jump_velocity * motor.jump_velocity + 2.0 * motor.gravity * (target_top - source_top)
    if discriminant < 0.0:
        return false
    var flight_time: float = (-motor.jump_velocity + sqrt(discriminant)) / motor.gravity
    var center_gap := absf(target.global_position.x - source.global_position.x)
    var edge_gap := maxf(0.0, center_gap - source_size.x * 0.5 - target_size.x * 0.5)
    return edge_gap <= motor.move_speed * flight_time


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    for line in report:
        print("[SEGMENT03 DUAL ROUTE] %s" % line)
    if failures.is_empty():
        print("[SEGMENT03 DUAL ROUTE PASS] Supplied art, two reachable routes, three stompable flower heads, synchronized plant phases, and route-following Amai passed.")
        quit(0)
        return
    for failure in failures:
        push_error("[SEGMENT03 DUAL ROUTE FAIL] %s" % failure)
    quit(1)
