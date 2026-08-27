extends Node

signal scene_change_started(scene_path: String)
signal scene_change_failed(scene_path: String, error_code: int)

var current_scene_path: String = ""


func change_scene(scene_path: String) -> bool:
    if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
        push_error("SceneManager: scene does not exist: %s" % scene_path)
        scene_change_failed.emit(scene_path, ERR_FILE_NOT_FOUND)
        return false

    scene_change_started.emit(scene_path)
    var error := get_tree().change_scene_to_file(scene_path)
    if error != OK:
        push_error("SceneManager: failed to change scene: %s (error %s)" % [scene_path, error])
        scene_change_failed.emit(scene_path, error)
        return false

    current_scene_path = scene_path
    return true
