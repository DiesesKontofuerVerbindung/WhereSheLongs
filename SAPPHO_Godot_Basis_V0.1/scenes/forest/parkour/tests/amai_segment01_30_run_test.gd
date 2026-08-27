extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const RUN_COUNT := 30
const MAX_ROUTE_FRAMES := 900
const PLAYER_FOLLOW_SPEED := 240.0

var failures: Array[String] = []
var run_lines: Array[String] = []


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
    var amai: AmaiParkourPlaceholder = scene.get_node("AmaiPlaceholder")
    scene.active = false
    player.set_physics_process(false)
    amai.set_physics_process(true)

    var landing_sums: Array[Vector2] = []
    landing_sums.resize(5)
    landing_sums.fill(Vector2.ZERO)
    var baseline_landings: Array[Vector2] = []
    var maximum_repeat_drift := 0.0

    for run_index in RUN_COUNT:
        player.global_position = Vector2(384.0, 430.0)
        amai.reset_to_segment(1)
        await physics_frame

        var takeoffs: Array[Vector2] = []
        var previous_jump_count := 0
        var completion_frame := -1
        for frame in MAX_ROUTE_FRAMES:
            player.global_position.x = minf(1300.0, player.global_position.x + PLAYER_FOLLOW_SPEED / 60.0)
            await physics_frame
            if amai.get_jump_count() > previous_jump_count:
                previous_jump_count = amai.get_jump_count()
                takeoffs.append(amai.global_position)
            if amai.is_route_complete():
                completion_frame = frame
                break

        var landings := amai.get_landing_history()
        _check(completion_frame >= 0, "Run %02d did not complete Segment 1" % (run_index + 1))
        _check(takeoffs.size() == 4, "Run %02d recorded %d/4 takeoffs" % [run_index + 1, takeoffs.size()])
        _check(landings.size() == 5, "Run %02d recorded %d/5 landings" % [run_index + 1, landings.size()])
        _check(amai.get_fall_recovery_count() == 0, "Run %02d needed %d emergency fall recoveries" % [run_index + 1, amai.get_fall_recovery_count()])

        if landings.size() == 5:
            if baseline_landings.is_empty():
                baseline_landings = landings.duplicate()
            for anchor_index in 5:
                landing_sums[anchor_index] += landings[anchor_index]
                maximum_repeat_drift = maxf(maximum_repeat_drift, landings[anchor_index].distance_to(baseline_landings[anchor_index]))

        run_lines.append("run=%02d complete=%s frame=%d recoveries=%d takeoffs=%s landings=%s" % [
            run_index + 1,
            str(completion_frame >= 0),
            completion_frame,
            amai.get_fall_recovery_count(),
            str(takeoffs),
            str(landings),
        ])

    var mean_landings: Array[Vector2] = []
    mean_landings.resize(5)
    for anchor_index in 5:
        mean_landings[anchor_index] = landing_sums[anchor_index] / float(RUN_COUNT)
    _check(maximum_repeat_drift <= 1.0, "30-run landing drift exceeded 1px: %.3f" % maximum_repeat_drift)

    for line in run_lines:
        print("[AMAI S1 30-RUN] %s" % line)
    print("[AMAI S1 30-RUN SUMMARY] mean_landings=%s max_repeat_drift=%.3f" % [str(mean_landings), maximum_repeat_drift])

    scene.queue_free()
    await process_frame
    _finish()


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    if failures.is_empty():
        print("[AMAI S1 30-RUN PASS] Segment 1 completed 30/30 physical routes with four jumps, five landings, and zero emergency recoveries.")
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI S1 30-RUN FAIL] %s" % failure)
    quit(1)
