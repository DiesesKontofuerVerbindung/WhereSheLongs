extends SceneTree

const VINE_SEGMENT_PATH := "res://scenes/forest/parkour/vine_segment_prototype.tscn"
const VINE_ECHO_COORDINATOR_SCRIPT := preload("res://scenes/forest/parkour/vine_echo/vine_echo_coordinator.gd")
const RUNNER_ACTION_CONTROLLER_SCRIPT := preload("res://scenes/forest/parkour/vine_echo/runner_action_controller.gd")
const VINE_DECISION_GATE_SCRIPT := preload("res://scenes/forest/parkour/vine_echo/vine_decision_gate.gd")

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load(VINE_SEGMENT_PATH) as PackedScene
    _check(packed != null, "Vine Segment prototype failed to load")
    if packed == null:
        quit(1)
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame

    var player: CharacterBody2D = scene.get_node("Player")
    var xiaomai: CharacterBody2D = scene.get_node("Xiaomai")
    var coordinator = scene.get_node("VineEchoCoordinator")
    var player_runner = scene.get_node("Player/RunnerActionController")
    var xiaomai_runner = scene.get_node("Xiaomai/RunnerActionController")
    var gate_01 = scene.get_node("Gate01")
    var gate_02 = scene.get_node("Gate02")
    var gate_03 = scene.get_node("Gate03")
    var gate_04 = scene.get_node("Gate04")

    _check(player.scene_file_path == "res://shared/player/player.tscn", "Vine Segment does not reuse the Shared Player")
    _check(player_runner.get_script() == xiaomai_runner.get_script(), "Player and Xiaomai do not share RunnerActionController")
    _check(player_runner.run_speed == xiaomai_runner.run_speed, "Player and Xiaomai horizontal speeds differ")
    _check(gate_01.has_first_round_echo_bypass(xiaomai), "Gate 01 does not bypass Xiaomai's NONE echo")
    _check(not gate_02.has_first_round_echo_bypass(xiaomai), "Only Gate 01 may bypass Xiaomai")
    for gate in [gate_01, gate_02, gate_03, gate_04]:
        _check(gate.has_fixed_ground_route(xiaomai), "%s lets Xiaomai land on the floating UP platform" % gate.name)
    _check(coordinator.get_echo_fixed_route().size() == 6, "Fixed Xiaomai route must contain spawn, four waits, and the exit anchor")

    _test_sequence_one(coordinator)
    _test_sequence_two(coordinator)
    _test_first_input_wins(coordinator)
    _test_pre_gate_input_buffer(coordinator)
    _test_action_waits_for_execution_line(coordinator)
    _test_same_gate_reentry_preserves_and_repeats_action(coordinator, player_runner)
    _test_same_gate_landing_retry(coordinator, player, player_runner)
    _test_airborne_action_buffer(xiaomai, xiaomai_runner)
    _test_gate_index_survives_pause_and_frame_variation(coordinator)

    scene.queue_free()
    await process_frame

    if failures.is_empty():
        print("[VINE ECHO SMOKE PASS] Gate-indexed echo, pre-gate/airborne input buffers, first-input lock, and pause/frame stability passed.")
        quit(0)
        return
    for failure in failures:
        push_error("[VINE ECHO SMOKE FAIL] %s" % failure)
    quit(1)


func _test_sequence_one(coordinator: Node) -> void:
    coordinator.debug_run_sequence([
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP,
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN,
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP,
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN,
    ])
    _check(coordinator.get_player_history() == [1, 2, 1, 2], "Test 1 Player history is not UP DOWN UP DOWN")
    _check(coordinator.get_xiaomai_history() == [0, 1, 2, 1], "Test 1 Xiaomai history is not NONE UP DOWN UP")


func _test_sequence_two(coordinator: Node) -> void:
    coordinator.debug_run_sequence([
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP,
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP,
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN,
        VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN,
    ])
    _check(coordinator.get_player_history() == [1, 1, 2, 2], "Test 2 Player history is not UP UP DOWN DOWN")
    _check(coordinator.get_xiaomai_history() == [0, 1, 1, 2], "Test 2 Xiaomai history is not NONE UP UP DOWN")


func _test_first_input_wins(coordinator: Node) -> void:
    coordinator.reset_rounds()
    coordinator.debug_enter_gate(0)
    _check(coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP), "Gate did not accept the first UP input")
    _check(not coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN), "Gate accepted DOWN after it had already locked UP")
    coordinator.debug_execute_gate(0)
    _check(coordinator.get_player_history() == [1], "Fast UP then DOWN did not preserve the first action")
    _check(coordinator.get_xiaomai_history() == [0], "First gate echo must remain NONE")


