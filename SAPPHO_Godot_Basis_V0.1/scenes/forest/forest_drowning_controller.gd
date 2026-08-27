extends Node

signal breath_changed(current_breath: float, maximum_breath: float)
signal transition_requested(trigger_id: StringName, expected_state: int, next_state: int)

@export var maximum_breath: float = 5.0
@export var trigger_id: StringName = &"breath_depleted"
@export var expected_state: int = 13
@export var next_state: int = 14

var current_breath: float
var active := false


func _ready() -> void:
    reset()


func _process(delta: float) -> void:
    consume_breath(delta)


func begin() -> void:
    current_breath = maximum_breath
    active = true
    set_process(true)
    breath_changed.emit(current_breath, maximum_breath)


func consume_breath(seconds: float) -> void:
    if not active:
        return

    current_breath = maxf(0.0, current_breath - seconds)
    breath_changed.emit(current_breath, maximum_breath)
    if current_breath == 0.0:
        active = false
        set_process(false)
        transition_requested.emit(trigger_id, expected_state, next_state)


func reset() -> void:
    current_breath = maximum_breath
    active = false
    set_process(false)


func _on_forest_state_changed(_previous_state: int, current_state: int) -> void:
    if current_state == expected_state:
        begin()
    elif active:
        reset()
