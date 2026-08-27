extends Node
class_name RunnerActionController

enum RunnerAction {
    NONE,
    UP,
    DOWN,
}

signal action_performed(action: int)

@export var runner_path: NodePath = ^".."
@export var collision_shape_path: NodePath = ^"../CollisionShape2D"
@export var run_speed := 300.0
@export var gravity := 1700.0
@export var jump_impulse := 900.0
@export var slide_duration := 1.05
@export var suspend_runner_physics := false

var is_running := false
var is_sliding := false
var _slide_remaining := 0.0
var _horizontal_input := 0.0
var _normal_shape: Shape2D
var _slide_shape: Shape2D
var _normal_collision_position := Vector2.ZERO
var _slide_collision_position := Vector2.ZERO

@onready var runner: CharacterBody2D = get_node(runner_path)
@onready var collision_shape: CollisionShape2D = get_node(collision_shape_path)


func _ready() -> void:
    process_physics_priority = 10
    _cache_collision_shapes()


func start_auto_run() -> void:
    start_run(1.0)


func start_run(initial_horizontal_input: float = 0.0) -> void:
    is_running = true
    _horizontal_input = clampf(initial_horizontal_input, -1.0, 1.0)
    if suspend_runner_physics:
        runner.set_physics_process(false)


func stop_auto_run() -> void:
    stop_run()


func stop_run() -> void:
    is_running = false
    _horizontal_input = 0.0
    _set_slide(false)
    runner.velocity = Vector2.ZERO
    if suspend_runner_physics:
        runner.set_physics_process(true)


func configure_motion(next_run_speed: float, next_gravity: float, next_jump_impulse: float) -> void:
    run_speed = next_run_speed
    gravity = next_gravity
    jump_impulse = next_jump_impulse


func set_horizontal_input(next_horizontal_input: float) -> void:
    _horizontal_input = clampf(next_horizontal_input, -1.0, 1.0)


func perform_action(action: int) -> void:
    match action:
        RunnerAction.UP:
            if runner.is_on_floor():
                runner.velocity.y = -jump_impulse
        RunnerAction.DOWN:
            if runner.is_on_floor():
                _slide_remaining = slide_duration
                _set_slide(true)
    action_performed.emit(action)


func debug_set_slide(enabled: bool) -> void:
    _slide_remaining = slide_duration if enabled else 0.0
    _set_slide(enabled)


func _physics_process(delta: float) -> void:
    if not is_running or get_tree().paused:
        return

    if runner.is_on_floor() and runner.velocity.y > 0.0:
        runner.velocity.y = 0.0
    else:
        runner.velocity.y = minf(runner.velocity.y + gravity * delta, 1100.0)
    runner.velocity.x = _horizontal_input * run_speed

    if is_sliding:
        _slide_remaining = maxf(0.0, _slide_remaining - delta)
        if is_zero_approx(_slide_remaining):
            _set_slide(false)

    runner.move_and_slide()


func _cache_collision_shapes() -> void:
    _normal_collision_position = collision_shape.position
    _normal_shape = collision_shape.shape.duplicate()
    _slide_shape = collision_shape.shape.duplicate()
    if _normal_shape is CapsuleShape2D and _slide_shape is CapsuleShape2D:
        var normal_capsule := _normal_shape as CapsuleShape2D
        var slide_capsule := _slide_shape as CapsuleShape2D
        slide_capsule.height = maxf(slide_capsule.radius * 2.0, normal_capsule.height - 10.0)
        _slide_collision_position = _normal_collision_position + Vector2(0.0, (normal_capsule.height - slide_capsule.height) * 0.5)
    elif _normal_shape is RectangleShape2D and _slide_shape is RectangleShape2D:
        var normal_rectangle := _normal_shape as RectangleShape2D
        var slide_rectangle := _slide_shape as RectangleShape2D
        slide_rectangle.size.y = normal_rectangle.size.y * 0.6
        _slide_collision_position = _normal_collision_position + Vector2(0.0, (normal_rectangle.size.y - slide_rectangle.size.y) * 0.5)


func _set_slide(enabled: bool) -> void:
    if _normal_shape == null or _slide_shape == null:
        return
    is_sliding = enabled
    collision_shape.shape = _slide_shape if enabled else _normal_shape
    collision_shape.position = _slide_collision_position if enabled else _normal_collision_position
