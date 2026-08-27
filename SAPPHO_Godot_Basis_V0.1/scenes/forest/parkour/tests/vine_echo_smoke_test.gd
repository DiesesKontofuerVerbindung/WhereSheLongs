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
    _test_gate_index_survives_pause_and_frame_variation(coordinator)

    scene.queue_free()
    await process_frame

    if failures.is_empty():
        print("[VINE ECHO SMOKE PASS] Gate-indexed one-round Xiaomai echo, first-gate NONE bypass, input lock, and pause/frame stability passed.")
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
    _check(coordinator.get_player_history() == [1], "Fast UP then DOWN did not preserve the first action")
    _check(coordinator.get_xiaomai_history() == [0], "First gate echo must remain NONE")


func _test_gate_index_survives_pause_and_frame_variation(coordinator: Node) -> void:
    coordinator.reset_rounds()
    coordinator.debug_enter_gate(0)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN)
    coordinator.debug_pass_gate(0)
    root.get_tree().paused = true
    _check(coordinator.current_gate_index == 1 and coordinator.previous_player_action == VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.DOWN, "Pause changed the stored gate-indexed action")
    root.get_tree().paused = false

    coordinator._physics_process(0.25)
    coordinator.debug_enter_gate(1)
    coordinator.debug_submit_action(VINE_ECHO_COORDINATOR_SCRIPT.RunnerAction.UP)
    coordinator.debug_pass_gate(1)
    _check(coordinator.get_player_history() == [2, 1], "Frame variation changed Player gate ordering")
    _check(coordinator.get_xiaomai_history() == [0, 2], "Frame variation changed Xiaomai from previous-gate echo")


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
