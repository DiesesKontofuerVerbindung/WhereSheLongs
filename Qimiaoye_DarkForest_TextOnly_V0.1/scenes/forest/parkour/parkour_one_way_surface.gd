extends StaticBody2D
class_name ParkourOneWaySurface

@export var surface_size := Vector2(160.0, 20.0)
@export var one_way_margin := 14.0

var collision_shape: CollisionShape2D


func _ready() -> void:
    collision_shape = CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = surface_size
    collision_shape.shape = rectangle
    collision_shape.one_way_collision = true
    collision_shape.one_way_collision_margin = one_way_margin
    add_child(collision_shape)
    add_to_group("parkour_greybox_surface")
