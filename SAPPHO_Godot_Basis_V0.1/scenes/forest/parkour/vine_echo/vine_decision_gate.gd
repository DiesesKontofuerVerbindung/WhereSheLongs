extends Node2D
class_name VineDecisionGate

signal decision_requested(gate_index: int, body: Node2D)
signal gate_passed(gate_index: int, body: Node2D)

@export var gate_index := 0

var _first_round_echo_bypass: CharacterBody2D

@onready var decision_zone: Area2D = $DecisionZone
@onready var pass_zone: Area2D = $PassZone
@onready var slide_vine: StaticBody2D = $SlideVine


func _ready() -> void:
    add_to_group("vine_decision_gate")
    decision_zone.body_entered.connect(_on_decision_zone_body_entered)
    pass_zone.body_entered.connect(_on_pass_zone_body_entered)


func allow_first_round_echo_bypass(echo_runner: CharacterBody2D) -> void:
    _first_round_echo_bypass = echo_runner
    slide_vine.add_collision_exception_with(echo_runner)


func has_first_round_echo_bypass(echo_runner: CharacterBody2D) -> bool:
    return _first_round_echo_bypass == echo_runner


func _on_decision_zone_body_entered(body: Node2D) -> void:
    if body is CharacterBody2D:
        decision_requested.emit(gate_index, body)


func _on_pass_zone_body_entered(body: Node2D) -> void:
    if body is CharacterBody2D:
        gate_passed.emit(gate_index, body)
