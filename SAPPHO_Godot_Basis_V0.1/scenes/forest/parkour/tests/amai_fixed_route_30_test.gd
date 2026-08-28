extends SceneTree

const PARKOUR_PATH := "res://scenes/forest/parkour/parkour_prototype.tscn"
const COORDINATOR_SCRIPT := preload("res://scenes/forest/parkour/vine_echo/vine_echo_coordinator.gd")
const RUN_COUNT := 30
var expected_route := PackedVector2Array([
    Vector2(2070.0, 584.0),
    Vector2(2122.0, 584.0),
    Vector2(2538.0, 584.0),
    Vector2(2946.0, 584.0),
    Vector2(3371.0, 584.0),
    Vector2(3820.0, 584.0),
])

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load(PARKOUR_PATH) as PackedScene
    _check(packed != null, "Parkour Prototype failed to load")
    if packed == null:
        quit(1)
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var coordinator = scene.get_node("VineEchoCoordinator")
    var xiaomai: CharacterBody2D = scene.get_node("AmaiEcho")
    var runner = scene.get_node("AmaiEcho/RunnerActionController")
    var route: PackedVector2Array = coordinator.get_echo_fixed_route()

    _check(route == expected_route, "Full Segment 02 fixed route changed unexpectedly: %s" % str(route))
    for gate_index in 4:
        var gate = scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (gate_index + 1))
        _check(gate.has_fixed_ground_route(xiaomai), "Gate %d still lets Amai perch on its UP platform" % (gate_index + 1))
        _check(is_equal_approx(route[gate_index + 1].x, gate.global_position.x - 90.0), "Gate %d wait anchor is not fixed 90px before its obstacle" % (gate_index + 1))

    var coordinate_sums := PackedVector2Array()
    coordinate_sums.resize(route.size())
    var maximum_drift := 0.0
    for run_index in RUN_COUNT:
        var actions := _make_action_sequence(run_index)
        coordinator.begin_run()
        coordinator.debug_run_sequence(actions)
        _check_shifted_echo(coordinator, actions, run_index)

        var delta: float = [1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0][run_index % 3]
        var arrivals := _predict_fixed_route_arrivals(route, actions, runner, delta)
        for anchor_index in route.size():
            coordinate_sums[anchor_index] += arrivals[anchor_index]
            maximum_drift = maxf(maximum_drift, arrivals[anchor_index].distance_to(route[anchor_index]))
        coordinator.stop_run(false)

    var mean_route := PackedVector2Array()
    mean_route.resize(route.size())
    for anchor_index in route.size():
        mean_route[anchor_index] = coordinate_sums[anchor_index] / float(RUN_COUNT)
        _check(mean_route[anchor_index].distance_to(route[anchor_index]) <= 0.01, "30-run mean drifted at anchor %d" % anchor_index)
    _check(maximum_drift <= 0.01, "Fixed-route arrival drift exceeded tolerance: %.3f" % maximum_drift)

    print("[AMAI FIXED ROUTE 30-RUN PASS] mean=%s max_drift=%.3f actions=gate-indexed" % [str(mean_route), maximum_drift])
    scene.queue_free()
    await process_frame

    if failures.is_empty():
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI FIXED ROUTE 30-RUN FAIL] %s" % failure)
    quit(1)


func _make_action_sequence(run_index: int) -> Array[int]:
    var result: Array[int] = []
    for gate_index in 4:
        result.append(COORDINATOR_SCRIPT.RunnerAction.UP if (run_index + gate_index) % 2 == 0 else COORDINATOR_SCRIPT.RunnerAction.DOWN)
    return result


func _check_shifted_echo(coordinator: Node, actions: Array[int], run_index: int) -> void:
    var expected_echo: Array[int] = [COORDINATOR_SCRIPT.RunnerAction.NONE]
    expected_echo.append_array(actions.slice(0, actions.size() - 1))
    _check(coordinator.get_player_history() == actions, "Run %d changed Player action order" % (run_index + 1))
    _check(coordinator.get_xiaomai_history() == expected_echo, "Run %d broke NONE/A1/A2/A3 echo order" % (run_index + 1))


func _predict_fixed_route_arrivals(route: PackedVector2Array, actions: Array[int], runner: Node, delta: float) -> PackedVector2Array:
    var arrivals := PackedVector2Array([route[0], route[1]])
    for gate_index in actions.size():
        var start := route[gate_index + 1]
        var target := route[gate_index + 2]
        var echo_action: int = COORDINATOR_SCRIPT.RunnerAction.NONE if gate_index == 0 else actions[gate_index - 1]
        var position := start
        var vertical_velocity: float = -runner.jump_impulse if echo_action == COORDINATOR_SCRIPT.RunnerAction.UP else 0.0
        var safety_frames := 0
        while position.distance_to(target) > 0.01 and safety_frames < 600:
            position.x = minf(target.x, position.x + runner.run_speed * delta)
            if echo_action == COORDINATOR_SCRIPT.RunnerAction.UP and (position.y < target.y or vertical_velocity < 0.0):
                vertical_velocity = minf(vertical_velocity + runner.gravity * delta, 1100.0)
                position.y += vertical_velocity * delta
                if position.y >= target.y and vertical_velocity >= 0.0:
                    position.y = target.y
            else:
                position.y = target.y
            safety_frames += 1
        if safety_frames >= 600:
            _check(false, "Route simulation did not settle at gate %d" % (gate_index + 1))
        arrivals.append(position)
    return arrivals


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
