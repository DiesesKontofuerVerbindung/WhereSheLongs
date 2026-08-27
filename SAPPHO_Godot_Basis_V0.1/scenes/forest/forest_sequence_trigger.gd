extends Area2D

signal transition_requested(trigger_id: StringName, expected_state: int, next_state: int)

@export var trigger_id: StringName
@export var expected_state: int
@export var next_state: int
@export var actor_path: NodePath = ^"../../Player"

@onready var actor: Node = get_node(actor_path)


func _ready() -> void:
    body_entered.connect(_on_body_entered)


func activate(body: Node) -> void:
    if body != actor:
        return
    transition_requested.emit(trigger_id, expected_state, next_state)


func _on_body_entered(body: Node) -> void:
    activate(body)
