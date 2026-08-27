extends Node2D
class_name AmaiParkourPlaceholder

enum AmaiState {
    RUNNING,
    WAITING,
}

signal waiting_started

@export var player_path: NodePath = ^"../Player"
@export var wait_distance_threshold := 520.0
@export var lead_distance := 210.0
@export var movement_speed := 280.0

var state: int = AmaiState.RUNNING
var last_mimicked_choice: StringName = &""

@onready var player: CharacterBody2D = get_node(player_path)
@onready var choice_label: Label = $ChoiceLabel


func _physics_process(delta: float) -> void:
    var distance_ahead := global_position.x - player.global_position.x
    if distance_ahead > wait_distance_threshold:
        _set_state(AmaiState.WAITING)
        return
    _set_state(AmaiState.RUNNING)
    var desired_position := player.global_position + Vector2(lead_distance, -72.0)
    global_position = global_position.move_toward(desired_position, movement_speed * delta)


func record_choice(choice: StringName) -> void:
    last_mimicked_choice = choice
    choice_label.text = "阿麦模仿：%s" % str(choice).replace("_", " ")


func warp_to_player_lead() -> void:
    global_position = player.global_position + Vector2(lead_distance, -72.0)


func _set_state(next_state: int) -> void:
    if state == next_state:
        return
    state = next_state
    if state == AmaiState.WAITING:
        waiting_started.emit()
