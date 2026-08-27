extends SceneTree

const ForestController = preload("res://scenes/forest/forest_sequence_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _check(condition: bool, message: String) -> void:
    if condition:
        print("[FOREST T01 PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FOREST T01 FAIL] %s" % message)


func _run() -> void:
    var forest := (load("res://scenes/forest/forest.tscn") as PackedScene).instantiate()
    root.add_child(forest)
    current_scene = forest
    await process_frame

    var controller = forest.get_node("ForestSequenceController")
    var player = forest.get_node("Player")
    var debug_panel = forest.get_node("Debug/ForestDebugPanel")

    _check(
        controller.current_state == ForestController.ForestState.ENTER_FOREST,
        "Forest starts at ENTER_FOREST"
    )
    _check(not debug_panel.get_node("Panel").visible, "Debug panel starts hidden")

    var visited_states := [controller.current_state]
    while controller.advance():
        visited_states.append(controller.current_state)

    _check(visited_states.size() == controller.get_state_count(), "State machine visits all T01 states")
    _check(
        controller.current_state == ForestController.ForestState.FOREST_END,
        "State machine reaches FOREST_END"
    )

    controller.restart_sequence()
    _check(
        controller.trigger_once(&"light_guide_once", ForestController.ForestState.LIGHT_GUIDE),
        "A new trigger advances the sequence"
    )
    _check(
        not controller.trigger_once(&"light_guide_once", ForestController.ForestState.MEET_AMAI),
        "A consumed trigger cannot fire twice"
    )

    controller.debug_jump(ForestController.ForestState.PARKOUR)
    _check(player.control_mode == player.ControlMode.EXTERNAL, "PARKOUR hands movement to EXTERNAL control")
    _check(not player.interaction_enabled, "Gameplay hand-off disables shared interaction")

    controller.debug_jump(ForestController.ForestState.LAKE_DIALOGUE)
    _check(player.control_mode == player.ControlMode.LOCKED, "LAKE_DIALOGUE locks Player control")

    controller.debug_jump(ForestController.ForestState.STREAM_WALK)
    _check(player.control_mode == player.ControlMode.NORMAL, "STREAM_WALK restores NORMAL control")
    _check(player.interaction_enabled, "NORMAL control restores shared interaction")

    debug_panel.toggle_panel()
    _check(debug_panel.get_node("Panel").visible, "F1 panel toggle path opens the debug panel")
    debug_panel.jump_to_state(ForestController.ForestState.LAKE_INTRO)
    _check(
        controller.current_state == ForestController.ForestState.LAKE_INTRO,
        "Debug jump initializes the requested state"
    )

    forest.queue_free()
    await process_frame

    if failures.is_empty():
        print("[FOREST T01 PASS] Scene skeleton, state flow, trigger guard, Player hand-off, and debug jumps are operational.")
        quit(0)
        return

    quit(1)
