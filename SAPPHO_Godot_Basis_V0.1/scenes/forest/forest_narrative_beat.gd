extends Node

signal transition_requested(trigger_id: StringName, expected_state: int, next_state: int)

@export var copy_id: StringName
@export var trigger_id: StringName
@export var expected_state: int
@export var next_state: int


func complete() -> void:
    transition_requested.emit(trigger_id, expected_state, next_state)
