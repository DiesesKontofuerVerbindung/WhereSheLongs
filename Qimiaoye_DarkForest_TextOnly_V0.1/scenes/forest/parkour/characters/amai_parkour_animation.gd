extends AnimatedSprite2D
class_name AmaiParkourAnimation

enum MotionState {
    IDLE,
    RUN_START,
    RUN,
}

const FRAME_ROOT := "res://scenes/forest/parkour/characters/amai_animation"
const IDLE_FRAME_COUNT := 60
const RUN_START_FRAME_COUNT := 21
const RUN_FRAME_COUNT := 14

@export var movement_threshold := 24.0
@export var idle_fps := 12.0
@export var run_start_fps := 30.0
@export var run_fps := 15.0
@export var stop_grace_duration := 0.12

static var _cached_sprite_frames: SpriteFrames

var motion_state := MotionState.IDLE
var _stationary_time := 0.0

@onready var runner := get_parent() as CharacterBody2D


func _ready() -> void:
    if _cached_sprite_frames == null:
        _cached_sprite_frames = _build_sprite_frames()
    sprite_frames = _cached_sprite_frames
    animation_finished.connect(_on_animation_finished)
    _set_motion_state(MotionState.IDLE)


func _physics_process(delta: float) -> void:
    if runner == null:
        return
    var horizontal_speed := runner.velocity.x
    var moving := absf(horizontal_speed) >= movement_threshold
    if moving:
        _stationary_time = 0.0
        flip_h = horizontal_speed < 0.0
        if motion_state == MotionState.IDLE:
            _set_motion_state(MotionState.RUN_START)
        return

    _stationary_time += delta
    if _stationary_time < stop_grace_duration:
        return
    _set_motion_state(MotionState.IDLE)


func get_motion_state_name() -> StringName:
    match motion_state:
        MotionState.RUN_START:
            return &"run_start"
        MotionState.RUN:
            return &"run"
        _:
            return &"idle"


func _build_sprite_frames() -> SpriteFrames:
    var next_frames := SpriteFrames.new()
    next_frames.remove_animation(&"default")
    _add_animation(next_frames, &"idle", "idle", "idle", IDLE_FRAME_COUNT, idle_fps, true)
    _add_animation(
        next_frames,
        &"run_start",
        "run_start",
        "run_start",
        RUN_START_FRAME_COUNT,
        run_start_fps,
        false
    )
    _add_animation(next_frames, &"run", "run", "run", RUN_FRAME_COUNT, run_fps, true)
    return next_frames


func _add_animation(
        target: SpriteFrames,
        animation_name: StringName,
        folder_name: String,
        file_prefix: String,
        frame_count: int,
        fps: float,
        loops: bool
) -> void:
    target.add_animation(animation_name)
    target.set_animation_speed(animation_name, fps)
    target.set_animation_loop(animation_name, loops)
    for frame_index in range(1, frame_count + 1):
        var texture_path := "%s/%s/%s_%03d.png" % [
            FRAME_ROOT,
            folder_name,
            file_prefix,
            frame_index,
        ]
        var texture := load(texture_path) as Texture2D
        if texture == null:
            push_error("[AMAI ANIMATION] Missing frame: %s" % texture_path)
            continue
        target.add_frame(animation_name, texture)


func _set_motion_state(next_state: MotionState) -> void:
    if motion_state == next_state and is_playing():
        return
    motion_state = next_state
    play(get_motion_state_name())


func _on_animation_finished() -> void:
    if motion_state != MotionState.RUN_START or runner == null:
        return
    if absf(runner.velocity.x) >= movement_threshold:
        _set_motion_state(MotionState.RUN)
    elif _stationary_time < stop_grace_duration:
        _set_motion_state(MotionState.RUN)
    else:
        _set_motion_state(MotionState.IDLE)
