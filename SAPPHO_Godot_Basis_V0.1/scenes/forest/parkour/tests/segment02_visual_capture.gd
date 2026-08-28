extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const DEFAULT_OUTPUT := "user://segment02_v2_visual.png"


func _initialize() -> void:
    call_deferred("_capture")


func _capture() -> void:
    var arguments := OS.get_cmdline_user_args()
    var preview_mode := "--preview" in arguments
    var capture_size := Vector2i(1920, 1080)
    for argument in arguments:
        if argument.begins_with("--size="):
            var dimensions := argument.trim_prefix("--size=").split("x")
            if dimensions.size() == 2:
                capture_size = Vector2i(dimensions[0].to_int(), dimensions[1].to_int())
    var packed := load(PARKOUR_SCENE) as PackedScene
    if packed == null:
        push_error("[S2 VISUAL CAPTURE FAIL] Parkour Prototype failed to load")
        quit(1)
        return

    root.size = capture_size
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame
    await scene.debug_jump_to_segment(2)
    await physics_frame

    scene.get_node("VineEchoDebug").visible = false
    scene.get_node("ParkourDebug/CanvasLayer").visible = false
    if preview_mode:
        print("[S2 PREVIEW READY] Segment 02 is running with normal gameplay input.")
        return

    var player := scene.get_node("Player") as CharacterBody2D
    var player_camera := scene.get_node("Player/Camera2D") as Camera2D
    var design_camera := scene.get_node("DesignCamera") as Camera2D
    player_camera.enabled = false
    design_camera.enabled = true
    player.global_position = Vector2(2628.0, 584.0)
    player.velocity = Vector2.ZERO
    scene.set_physics_process(false)
    player.set_physics_process(false)
    await process_frame
    await process_frame
    await process_frame

    var output_path := DEFAULT_OUTPUT
    for argument in arguments:
        if argument.begins_with("--output="):
            output_path = argument.trim_prefix("--output=")
    var image := root.get_texture().get_image()
    var save_error := image.save_png(output_path)
    if save_error != OK:
        push_error("[S2 VISUAL CAPTURE FAIL] save_png returned %s for %s" % [save_error, output_path])
        quit(1)
        return
    print("[S2 VISUAL CAPTURE PASS] output=%s size=%dx%d roots=4" % [output_path, image.get_width(), image.get_height()])
    quit(0)
