extends Node
class_name ParkourMotor

@export var move_speed := 300.0
@export var ground_acceleration := 1800.0
@export var ground_deceleration := 2200.0
@export var gravity := 1700.0
@export var jump_velocity := -900.0
@export var max_fall_speed := 1100.0
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.12
@export_range(0.1, 1.0, 0.05) var jump_release_multiplier := 0.45
@export var variable_jump_enabled := true

var velocity := Vector2.ZERO
var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_count := 0


func step(
        delta: float,
        horizontal_input: float,
        jump_pressed: bool,
        jump_held: bool,
        jump_released: bool,
        grounded: bool
) -> Vector2:
    coyote_timer = coyote_time if grounded else maxf(0.0, coyote_timer - delta)
    jump_buffer_timer = jump_buffer_time if jump_pressed else maxf(0.0, jump_buffer_timer - delta)

    var target_speed := clampf(horizontal_input, -1.0, 1.0) * move_speed
    var acceleration := ground_acceleration if not is_zero_approx(horizontal_input) else ground_deceleration
    velocity.x = move_toward(velocity.x, target_speed, acceleration * delta)

    if grounded and velocity.y > 0.0:
        velocity.y = 0.0

    if coyote_timer > 0.0 and jump_buffer_timer > 0.0:
        velocity.y = jump_velocity
        coyote_timer = 0.0
        jump_buffer_timer = 0.0
        jump_count += 1
    elif not grounded:
        velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)

    if variable_jump_enabled and jump_released and not jump_held and velocity.y < 0.0:
        velocity.y *= jump_release_multiplier

    return velocity


func reset_motion() -> void:
    velocity = Vector2.ZERO
    coyote_timer = 0.0
    jump_buffer_timer = 0.0


func reset_counters() -> void:
    jump_count = 0