func _test_pre_gate_input_buffer(coordinator: Node) -> void:
    coordinator.reset_rounds()
    _check(coordinator.debug_buffer_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN), "Pre-gate DOWN input was not buffered")
    _check(not coordinator.debug_buffer_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP), "A second pre-gate input overwrote the first input")
    coordinator.debug_enter_gate(0)
    coordinator._physics_process(1.0 / 60.0)
    _check(coordinator.action_locked, "Buffered pre-gate DOWN was not locked on Gate entry")
    _check(coordinator.get_player_history().is_empty(), "Buffered pre-gate DOWN executed before the action line")
    coordinator.debug_execute_gate(0)
    _check(coordinator.get_player_history() == [2], "Buffered pre-gate DOWN was not committed on Gate entry")


func _test_action_waits_for_execution_line(coordinator: Node) -> void:
    coordinator.reset_rounds()
    coordinator.debug_enter_gate(0)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP)
    _check(coordinator.action_locked, "UP selection did not lock in the decision zone")
    _check(coordinator.get_player_history().is_empty(), "UP executed inside the early decision zone")
    coordinator.debug_execute_gate(0)
    _check(coordinator.get_player_history() == [1], "UP did not execute at the action line")
    _check(coordinator.get_xiaomai_history() == [0], "Gate 01 action line did not preserve Amai NONE")


func _test_same_gate_reentry_preserves_and_repeats_action(coordinator: Node, player_runner: Node) -> void:
    coordinator.reset_rounds()
    coordinator.debug_enter_gate(0)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN)
    coordinator.debug_execute_gate(0)
    var history_before: Array[int] = coordinator.get_player_history()
    coordinator.debug_enter_gate(0)
    _check(coordinator.action_locked, "Re-entering the same DecisionZone cleared the locked DOWN action")
    _check(coordinator.get_player_history() == history_before, "Re-entering the same DecisionZone duplicated Player history")
    player_runner.debug_set_slide(false)
    coordinator.debug_execute_gate(0)
    _check(player_runner.is_sliding, "Re-entering the ActionZone did not repeat the locked DOWN slide")
    _check(coordinator.get_player_history() == history_before, "Repeated physical DOWN execution duplicated Gate history")
    coordinator.debug_pass_gate(0)
    _check(coordinator.current_gate_index == 1, "Same-Gate re-entry prevented the Gate from finishing")


func _test_same_gate_landing_retry(coordinator: Node, player: CharacterBody2D, player_runner: Node) -> void:
    coordinator.reset_rounds()
    coordinator.debug_enter_gate(0)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP)
    coordinator.debug_execute_gate(0)
    var player_history_before: Array[int] = coordinator.get_player_history()
    var xiaomai_history_before: Array[int] = coordinator.get_xiaomai_history()
    player.velocity.y = 0.0
    _check(coordinator.debug_retry_locked_player_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP), "Locked UP could not be retried after landing")
    _check(player.velocity.y == -player_runner.jump_impulse, "Locked UP retry did not produce a physical jump")
    _check(not coordinator.debug_retry_locked_player_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN), "Same-Gate retry changed the locked UP choice")
    _check(coordinator.get_player_history() == player_history_before, "Same-Gate UP retry duplicated Player history")
    _check(coordinator.get_xiaomai_history() == xiaomai_history_before, "Same-Gate UP retry duplicated Amai echo history")


func _test_airborne_action_buffer(xiaomai: CharacterBody2D, runner: Node) -> void:
    xiaomai.global_position.y -= 80.0
    xiaomai.velocity = Vector2(0.0, 1.0)
    xiaomai.move_and_slide()
    xiaomai.velocity = Vector2.ZERO
    _check(not xiaomai.is_on_floor(), "Airborne action test did not leave the floor")
    runner.perform_action(RUNNER_ACTION_CONTROLLER_SCRIPT.RunnerAction.UP)
    _check(runner.get_queued_ground_action() == RUNNER_ACTION_CONTROLLER_SCRIPT.RunnerAction.UP, "Airborne UP was dropped instead of queued")
    runner.stop_run()
    runner.start_run(0.0)
    runner.perform_action(RUNNER_ACTION_CONTROLLER_SCRIPT.RunnerAction.DOWN)
    _check(runner.get_queued_ground_action() == RUNNER_ACTION_CONTROLLER_SCRIPT.RunnerAction.DOWN, "Airborne DOWN was dropped instead of queued")
    runner.stop_run()
    runner.start_run(0.0)


func _test_gate_index_survives_pause_and_frame_variation(coordinator: Node) -> void:
    coordinator.reset_rounds()
    coordinator.debug_enter_gate(0)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN)
    coordinator.debug_execute_gate(0)
    coordinator.debug_pass_gate(0)
    root.get_tree().paused = true
    _check(coordinator.current_gate_index == 1 and coordinator.previous_player_action == VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN, "Pause changed the stored gate-indexed action")
    root.get_tree().paused = false

    coordinator._physics_process(0.25)
    coordinator.debug_enter_gate(1)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP)
    coordinator.debug_execute_gate(1)
    coordinator.debug_pass_gate(1)
    _check(coordinator.get_player_history() == [2, 1], "Frame variation changed Player gate ordering")
    _check(coordinator.get_xiaomai_history() == [0, 2], "Frame variation changed Xiaomai from previous-gate echo")


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
