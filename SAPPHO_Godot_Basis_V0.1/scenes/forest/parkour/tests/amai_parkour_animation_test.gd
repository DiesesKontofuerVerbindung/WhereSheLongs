extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const VISUAL_SCENE := "res://scenes/forest/parkour/characters/amai_parkour_visual.tscn"
const ANIMATION_SCRIPT := "res://scenes/forest/parkour/characters/amai_parkour_animation.gd"
const TARGET_CHARACTER_HEIGHT := 170.0
const EXPECTED_VISUAL_SCALE := Vector2(0.15, 0.15)
const EXPECTED_FOOT_Y := 16.0

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed_visual := load(VISUAL_SCENE) as PackedScene
    _check(packed_visual != null, "Amai animation visual failed to load")
    if packed_visual == null:
        _finish()
        return

    var runner := CharacterBody2D.new()
    var visual := packed_visual.instantiate() as AnimatedSprite2D
    runner.add_child(visual)
    root.add_child(runner)
    await process_frame
    await physics_frame

    _check(visual.sprite_frames.has_animation(&"idle"), "Idle animation is missing")
    _check(visual.sprite_frames.has_animation(&"run_start"), "Run-start animation is missing")
    _check(visual.sprite_frames.has_animation(&"run"), "Run loop is missing")
    _check(visual.sprite_frames.get_frame_count(&"idle") == 60, "Idle loop must contain 60 sampled frames")
    _check(visual.sprite_frames.get_frame_count(&"run_start") == 21, "Run-start must contain 21 sampled frames")
    _check(visual.sprite_frames.get_frame_count(&"run") == 14, "Run loop must contain 14 sampled frames")
    _check(visual.sprite_frames.get_animation_loop(&"idle"), "Idle animation is not looping")
    _check(not visual.sprite_frames.get_animation_loop(&"run_start"), "Run-start animation must play once")
    _check(visual.sprite_frames.get_animation_loop(&"run"), "Run animation is not looping")
    _check(visual.animation == &"idle", "Stationary Amai did not start in idle")
    _check(_all_frames_use_source_canvas(visual.sprite_frames), "Animation frames lost the 720x1280 source canvas")
    _check(visual.scale.is_equal_approx(EXPECTED_VISUAL_SCALE), "Amai visual scale no longer matches the marked-line target")
    var idle_texture := visual.sprite_frames.get_frame_texture(&"idle", 0)
    var idle_used_rect := idle_texture.get_image().get_used_rect()
    var visible_height := float(idle_used_rect.size.y) * visual.scale.y
    var foot_y := visual.position.y + float(idle_used_rect.end.y - idle_texture.get_height() / 2) * visual.scale.y
    _check(absf(visible_height - TARGET_CHARACTER_HEIGHT) <= 12.0, "Amai no longer matches the marked-line character height")
    _check(is_equal_approx(foot_y, EXPECTED_FOOT_Y), "Scaled Amai feet are no longer anchored to the physical floor")

    runner.velocity = Vector2(300.0, 0.0)
    await physics_frame
    await physics_frame
    _check(visual.animation == &"run_start", "Movement did not enter Amai's run-start animation")
    _check(not visual.flip_h, "Rightward movement must use the source-facing direction")

    await create_timer(0.30).timeout
    runner.velocity = Vector2.ZERO
    await physics_frame
    _check(visual.animation == &"run_start", "A one-frame route-anchor pause reset Amai to idle")
    runner.velocity = Vector2(300.0, 0.0)
    await create_timer(0.50).timeout
    _check(visual.animation == &"run", "Run-start did not reach Amai's run loop within a normal route leg")

    runner.velocity = Vector2(-300.0, 0.0)
    await physics_frame
    await physics_frame
    _check(visual.flip_h, "Leftward movement did not flip Amai's animation")

    runner.velocity = Vector2.ZERO
    await create_timer(0.18).timeout
    await physics_frame
    _check(visual.animation == &"idle", "Stopping did not return Amai to idle")
    runner.queue_free()

    var packed_parkour := load(PARKOUR_SCENE) as PackedScene
    _check(packed_parkour != null, "Parkour Prototype failed to load with Amai's animation")
    if packed_parkour != null:
        var parkour := packed_parkour.instantiate()
        root.add_child(parkour)
        await process_frame
        parkour.active = false
        var amai_visual := parkour.get_node("AmaiPlaceholder/AmaiSprite")
        var echo_visual := parkour.get_node("AmaiEcho/AmaiSprite")
        _check(_is_amai_animation(amai_visual), "AmaiPlaceholder still uses the static sprite")
        _check(_is_amai_animation(echo_visual), "AmaiEcho still uses the static sprite")
        var action_controller := parkour.get_node("AmaiEcho/RunnerActionController") as RunnerActionController
        _check(action_controller.visual_path == NodePath("../AmaiSprite"), "Amai Echo slide controller lost its visual hook")
        parkour.queue_free()

    _finish()


func _all_frames_use_source_canvas(frames: SpriteFrames) -> bool:
    for animation_name in [&"idle", &"run_start", &"run"]:
        for frame_index in range(frames.get_frame_count(animation_name)):
            var texture := frames.get_frame_texture(animation_name, frame_index)
            if texture == null or texture.get_size() != Vector2(720.0, 1280.0):
                return false
    return true


func _is_amai_animation(node: Node) -> bool:
    return (
        node is AnimatedSprite2D
        and node.get_script() != null
        and node.get_script().resource_path == ANIMATION_SCRIPT
    )


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    if failures.is_empty():
        print("[AMAI ANIMATION PASS] Idle, run-start, run loop, facing, source canvas, and both Parkour integrations passed.")
        quit(0)
        return
    for failure in failures:
        push_error("[AMAI ANIMATION FAIL] %s" % failure)
    quit(1)
