extends "res://shared/interaction/interactable.gd"

@export_file("*.tscn") var target_scene: String
@export var set_flag_on_use: StringName
@export var set_flag_value: bool = true


func interact(_actor: Node) -> void:
    if target_scene.is_empty():
        push_warning("ScenePortal has no target_scene.")
        return

    if not set_flag_on_use.is_empty():
        GameState.set_flag(set_flag_on_use, set_flag_value)

    SceneManager.change_scene(target_scene)
