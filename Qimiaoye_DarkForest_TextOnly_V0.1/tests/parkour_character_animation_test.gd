extends Node

const XIAOLING_VISUAL := preload("res://scenes/forest/parkour/characters/xiaoling_parkour_visual.tscn")
const AMAI_VISUAL := preload("res://scenes/forest/parkour/characters/amai_parkour_visual.tscn")

var _failures := 0


func _ready() -> void:
    await get_tree().process_frame
    await _verify_xiaoling()
    await _verify_amai()
    if _failures == 0:
        print("[PARKOUR CHARACTER ANIMATION TEST] PASS Xiaoling=151/13/30/22 Amai=60/21/14/77")
        get_tree().quit(0)
    else:
        push_error("[PARKOUR CHARACTER ANIMATION TEST] FAIL count=%d" % _failures)
        get_tree().quit(1)


func _verify_xiaoling() -> void:
    var runner := CharacterBody2D.new()
    var visual := XIAOLING_VISUAL.instantiate() as AnimatedSprite2D
    runner.add_child(visual)
    add_child(runner)
    await get_tree().process_frame
    _expect_animation(visual, &"idle", 151, 30.0, true, "Xiaoling")
    _expect_animation(visual, &"run_start", 13, 30.0, false, "Xiaoling")
    _expect_animation(visual, &"run", 30, 30.0, true, "Xiaoling")
    _expect_animation(visual, &"jump", 22, 20.0, false, "Xiaoling")
    _expect_texture_size(visual, &"idle", 0, Vector2i(720, 1280), "Xiaoling idle first")
    _expect_texture_size(visual, &"run", 29, Vector2i(720, 1280), "Xiaoling run last")
    runner.queue_free()


func _verify_amai() -> void:
    var runner := CharacterBody2D.new()
    var visual := AMAI_VISUAL.instantiate() as AnimatedSprite2D
    runner.add_child(visual)
    add_child(runner)
    await get_tree().process_frame
    _expect_animation(visual, &"idle", 60, 12.0, true, "Amai")
    _expect_animation(visual, &"run_start", 21, 30.0, false, "Amai")
    _expect_animation(visual, &"run", 14, 15.0, true, "Amai")
    _expect_animation(visual, &"jump", 77, 70.0, false, "Amai")
    _expect_texture_size(visual, &"jump", 0, Vector2i(720, 1280), "Amai jump first")
    _expect_texture_size(visual, &"jump", 76, Vector2i(720, 1280), "Amai jump last")
    visual.call("_set_motion_state", 3)
    _expect(visual.animation == &"jump", "Amai jump state selects jump animation")
    runner.velocity = Vector2(300.0, 0.0)
    visual.call("play_scripted_run", 1.0)
    _expect(visual.animation == &"run", "Amai scripted movement selects run animation immediately")
    _expect(not visual.flip_h, "Amai positive scripted movement faces right")
    runner.velocity = Vector2.ZERO
    visual.call("play_scripted_idle")
    _expect(visual.animation == &"idle", "Amai scripted movement returns to idle")
    runner.queue_free()


func _expect_animation(
        visual: AnimatedSprite2D,
        animation_name: StringName,
        expected_count: int,
        expected_fps: float,
        expected_loop: bool,
        label: String
) -> void:
    var frames := visual.sprite_frames
    _expect(frames.has_animation(animation_name), "%s has %s" % [label, animation_name])
    if not frames.has_animation(animation_name):
        return
    _expect(
        frames.get_frame_count(animation_name) == expected_count,
        "%s %s frame count=%d" % [label, animation_name, expected_count]
    )
    _expect(
        is_equal_approx(frames.get_animation_speed(animation_name), expected_fps),
        "%s %s fps=%.1f" % [label, animation_name, expected_fps]
    )
    _expect(
        frames.get_animation_loop(animation_name) == expected_loop,
        "%s %s loop=%s" % [label, animation_name, expected_loop]
    )


func _expect_texture_size(
        visual: AnimatedSprite2D,
        animation_name: StringName,
        frame_index: int,
        expected_size: Vector2i,
        label: String
) -> void:
    var texture := visual.sprite_frames.get_frame_texture(animation_name, frame_index)
    _expect(texture != null, "%s texture loads" % label)
    if texture != null:
        _expect(texture.get_size() == Vector2(expected_size), "%s size=%s" % [label, expected_size])


func _expect(condition: bool, message: String) -> void:
    if condition:
        return
    _failures += 1
    push_error("[PARKOUR CHARACTER ANIMATION TEST] %s" % message)
