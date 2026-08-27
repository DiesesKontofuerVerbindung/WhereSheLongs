extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const RUN_COUNT := 30
const MAX_FRAMES := 1800

var failures: Array[String] = []
var baseline_landings: Dictionary = {}
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

    var player: CharacterBody2D = scene.get_node("Player")
    var amai: AmaiParkourPlaceholder = scene.get_node("AmaiPlaceholder")
    player.set_physics_process(false)
    amai.set_physics_process(true)

    for run_index in RUN_COUNT:
        var choice: StringName = &"WAIT" if run_index % 2 == 0 else &"RISK_ROUTE"
        var guide_name: StringName = &"Segment03SafeGuide" if choice == &"WAIT" else &"Segment03RiskGuide"
        player.global_position = Vector2(3970.0, 596.0)
        amai.reset_to_segment(3)
        amai.record_choice(choice)
        await physics_frame

        var complete := false
        for frame in MAX_FRAMES:
            player.global_position.x = minf(5700.0, player.global_position.x + 5.0)
            await physics_frame
            if amai.is_route_complete():
                complete = true
                break

        var landings := amai.get_landing_history()
        _check(complete, "run %d %s did not complete" % [run_index + 1, guide_name])
        _check(amai.get_fall_recovery_count() == 0, "run %d %s needed fall recovery" % [run_index + 1, guide_name])
        _check(amai.get_max_observed_lead() <= 30.0, "run %d %s moved ahead by %.1f px" % [run_index + 1, guide_name, amai.get_max_observed_lead()])
        _check(amai.get_max_observed_trail() >= amai.segment_three_follow_distance, "run %d %s never trailed Xiaoling" % [run_index + 1, guide_name])
        _check(amai.get_max_observed_horizontal_speed() <= amai.segment_three_follow_speed + 0.01, "run %d %s exceeded follow speed" % [run_index + 1, guide_name])

        if not baseline_landings.has(guide_name):
            baseline_landings[guide_name] = landings.duplicate()
        else:
            var baseline: Array = baseline_landings[guide_name]
            _check(landings.size() == baseline.size(), "run %d %s landing count drifted" % [run_index + 1, guide_name])
            for landing_index in mini(landings.size(), baseline.size()):
                _check(landings[landing_index].distance_to(baseline[landing_index]) <= 0.5, "run %d %s landing %d drifted" % [run_index + 1, guide_name, landing_index])

        report.append("run=%02d guide=%s jumps=%d landings=%d max_lead=%.1f max_trail=%.1f max_vx=%.1f final=(%.1f,%.1f)" % [
            run_index + 1,
            guide_name,
            amai.get_jump_count(),
            landings.size(),
            amai.get_max_observed_lead(),
            amai.get_max_observed_trail(),
            amai.get_max_observed_horizontal_speed(),
            amai.global_position.x,
            amai.global_position.y,
        ])

    scene.queue_free()
    await process_frame
    _finish()


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    for line in report:
        print("[AMAI S3 FOLLOW 30] %s" % line)
    if failures.is_empty():
        print("[AMAI S3 FOLLOW 30 PASS] Thirty alternating lower/flower-head runs stayed deterministic, physical, slower than Xiaoling, and behind her.")
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI S3 FOLLOW 30 FAIL] %s" % failure)
    quit(1)
