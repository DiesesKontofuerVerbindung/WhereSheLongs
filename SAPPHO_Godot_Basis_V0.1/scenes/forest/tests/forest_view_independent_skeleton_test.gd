extends SceneTree

const ForestController = preload("res://scenes/forest/forest_sequence_controller.gd")

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _check(condition: bool, message: String) -> void:
    if condition:
        print("[FOREST SKELETON PASS] %s" % message)
    else:
        failures.append(message)
        push_error("[FOREST SKELETON FAIL] %s" % message)


func _run() -> void:
    var forest := (load("res://scenes/forest/forest.tscn") as PackedScene).instantiate()
    root.add_child(forest)
    current_scene = forest
    await process_frame

    var controller = forest.get_node("ForestSequenceController")
    var player = forest.get_node("Player")
    var amai_encounter = forest.get_node("Characters/AmaiEncounter")
    var waterfall = forest.get_node("Gameplay/WaterfallSequence")
    var drowning = forest.get_node("Gameplay/DrowningController")
    var rescue = forest.get_node("Characters/MysteryGirlRescue")
    var collapse = forest.get_node("Gameplay/WorldCollapse")

    controller.debug_jump(ForestController.ForestState.MEET_AMAI)
    _check(amai_encounter.copy_id == &"forest.amai.encounter", "Narrative beat keeps a copy ID without runtime dialogue")
    amai_encounter.complete()
    _check(controller.current_state == ForestController.ForestState.DECIDE_FOLLOW, "Amai encounter reports completion to the main controller")
    amai_encounter.complete()
    _check(controller.current_state == ForestController.ForestState.DECIDE_FOLLOW, "Narrative completion is consumed only once")

    waterfall.complete()
    _check(controller.current_state == ForestController.ForestState.DECIDE_FOLLOW, "Out-of-order sequence events cannot skip the story")
    controller.debug_jump(ForestController.ForestState.WATERFALL_INTRO)
    waterfall.complete()
    _check(controller.current_state == ForestController.ForestState.WATERFALL_JUMP, "Waterfall keeps a player-confirmed transition socket")

    controller.debug_jump(ForestController.ForestState.DROWNING)
    _check(drowning.active, "Entering DROWNING starts the breath sequence")
    drowning.consume_breath(drowning.maximum_breath)
    _check(controller.current_state == ForestController.ForestState.GIRL_RESCUE, "Breath depletion advances to rescue without reloading")
    rescue.complete()
    _check(controller.current_state == ForestController.ForestState.LAKE_DIALOGUE, "Rescue completion advances to lake dialogue")

    controller.debug_jump(ForestController.ForestState.WORLD_COLLAPSE)
    collapse.complete()
    _check(controller.current_state == ForestController.ForestState.FOREST_END, "World collapse exposes the final transition socket")

    var trigger := (load("res://scenes/forest/forest_sequence_trigger.tscn") as PackedScene).instantiate()
    trigger.trigger_id = &"entry_trigger"
    trigger.expected_state = ForestController.ForestState.ENTER_FOREST
    trigger.next_state = ForestController.ForestState.LIGHT_GUIDE
    trigger.transition_requested.connect(controller.request_transition)
    forest.get_node("Gameplay").add_child(trigger)
    await process_frame

    controller.restart_sequence()
    trigger.activate(player)
    _check(controller.current_state == ForestController.ForestState.LIGHT_GUIDE, "Sequence Trigger advances from its expected state")
    trigger.activate(player)
    _check(controller.current_state == ForestController.ForestState.LIGHT_GUIDE, "Sequence Trigger cannot fire twice")

    forest.queue_free()
    await process_frame

    if failures.is_empty():
        print("[FOREST SKELETON PASS] View-independent trigger, inactive copy slots, scripted beats, and drowning flow are operational.")
        quit(0)
        return

    quit(1)
