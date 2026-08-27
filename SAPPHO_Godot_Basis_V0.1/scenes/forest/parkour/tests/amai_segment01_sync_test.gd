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

    var player: CharacterBody2D = scene.get_node("Player")
    var amai: AmaiParkourPlaceholder = scene.get_node("AmaiPlaceholder")
    scene.active = false
    player.set_physics_process(false)
    amai.set_physics_process(true)
    player.global_position.x = 1200.0
    amai.reset_to_segment(1)

    var reached_mid_route := await _wait_for_guide_index(amai, 2, 360)
    _check(reached_mid_route, "Amai did not reach the Segment 1 mid-route anchor")

    var recovery_anchor_index := amai.get_guide_index()
    var recovery_anchor := amai.guide_root.get_node("Segment01Guide").get_child(recovery_anchor_index) as Marker2D
    amai.global_position.y = amai.segment_one_fall_recovery_y + 20.0
    await physics_frame
    _check(amai.get_guide_index() == recovery_anchor_index, "Amai lost Segment 1 progress during fall recovery")
    _check(amai.global_position.distance_to(recovery_anchor.global_position) <= 1.0, "Amai did not recover to its last confirmed Segment 1 landing")
    _check(amai.get_fall_recovery_count() == 1, "Amai fall recovery was not recorded exactly once")
    player.global_position.x = 330.0
    amai.hold_for_player_recovery()
    for frame in 4:
        await physics_frame
    report.append("fall_recovery index=%d p=(%.1f,%.1f) count=%d" % [
        amai.get_guide_index(),
        amai.global_position.x,
        amai.global_position.y,
        amai.get_fall_recovery_count(),
    ])

    var pre_fall_index := amai.get_guide_index()
    var pre_fall_position := amai.global_position
    var pre_fall_landings := amai.get_landing_history().size()

    scene.respawn(true)
    await physics_frame
    var held_position := amai.global_position
    for frame in 90:
        await physics_frame

    _check(amai.is_waiting_for_player_recovery(), "Amai did not enter recovery hold after Xiaoling respawned")
    _check(amai.get_guide_index() == pre_fall_index, "Amai restarted or advanced its guide while Xiaoling recovered")
    _check(amai.global_position.distance_to(held_position) <= 1.0, "Amai drifted away from its pre-fall landing")
    _check(amai.global_position.distance_to(pre_fall_position) <= 2.0, "Amai returned to the Segment 1 spawn instead of holding position")
    _check(amai.get_landing_history().size() >= pre_fall_landings, "Amai landing history was reset after Xiaoling fell")
    report.append("respawn_hold index=%d p=(%.1f,%.1f) drift=%.2f" % [
        amai.get_guide_index(),
        amai.global_position.x,
        amai.global_position.y,
        amai.global_position.distance_to(held_position),
    ])

    player.global_position.x = amai.global_position.x - 100.0
    var reached_j4 := await _wait_for_guide_index(amai, 4, 360)
    _check(reached_j4, "Amai did not resume after Xiaoling caught up")
    _check(not amai.is_segment_one_exit_released(), "Amai left J4 before Xiaoling landed there")

    var j4_wait_position := amai.global_position
    for frame in 60:
        await physics_frame
    _check(amai.global_position.distance_to(j4_wait_position) <= 1.0, "Amai did not wait on J4 for Xiaoling")

    var j4 = scene.get_platform(&"J4")
    player.global_position = j4.get_respawn_position()
    scene.call("_on_platform_landed", &"J4")
    var escort_start_x := amai.global_position.x
    for frame in 90:
        player.global_position.x += 4.0
        await physics_frame
        if amai.global_position.x >= escort_start_x + 120.0:
            break
    _check(amai.is_segment_one_exit_released(), "J4 landing did not release Amai's shared exit")
    _check(amai.global_position.x >= escort_start_x + 120.0, "Amai stayed frozen after Xiaoling landed on J4")
    _check(amai.global_position.x - player.global_position.x <= amai.segment_one_escort_lead + 5.0, "Amai outran Xiaoling during the shared exit")
    report.append("j4_wait=(%.1f,%.1f) escort_x=%.1f player_x=%.1f lead=%.1f" % [
        j4_wait_position.x,
        j4_wait_position.y,
        amai.global_position.x,
        player.global_position.x,
        amai.global_position.x - player.global_position.x,
    ])

    scene.queue_free()
    await process_frame
    _finish()


func _wait_for_guide_index(amai: AmaiParkourPlaceholder, target_index: int, max_frames: int) -> bool:
    for frame in max_frames:
        await physics_frame
        if amai.get_guide_index() >= target_index:
            return true
    return false


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    for line in report:
        print("[AMAI S1 SYNC] %s" % line)
    if failures.is_empty():
        print("[AMAI S1 SYNC PASS] Amai preserves progress on respawn, waits on J4, and escorts Xiaoling to Segment 2.")
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI S1 SYNC FAIL] %s" % failure)
    quit(1)
