extends Node2D
class_name VineDecisionGate

signal decision_requested(gate_index: int, body: Node2D)
signal action_execution_requested(gate_index: int, body: Node2D)
signal gate_passed(gate_index: int, body: Node2D)

@export var gate_index := 0
@export var action_zone_x_offset := -100.0
@export var pass_zone_x_offset := 60.0

var _first_round_echo_bypass: CharacterBody2D
var _fixed_ground_route_runner: CharacterBody2D

@onready var decision_zone: Area2D = $DecisionZone
@onready var action_zone: Area2D = $ActionZone
@onready var pass_zone: Area2D = $PassZone
@onready var slide_vine: StaticBody2D = $SlideVine
@onready var up_path: StaticBody2D = $UpPath


func _ready() -> void:
    add_to_group("vine_decision_gate")
    action_zone.position.x = action_zone_x_offset
    pass_zone.position.x = pass_zone_x_offset
    decision_zone.body_entered.connect(_on_decision_zone_body_entered)
    action_zone.body_entered.connect(_on_action_zone_body_entered)
    pass_zone.body_entered.connect(_on_pass_zone_body_entered)


func allow_first_round_echo_bypass(echo_runner: CharacterBody2D) -> void:
    _first_round_echo_bypass = echo_runner
    slide_vine.add_collision_exception_with(echo_runner)


func allow_fixed_ground_route(echo_runner: CharacterBody2D) -> void:
    _fixed_ground_route_runner = echo_runner
    up_path.add_collision_exception_with(echo_runner)


func has_first_round_echo_bypass(echo_runner: CharacterBody2D) -> bool:
    return _first_round_echo_bypass == echo_runner


func has_fixed_ground_route(echo_runner: CharacterBody2D) -> bool:
    return _fixed_ground_route_runner == echo_runner


func _on_decision_zone_body_entered(body: Node2D) -> void:
    if body is CharacterBody2D:
        decision_requested.emit(gate_index, body)


func _on_action_zone_body_entered(body: Node2D) -> void:
    if body is CharacterBody2D:
        action_execution_requested.emit(gate_index, body)


func _on_pass_zone_body_entered(body: Node2D) -> void:
    if body is CharacterBody2D:
        gate_passed.emit(gate_index, body)
