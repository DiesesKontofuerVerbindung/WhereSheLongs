extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const VISUAL_SCENE := "res://scenes/forest/parkour/characters/xiaoling_parkour_visual.tscn"
const ANIMATION_SCRIPT := "res://scenes/forest/parkour/characters/xiaoling_parkour_animation.gd"
const TARGET_CHARACTER_HEIGHT := 170.0
const EXPECTED_VISUAL_SCALE := Vector2(0.15, 0.15)
const EXPECTED_FOOT_Y := 16.0

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed_visual := load(VISUAL_SCENE) as PackedScene
    _check(packed_visual != null, "Xiaoling animation visual failed to load")
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
    _check(visual.sprite_frames.has_animation(&"jump"), "Jump animation is missing")
    _check(visual.sprite_frames.get_frame_count(&"idle") == 8, "Idle loop must contain 8 frames")
    _check(visual.sprite_frames.get_frame_count(&"run_start") == 9, "Run-start must contain 9 frames")
    _check(visual.sprite_frames.get_frame_count(&"run") == 9, "Run loop must use frames 1-9 and return directly to frame 1")
    _check(visual.sprite_frames.get_frame_count(&"jump") == 22, "Jump animation must contain 22 sampled frames")
    _check(visual.sprite_frames.get_animation_loop(&"idle"), "Idle animation is not looping")
    _check(not visual.sprite_frames.get_animation_loop(&"run_start"), "Run-start animation must play once")
    _check(visual.sprite_frames.get_animation_loop(&"run"), "Run animation is not looping")
    _check(not visual.sprite_frames.get_animation_loop(&"jump"), "Jump animation must not loop")
    _check(visual.animation == &"idle", "Stationary Xiaoling did not start in idle")
    _check(_all_frames_normalized(visual.sprite_frames), "Animation frames are not normalized to one canvas and foot baseline")
    _check(visual.scale.is_equal_approx(EXPECTED_VISUAL_SCALE), "Xiaoling visual scale no longer matches the marked-line target")
    var idle_texture := visual.sprite_frames.get_frame_texture(&"idle", 0)
    var idle_used_rect := idle_texture.get_image().get_used_rect()
    var visible_height := float(idle_used_rect.size.y) * visual.scale.y
    var foot_y := visual.position.y + float(idle_used_rect.end.y - idle_texture.get_height() / 2) * visual.scale.y
    _check(absf(visible_height - TARGET_CHARACTER_HEIGHT) <= 12.0, "Xiaoling no longer matches the marked-line character height")
    _check(is_equal_approx(foot_y, EXPECTED_FOOT_Y), "Scaled Xiaoling feet are no longer anchored to the physical floor")

    runner.velocity = Vector2(300.0, 0.0)
    await physics_frame
    await physics_frame
    _check(visual.animation == &"run_start", "Movement did not enter the run-start anticipation")
    _check(not visual.flip_h, "Rightward movement must use the source-facing direction")

    await create_timer(0.7).timeout
    _check(visual.animation == &"run", "Run-start did not transition into the run loop")

    runner.velocity = Vector2(-300.0, 0.0)
    await physics_frame
    await physics_frame
    _check(visual.flip_h, "Leftward movement did not flip the animation")

    runner.velocity = Vector2.ZERO
    await physics_frame
    await physics_frame
    _check(visual.animation == &"idle", "Stopping did not return to the idle loop")

    runner.velocity = Vector2(300.0, -900.0)
    await physics_frame
    await physics_frame
    _check(visual.animation == &"jump", "Upward velocity did not enter the jump animation")
    _check(not visual.flip_h, "Rightward jump must use the source-facing direction")

    runner.velocity = Vector2(-300.0, -400.0)
    await physics_frame
    await physics_frame
    _check(visual.flip_h, "Leftward airborne movement did not flip the jump animation")

    await create_timer(1.2).timeout
    _check(visual.animation == &"jump", "Airborne jump state did not hold after the one-shot animation finished")
    _check(not visual.is_playing(), "Finished jump animation should hold its final frame instead of looping")
    runner.queue_free()

    var packed_parkour := load(PARKOUR_SCENE) as PackedScene
    _check(packed_parkour != null, "Parkour Prototype failed to load with the animation visual")
    if packed_parkour != null:
        var parkour := packed_parkour.instantiate()
        root.add_child(parkour)
        await process_frame
        parkour.active = false
        var integrated_visual := parkour.get_node("Player/XiaolingSprite")
        _check(
            integrated_visual is AnimatedSprite2D
            and integrated_visual.get_script() != null
            and integrated_visual.get_script().resource_path == ANIMATION_SCRIPT,
            "Parkour Player still uses the static Xiaoling sprite"
        )
        var action_controller := parkour.get_node("Player/RunnerActionController") as RunnerActionController
        _check(action_controller.visual_path == NodePath("../XiaolingSprite"), "Slide controller lost its Xiaoling visual hook")
        parkour.queue_free()

    _finish()


func _all_frames_normalized(frames: SpriteFrames) -> bool:
    for animation_name in [&"idle", &"run_start", &"run", &"jump"]:
        for frame_index in range(frames.get_frame_count(animation_name)):
            var texture := frames.get_frame_texture(animation_name, frame_index)
            if texture == null or texture.get_size() != Vector2(800.0, 1280.0):
                return false
            var image := texture.get_image()
            if image == null or image.get_used_rect().end.y != 1200:
                return false
    return true


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _finish() -> void:
    if failures.is_empty():
        print("[XIAOLING ANIMATION PASS] Idle, run-start, run, one-shot jump, facing, normalized feet, and Parkour integration passed.")
        quit(0)
        return
    for failure in failures:
        push_error("[XIAOLING ANIMATION FAIL] %s" % failure)
    quit(1)
