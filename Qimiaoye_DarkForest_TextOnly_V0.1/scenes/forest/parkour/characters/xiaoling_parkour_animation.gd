extends AnimatedSprite2D
class_name XiaolingParkourAnimation

enum MotionState {
    IDLE,
    RUN_START,
    RUN,
    JUMP,
}

const HIGH_FRAME_ROOT := "res://scenes/forest/parkour/characters/xiaoling_animation_v2"
const LEGACY_FRAME_ROOT := "res://scenes/forest/parkour/characters/xiaoling_animation"
const IDLE_FRAME_COUNT := 151
const RUN_START_FRAME_COUNT := 13
const RUN_FRAME_COUNT := 30
const JUMP_FRAME_COUNT := 22

@export var movement_threshold := 24.0
@export var vertical_motion_threshold := 24.0
@export var idle_fps := 30.0
@export var run_start_fps := 30.0
@export var run_fps := 30.0
@export var jump_fps := 20.0

static var _cached_sprite_frames: SpriteFrames

var motion_state := MotionState.IDLE

@onready var runner := get_parent() as CharacterBody2D


func _ready() -> void:
    if _cached_sprite_frames == null:
        _cached_sprite_frames = _build_sprite_frames()
    sprite_frames = _cached_sprite_frames
    animation_finished.connect(_on_animation_finished)
    _set_motion_state(MotionState.IDLE)


func _physics_process(_delta: float) -> void:
    if runner == null:
        return
    var horizontal_speed := runner.velocity.x
    var moving := absf(horizontal_speed) >= movement_threshold
    if moving:
        flip_h = horizontal_speed < 0.0
    var jump_motion := (
        runner.velocity.y < -vertical_motion_threshold
        or (
            not runner.is_on_floor()
            and (absf(runner.velocity.y) >= vertical_motion_threshold or motion_state == MotionState.JUMP)
        )
    )
    if jump_motion:
        if motion_state != MotionState.JUMP:
            _set_motion_state(MotionState.JUMP)
        return
    if motion_state == MotionState.JUMP:
        _set_motion_state(MotionState.RUN if moving else MotionState.IDLE)
        return
    if not moving:
        if motion_state != MotionState.IDLE:
            _set_motion_state(MotionState.IDLE)
        return
    if motion_state == MotionState.IDLE:
        _set_motion_state(MotionState.RUN_START)


func get_motion_state_name() -> StringName:
    match motion_state:
        MotionState.RUN_START:
            return &"run_start"
        MotionState.RUN:
            return &"run"
        MotionState.JUMP:
            return &"jump"
        _:
            return &"idle"


func _build_sprite_frames() -> SpriteFrames:
    var next_frames := SpriteFrames.new()
    next_frames.remove_animation(&"default")
    _add_animation(next_frames, &"idle", HIGH_FRAME_ROOT, "idle", "idle", IDLE_FRAME_COUNT, 3, idle_fps, true)
    _add_animation(
        next_frames,
        &"run_start",
        HIGH_FRAME_ROOT,
        "run_start",
        "run_start",
        RUN_START_FRAME_COUNT,
        3,
        run_start_fps,
        false
    )
    _add_animation(next_frames, &"run", HIGH_FRAME_ROOT, "run", "run", RUN_FRAME_COUNT, 3, run_fps, true)
    _add_animation(next_frames, &"jump", LEGACY_FRAME_ROOT, "", "jump", JUMP_FRAME_COUNT, 2, jump_fps, false)
    return next_frames


func _add_animation(
        target: SpriteFrames,
        animation_name: StringName,
        frame_root: String,
        folder_name: String,
        file_prefix: String,
        frame_count: int,
        zero_padding: int,
        fps: float,
        loops: bool
) -> void:
    target.add_animation(animation_name)
    target.set_animation_speed(animation_name, fps)
    target.set_animation_loop(animation_name, loops)
    for frame_index in range(1, frame_count + 1):
        var frame_number := "%03d" % frame_index if zero_padding == 3 else "%02d" % frame_index
        var folder_segment := "/%s" % folder_name if not folder_name.is_empty() else ""
        var texture_path := "%s%s/%s_%s.png" % [
            frame_root,
            folder_segment,
            file_prefix,
            frame_number,
        ]
        var texture := load(texture_path) as Texture2D
        if texture == null:
            push_error("[XIAOLING ANIMATION] Missing frame: %s" % texture_path)
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
    else:
        _set_motion_state(MotionState.IDLE)
