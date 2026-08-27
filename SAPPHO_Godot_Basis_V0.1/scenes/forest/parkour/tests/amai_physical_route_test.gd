extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const MAX_ROUTE_FRAMES := 1800
const PLAYER_FOLLOW_SPEED := 300.0
const MAX_ALLOWED_LEAD := 700.0

var failures: Array[String] = []
var report_lines: Array[String] = []


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

    var player: CharacterBody2D = scene.get_node("Player")
    var amai: CharacterBody2D = scene.get_node("AmaiPlaceholder")
    scene.active = false
    player.set_physics_process(false)
    amai.set_physics_process(true)

    var segment_01 := await _run_route(amai, player, 1, &"", 384.0, 1300.0)
    _check_route("Segment01Guide", segment_01, 4, 5)

    var segment_03_safe := await _run_route(amai, player, 3, &"WAIT", 3970.0, 5700.0)
    _check_route("Segment03SafeGuide", segment_03_safe, 3, 10)

    var segment_03_risk := await _run_route(amai, player, 3, &"RISK_ROUTE", 3970.0, 5700.0)
    _check_route("Segment03RiskGuide", segment_03_risk, 7, 16)

    scene.queue_free()
    await process_frame
    _finish()


func _run_route(
        amai: CharacterBody2D,
        player: CharacterBody2D,
        segment_index: int,
        choice: StringName,
        player_start_x: float,
        player_end_x: float
    ) -> Dictionary:
    player.global_position.x = player_start_x
    amai.reset_to_segment(segment_index)
    if not choice.is_empty():
        amai.record_choice(choice)
    await physics_frame

    var observed_airborne := false
    var observed_rising := false
    var observed_falling := false
    var completion_frame := -1
    for frame in MAX_ROUTE_FRAMES:
        player.global_position.x = minf(player_end_x, player.global_position.x + PLAYER_FOLLOW_SPEED / 60.0)
        await physics_frame
        if not amai.is_on_floor():
            observed_airborne = true
            observed_rising = observed_rising or amai.velocity.y < -100.0
            observed_falling = observed_falling or amai.velocity.y > 100.0
        if amai.is_route_complete():
            completion_frame = frame
            break

    var result := {
        "guide": str(amai.active_guide),
        "complete": completion_frame >= 0,
        "completion_frame": completion_frame,
        "jump_count": amai.get_jump_count(),
        "landing_count": amai.get_landing_history().size(),
        "landings": amai.get_landing_history(),
        "max_lead": amai.get_max_observed_lead(),
        "max_trail": amai.get_max_observed_trail(),
        "max_horizontal_speed": amai.get_max_observed_horizontal_speed(),
        "fall_recoveries": amai.get_fall_recovery_count(),
        "airborne": observed_airborne,
        "rising": observed_rising,
        "falling": observed_falling,
        "final_position": amai.global_position,
        "max_landing_vertical_error": _max_landing_vertical_error(amai, amai.get_landing_history()),
    }
    report_lines.append("guide=%s complete=%s frame=%d jumps=%d landings=%d recoveries=%d max_lead=%.1f max_trail=%.1f max_vx=%.1f max_landing_dy=%.1f final=(%.1f,%.1f)" % [
        result["guide"],
        str(result["complete"]),
        result["completion_frame"],
        result["jump_count"],
        result["landing_count"],
        result["fall_recoveries"],
        result["max_lead"],
        result["max_trail"],
        result["max_horizontal_speed"],
        result["max_landing_vertical_error"],
        result["final_position"].x,
        result["final_position"].y,
    ])
    return result


func _max_landing_vertical_error(amai: CharacterBody2D, landings: Array[Vector2]) -> float:
    var guide := amai.guide_root.get_node(NodePath(str(amai.active_guide))) as Node2D
    var max_error := 0.0
    var landing_index := 0
    for child in guide.get_children():
        if child is not Marker2D or landing_index >= landings.size():
            continue
        max_error = maxf(max_error, absf(landings[landing_index].y - (child as Marker2D).global_position.y))
        landing_index += 1
    return max_error


func _check_route(guide_name: String, result: Dictionary, expected_jumps: int, expected_landings: int) -> void:
    _check(result["guide"] == guide_name, "%s did not remain active" % guide_name)
    _check(result["complete"], "%s did not complete its fixed route" % guide_name)
    _check(result["jump_count"] == expected_jumps, "%s jump count is %d instead of %d" % [guide_name, result["jump_count"], expected_jumps])
    _check(result["landing_count"] >= expected_landings, "%s recorded only %d/%d landings" % [guide_name, result["landing_count"], expected_landings])
    _check(result["airborne"] and result["rising"] and result["falling"], "%s did not show a real rise/fall physics arc" % guide_name)
    _check(result["max_horizontal_speed"] <= 300.01, "%s moved faster than Xiaoling's 300 px/s" % guide_name)
    if guide_name.begins_with("Segment03"):
        _check(result["max_horizontal_speed"] <= 255.01, "%s ignored the slower Segment 3 follow speed" % guide_name)
        _check(result["max_lead"] <= 30.01, "%s ran ahead of Xiaoling in Segment 3 by %.1f px" % [guide_name, result["max_lead"]])
        _check(result["max_trail"] >= 150.0, "%s never formed a visible trailing gap" % guide_name)
    else:
        _check(result["max_lead"] <= MAX_ALLOWED_LEAD, "%s exceeded the one-to-two-cell lead: %.1f" % [guide_name, result["max_lead"]])
    _check(result["max_landing_vertical_error"] <= 18.01, "%s landed on the wrong height by %.1f px" % [guide_name, result["max_landing_vertical_error"]])
    _check(guide_name != "Segment01Guide" or result["fall_recoveries"] == 0, "Segment01Guide needed %d emergency fall recoveries" % result["fall_recoveries"])


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    for line in report_lines:
        print("[AMAI PHYSICAL ROUTE] %s" % line)
    if failures.is_empty():
        print("[AMAI PHYSICAL ROUTE PASS] Segment 01 keeps its fixed jump lead; Segment 03 uses fixed real jumps on both routes while Amai follows behind Xiaoling.")
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI PHYSICAL ROUTE FAIL] %s" % failure)
    quit(1)
