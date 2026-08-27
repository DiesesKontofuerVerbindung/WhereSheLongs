extends Node2D
class_name ParkourPlatform

signal platform_landed(platform_id: StringName)

@export var platform_id: StringName
@export var checkpoint_enabled := true
@export var show_mechanics_visual := false

var normalized_position := Vector2.ZERO
var _landed_body_ids: Dictionary = {}

@onready var static_body: StaticBody2D = $StaticBody2D
@onready var body_shape: CollisionShape2D = $StaticBody2D/CollisionShape2D
@onready var landing_sensor: Area2D = $LandingSensor
@onready var sensor_shape: CollisionShape2D = $LandingSensor/CollisionShape2D


func _ready() -> void:
    landing_sensor.body_entered.connect(_on_body_entered)
    landing_sensor.body_exited.connect(_on_body_exited)


func configure(data: Dictionary, design_size: Vector2) -> void:
    normalized_position = data.get("normalized_position", Vector2.ZERO)
    position = normalized_position * design_size
    checkpoint_enabled = data.get("checkpoint_enabled", true)

    var collision_size: Vector2 = data.get("collision_size", Vector2(160.0, 30.0))
    var landing_size: Vector2 = data.get("landing_sensor_size", Vector2(140.0, 14.0))
    static_body.position = data.get("collision_offset", Vector2.ZERO)

    var rectangle := body_shape.shape as RectangleShape2D
    rectangle.size = collision_size
    var sensor_rectangle := sensor_shape.shape as RectangleShape2D
    sensor_rectangle.size = landing_size
    landing_sensor.position = static_body.position + Vector2(0.0, -collision_size.y * 0.5 - landing_size.y * 0.5)

    var visual := get_node_or_null("Visual") as Polygon2D
    if visual != null:
        visual.visible = show_mechanics_visual
        var half := collision_size * 0.5
        visual.position = static_body.position
        visual.polygon = PackedVector2Array([
            Vector2(-half.x, -half.y),
            Vector2(half.x, -half.y),
            Vector2(half.x, half.y),
            Vector2(-half.x, half.y),
        ])


func get_respawn_position() -> Vector2:
    var rectangle := body_shape.shape as RectangleShape2D
    return global_position + static_body.position + Vector2(0.0, -rectangle.size.y * 0.5 - 24.0)


func reset_landing_guard() -> void:
    _landed_body_ids.clear()


func debug_register_landing(body: CharacterBody2D) -> void:
    _register_landing(body)


func _on_body_entered(body: Node2D) -> void:
    if body is CharacterBody2D and body.velocity.y >= -1.0:
        _register_landing(body)


func _on_body_exited(body: Node2D) -> void:
    _landed_body_ids.erase(body.get_instance_id())


func _register_landing(body: CharacterBody2D) -> void:
    var body_id := body.get_instance_id()
    if _landed_body_ids.has(body_id):
        return
    _landed_body_ids[body_id] = true
    platform_landed.emit(platform_id)
