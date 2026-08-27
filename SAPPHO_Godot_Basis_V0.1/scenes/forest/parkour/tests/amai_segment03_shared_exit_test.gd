extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"

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
    await scene.debug_jump_to_segment(3)
    await physics_frame

    var player: CharacterBody2D = scene.get_node("Player")
    var amai: AmaiParkourPlaceholder = scene.get_node("AmaiPlaceholder")
    scene.active = false
    player.set_physics_process(false)
    amai.set_physics_process(true)
    player.global_position.x = 3970.0
    amai.reset_to_segment(3)
    amai.record_choice(&"WAIT")
    await physics_frame

    var max_lead := amai.global_position.x - player.global_position.x
    var max_trail := player.global_position.x - amai.global_position.x
    for frame in 1200:
        player.global_position.x = minf(5700.0, player.global_position.x + 5.0)
        await physics_frame
        max_lead = maxf(max_lead, amai.global_position.x - player.global_position.x)
        max_trail = maxf(max_trail, player.global_position.x - amai.global_position.x)
        if amai.is_route_complete():
            break
    _check(amai.is_route_complete(), "Amai did not reach the final Segment 3 platform")
    _check(max_lead <= 30.0, "Amai moved ahead of Xiaoling instead of following her")
    _check(max_trail >= amai.segment_three_follow_distance, "Segment 3 never formed a visible Xiaoling-first trailing gap")

    player.global_position.x = 5700.0
    scene.active = true
    scene.call("_on_segment_03_finish_entered", player)
    await physics_frame
    _check(amai.is_segment_three_exit_released(), "Amai did not begin the final catch-up after Xiaoling reached the exit")

    var escort_start := amai.global_position
    var last_segment_three_position := escort_start
    for frame in 240:
        if scene.current_segment != 3:
            break
        await physics_frame
        if scene.current_segment == 3:
            last_segment_three_position = amai.global_position

    _check(amai.global_position.x > escort_start.x + 40.0, "Amai did not catch up after Xiaoling reached the exit")
    _check(last_segment_three_position.x >= amai.segment_three_exit_x - amai.arrival_tolerance, "Amai had not reached the shared exit before Segment 4")
    _check(scene.current_segment == 4, "Shared exit did not enter WATERFALL_INTRO")
    _check(absf(amai.global_position.x - player.global_position.x) <= 180.0, "Amai did not arrive beside Xiaoling in Segment 4")
    report.append("escort_start=(%.1f,%.1f) exit=(%.1f,%.1f) max_lead=%.1f max_trail=%.1f waterfall=(%.1f,%.1f)" % [
        escort_start.x,
        escort_start.y,
        last_segment_three_position.x,
        last_segment_three_position.y,
        max_lead,
        max_trail,
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
        print("[AMAI S3 SHARED EXIT] %s" % line)
    if failures.is_empty():
        print("[AMAI S3 SHARED EXIT PASS] Xiaoling leads Segment 3, Amai follows behind on the chosen route, catches up at the exit, and enters WATERFALL_INTRO beside her.")
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI S3 SHARED EXIT FAIL] %s" % failure)
    quit(1)
