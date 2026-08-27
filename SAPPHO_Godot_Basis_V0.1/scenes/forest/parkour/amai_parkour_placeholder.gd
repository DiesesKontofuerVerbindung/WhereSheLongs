extends Node2D
class_name AmaiParkourPlaceholder

enum AmaiState {
    RUNNING,
    WAITING,
}

signal waiting_started

@export var player_path: NodePath = ^"../Player"
@export var guide_root_path: NodePath = ^"../Gameplay/AmaiGuides"
@export var wait_distance_threshold := 520.0
@export var movement_speed := 280.0

var state: int = AmaiState.RUNNING
var last_mimicked_choice: StringName = &""
var active_guide: StringName = &"Segment01Guide"
var _guide_points: Array[Marker2D] = []
var _guide_index := 0

@onready var player: CharacterBody2D = get_node(player_path)
@onready var choice_label: Label = $ChoiceLabel
@onready var guide_root: Node2D = get_node(guide_root_path)


func _ready() -> void:
    reset_to_segment(1)


func _physics_process(delta: float) -> void:
    if _guide_points.is_empty():
        return
    var distance_ahead := global_position.x - player.global_position.x
    if distance_ahead > wait_distance_threshold:
        _set_state(AmaiState.WAITING)
        return
    _set_state(AmaiState.RUNNING)
    var guide_point := _guide_points[_guide_index]
    global_position = global_position.move_toward(guide_point.global_position, movement_speed * delta)
    if global_position.distance_to(guide_point.global_position) <= 6.0 and _guide_index < _guide_points.size() - 1:
        _guide_index += 1


func has_guide(guide_name: StringName) -> bool:
    return guide_root.get_node_or_null(NodePath(str(guide_name))) is Node2D


func record_choice(choice: StringName) -> void:
    last_mimicked_choice = choice
    choice_label.text = "阿麦模仿：%s" % str(choice).replace("_", " ")
    match choice:
        &"JUMP":
            _set_guide(&"Segment02JumpGuide")
        &"SLIDE":
            _set_guide(&"Segment02SlideGuide")
        &"WAIT":
            _set_guide(&"Segment03SafeGuide")
        &"RISK_ROUTE":
            _set_guide(&"Segment03RiskGuide")


func reset_to_segment(segment_index: int) -> void:
    var guide_name: StringName = &"Segment01Guide"
    if segment_index == 2:
        guide_name = &"Segment02MainGuide"
    elif segment_index == 3:
        guide_name = &"Segment03SafeGuide"
    _set_guide(guide_name, true)


func _set_guide(guide_name: StringName, warp_to_start: bool = false) -> void:
    var guide := guide_root.get_node_or_null(NodePath(str(guide_name))) as Node2D
    if guide == null:
        return
    active_guide = guide_name
    _guide_points.clear()
    for child in guide.get_children():
        if child is Marker2D:
            _guide_points.append(child as Marker2D)
    _guide_index = 0
    if _guide_points.is_empty():
        return
    if warp_to_start:
        global_position = _guide_points[0].global_position
    else:
        _advance_to_nearest_guide_point()


func _advance_to_nearest_guide_point() -> void:
    var nearest_index := 0
    var nearest_distance := INF
    for index in _guide_points.size():
        var candidate_distance := global_position.distance_squared_to(_guide_points[index].global_position)
        if candidate_distance < nearest_distance:
            nearest_distance = candidate_distance
            nearest_index = index
    _guide_index = nearest_index


func _set_state(next_state: int) -> void:
    if state == next_state:
        return
    state = next_state
    if state == AmaiState.WAITING:
        waiting_started.emit()
