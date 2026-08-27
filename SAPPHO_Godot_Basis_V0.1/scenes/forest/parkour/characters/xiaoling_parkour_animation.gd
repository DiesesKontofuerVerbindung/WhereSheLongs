extends AnimatedSprite2D
class_name XiaolingParkourAnimation

enum MotionState {
    IDLE,
    RUN_START,
    RUN,
}

const IDLE_FRAMES := [
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_01.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_02.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_03.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_04.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_05.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_06.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_07.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/idle_08.png"),
]
const RUN_START_FRAMES := [
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_01.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_02.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_03.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_04.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_05.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_06.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_07.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_08.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_start_09.png"),
]
const RUN_FRAMES := [
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_01.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_02.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_03.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_04.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_05.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_06.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_07.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_08.png"),
    preload("res://scenes/forest/parkour/characters/xiaoling_animation/run_09.png"),
]

@export var movement_threshold := 24.0
@export var idle_fps := 8.0
@export var run_start_fps := 16.0
@export var run_fps := 14.0

var motion_state := MotionState.IDLE

@onready var runner := get_parent() as CharacterBody2D


func _ready() -> void:
    _build_sprite_frames()
    animation_finished.connect(_on_animation_finished)
    _set_motion_state(MotionState.IDLE)


func _physics_process(_delta: float) -> void:
    if runner == null:
        return
    var horizontal_speed := runner.velocity.x
    var moving := absf(horizontal_speed) >= movement_threshold
    if moving:
        flip_h = horizontal_speed < 0.0
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
        _:
            return &"idle"


func _build_sprite_frames() -> void:
    var next_frames := SpriteFrames.new()
    next_frames.remove_animation(&"default")
    _add_animation(next_frames, &"idle", IDLE_FRAMES, idle_fps, true)
    _add_animation(next_frames, &"run_start", RUN_START_FRAMES, run_start_fps, false)
    _add_animation(next_frames, &"run", RUN_FRAMES, run_fps, true)
    sprite_frames = next_frames


func _add_animation(
        target: SpriteFrames,
        animation_name: StringName,
        textures: Array,
        fps: float,
        loops: bool
) -> void:
    target.add_animation(animation_name)
    target.set_animation_speed(animation_name, fps)
    target.set_animation_loop(animation_name, loops)
    for texture in textures:
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
