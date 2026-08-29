extends Node2D
class_name ParkourPredatorPlant

enum PlantState {
    OPEN,
    CLOSED,
}

signal hazard_triggered
signal choice_made(choice: StringName)
signal state_changed(next_state: int)

@export var open_duration := 1.6
@export var closed_duration := 1.2

var state: int = PlantState.OPEN
var state_timer := 0.0
var last_choice: StringName = &""

@onready var visual: Polygon2D = $Visual
@onready var hazard_area: Area2D = $HazardArea


func _ready() -> void:
    state_timer = open_duration
    hazard_area.body_entered.connect(_on_hazard_entered)
    $RiskRouteSensor.body_entered.connect(_on_risk_route_entered)
    $SafeRouteSensor.body_entered.connect(_on_safe_route_entered)
    _refresh_visual()


func _physics_process(delta: float) -> void:
    state_timer -= delta
    if state_timer > 0.0:
        return
    if state == PlantState.OPEN:
        set_state(PlantState.CLOSED)
    else:
        set_state(PlantState.OPEN)


func set_state(next_state: int) -> void:
    state = next_state
    state_timer = open_duration if state == PlantState.OPEN else closed_duration
    _refresh_visual()
    state_changed.emit(state)


func reset_choice() -> void:
    last_choice = &""


func debug_choose(choice: StringName) -> void:
    _record_choice(choice)


func debug_trigger_hazard() -> bool:
    if state != PlantState.OPEN:
        return false
    hazard_triggered.emit()
    return true


func get_state_name() -> String:
    return "OPEN" if state == PlantState.OPEN else "CLOSED"


func _on_hazard_entered(body: Node2D) -> void:
    if body is CharacterBody2D and state == PlantState.OPEN:
        hazard_triggered.emit()


func _on_risk_route_entered(body: Node2D) -> void:
    if body is CharacterBody2D:
        _record_choice(&"RISK_ROUTE")


func _on_safe_route_entered(body: Node2D) -> void:
    if body is CharacterBody2D and state == PlantState.CLOSED:
        _record_choice(&"WAIT")


func _record_choice(choice: StringName) -> void:
    if last_choice != &"":
        return
    last_choice = choice
    choice_made.emit(choice)


func _refresh_visual() -> void:
    visual.color = Color(0.92, 0.2, 0.32, 1.0) if state == PlantState.OPEN else Color(0.28, 0.72, 0.42, 1.0)
