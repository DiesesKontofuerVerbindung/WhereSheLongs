extends Node2D
class_name ParkourVineGate

signal choice_made(choice: StringName)

var last_choice: StringName = &""


func _ready() -> void:
    $JumpSensor.body_entered.connect(_on_jump_sensor_entered)
    $SlideSensor.body_entered.connect(_on_slide_sensor_entered)


func reset_choice() -> void:
    last_choice = &""


func debug_choose(choice: StringName) -> void:
    _record_choice(choice)


func _on_jump_sensor_entered(body: Node2D) -> void:
    if body is CharacterBody2D and body.velocity.y != 0.0:
        _record_choice(&"JUMP")


func _on_slide_sensor_entered(body: Node2D) -> void:
    if body is CharacterBody2D and body.get_meta("parkour_sliding", false):
        _record_choice(&"SLIDE")


func _record_choice(choice: StringName) -> void:
    if last_choice != &"":
        return
    last_choice = choice
    choice_made.emit(choice)
