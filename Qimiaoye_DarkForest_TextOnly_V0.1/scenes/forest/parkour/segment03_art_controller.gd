extends Node2D
class_name Segment03ArtController

@export var closed_backdrop_path: NodePath = ^"BackdropClosed"
@export var open_backdrop_path: NodePath = ^"BackdropOpen"
@export var master_plant_path: NodePath = ^"../PredatorPlant"
@export var follower_plant_paths: Array[NodePath] = [
    ^"../PredatorPlantB",
    ^"../PredatorPlantC",
]

@onready var closed_backdrop: Sprite2D = get_node(closed_backdrop_path)
@onready var open_backdrop: Sprite2D = get_node(open_backdrop_path)
@onready var master_plant: ParkourPredatorPlant = get_node(master_plant_path)

var follower_plants: Array[ParkourPredatorPlant] = []


func _ready() -> void:
    for path in follower_plant_paths:
        var plant := get_node_or_null(path) as ParkourPredatorPlant
        if plant == null:
            continue
        plant.set_physics_process(false)
        follower_plants.append(plant)
    master_plant.state_changed.connect(_on_master_state_changed)
    _sync_scene_state.call_deferred(master_plant.state)


func _on_master_state_changed(next_state: int) -> void:
    _sync_scene_state(next_state)


func _sync_scene_state(next_state: int) -> void:
    for plant in follower_plants:
        if plant.state != next_state:
            plant.set_state(next_state)
    var is_open := next_state == ParkourPredatorPlant.PlantState.OPEN
    open_backdrop.visible = is_open
    closed_backdrop.visible = not is_open
