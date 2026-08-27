extends SceneTree

const REQUIRED_ACTIONS := [
    "move_left",
    "move_right",
    "move_up",
    "move_down",
    "interact",
    "look",
    "jump",
    "pause",
]

const REQUIRED_RESOURCES := [
    "res://shared/player/player.tscn",
    "res://shared/interaction/interactable.gd",
    "res://shared/dialogue/dialogue_ui.tscn",
    "res://shared/game_state/game_state.gd",
    "res://shared/scene_manager/scene_manager.gd",
    "res://scenes/test_room/test_room.tscn",
    "res://scenes/forest/forest.tscn",
    "res://scenes/wedding/wedding.tscn",
]

const SCENES_TO_ENTER_TREE := [
    "res://shared/player/player.tscn",
    "res://shared/dialogue/dialogue_ui.tscn",
    "res://scenes/test_room/test_room.tscn",
    "res://scenes/forest/forest.tscn",
    "res://scenes/wedding/wedding.tscn",
]

const REQUIRED_PLAYER_METHODS := [
    "set_control_mode",
    "use_normal_control",
    "lock_control",
    "use_external_control",
    "set_interaction_enabled",
    "set_external_velocity",
    "stop_external_movement",
]


func _initialize() -> void:
    call_deferred("_run_smoke_test")


func _run_smoke_test() -> void:
    var failures: Array[String] = []

    for action in REQUIRED_ACTIONS:
        if not InputMap.has_action(action):
            failures.append("Missing InputMap action: %s" % action)

    for path in REQUIRED_RESOURCES:
        if not ResourceLoader.exists(path):
            failures.append("Missing resource: %s" % path)

    for path in SCENES_TO_ENTER_TREE:
        var resource := load(path)
        if resource == null or not resource is PackedScene:
            failures.append("Failed to load PackedScene: %s" % path)
            continue

        var instance := (resource as PackedScene).instantiate()
        if instance == null:
            failures.append("Failed to instantiate scene: %s" % path)
            continue

        get_root().add_child(instance)
        await process_frame

        if path == "res://shared/player/player.tscn":
            for method_name in REQUIRED_PLAYER_METHODS:
                if not instance.has_method(method_name):
                    failures.append("Shared Player missing public method: %s" % method_name)

        instance.queue_free()
        await process_frame

    if failures.is_empty():
        print("[SMOKE PASS] Basis V0.1 resources entered the SceneTree and shared contracts are present.")
        quit(0)
        return

    for failure in failures:
        push_error("[SMOKE FAIL] %s" % failure)
    quit(1)
