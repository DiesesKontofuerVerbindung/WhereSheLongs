extends CharacterBody2D

enum ControlMode {
    NORMAL,
    LOCKED,
    EXTERNAL,
}

signal facing_changed(direction: Vector2)
signal movement_state_changed(is_moving: bool)
signal control_mode_changed(mode: int)

@export var move_speed: float = 220.0
@export var interaction_offset: float = 30.0
@export_enum("Normal", "Locked", "External") var control_mode: int = ControlMode.NORMAL
@export var interaction_enabled: bool = true

@onready var interaction_detector: Area2D = $InteractionDetector

var facing_direction: Vector2 = Vector2.DOWN
var _was_moving := false
var _external_velocity := Vector2.ZERO


func _physics_process(_delta: float) -> void:
    if get_tree().paused:
        _stop_movement()
        return

    match control_mode:
        ControlMode.LOCKED:
            _stop_movement()
            return
        ControlMode.EXTERNAL:
            _process_external_movement()
            return
        _:
            _process_normal_movement()


func _unhandled_input(event: InputEvent) -> void:
    if get_tree().paused or Dialogue.is_open():
        return
    if control_mode != ControlMode.NORMAL or not interaction_enabled:
        return

    if event.is_action_pressed("interact"):
        var target := _get_nearest_interactable()
        if target != null:
            get_viewport().set_input_as_handled()
            target.interact(self)

    elif event.is_action_pressed("look"):
        var target := _get_nearest_interactable()
        if target != null:
            target.look(self)
            get_viewport().set_input_as_handled()


func set_control_mode(mode: int) -> void:
    if mode < ControlMode.NORMAL or mode > ControlMode.EXTERNAL:
        push_warning("Player received invalid control mode: %s" % mode)
        return
    if control_mode == mode:
        return

    control_mode = mode
    if control_mode != ControlMode.EXTERNAL:
        _external_velocity = Vector2.ZERO
    if control_mode == ControlMode.LOCKED:
        velocity = Vector2.ZERO
        _publish_movement_state(false)

    control_mode_changed.emit(control_mode)


func use_normal_control() -> void:
    set_control_mode(ControlMode.NORMAL)


func lock_control() -> void:
    set_control_mode(ControlMode.LOCKED)


func use_external_control() -> void:
    set_control_mode(ControlMode.EXTERNAL)


func set_interaction_enabled(enabled: bool) -> void:
    interaction_enabled = enabled


func set_external_velocity(desired_velocity: Vector2, update_facing: bool = true) -> void:
    _external_velocity = desired_velocity
    if update_facing and desired_velocity != Vector2.ZERO:
        _set_facing(desired_velocity.normalized())


func stop_external_movement() -> void:
    _external_velocity = Vector2.ZERO


func get_facing_direction() -> Vector2:
    return facing_direction


func _process_normal_movement() -> void:
    if Dialogue.is_open():
        _stop_movement()
        return

    var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
    if input_vector != Vector2.ZERO:
        input_vector = input_vector.normalized()
        velocity = input_vector * move_speed
        _set_facing(input_vector)
        _publish_movement_state(true)
    else:
        velocity = Vector2.ZERO
        _publish_movement_state(false)

    move_and_slide()


func _process_external_movement() -> void:
    velocity = _external_velocity
    _publish_movement_state(velocity != Vector2.ZERO)
    move_and_slide()


func _stop_movement() -> void:
    velocity = Vector2.ZERO
    _publish_movement_state(false)
    move_and_slide()


func _set_facing(direction: Vector2) -> void:
    if direction == Vector2.ZERO:
        return

    if abs(direction.x) > abs(direction.y):
        facing_direction = Vector2.RIGHT if direction.x > 0.0 else Vector2.LEFT
    else:
        facing_direction = Vector2.DOWN if direction.y > 0.0 else Vector2.UP

    interaction_detector.position = facing_direction * interaction_offset
    facing_changed.emit(facing_direction)


func _publish_movement_state(is_moving: bool) -> void:
    if is_moving == _was_moving:
        return
    _was_moving = is_moving
    movement_state_changed.emit(is_moving)


func _get_nearest_interactable() -> Area2D:
    var nearest: Area2D = null
    var nearest_distance := INF

    for area in interaction_detector.get_overlapping_areas():
        if not area.has_method("interact") or not area.has_method("look"):
            continue
        var distance := global_position.distance_squared_to(area.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest = area

    return nearest
