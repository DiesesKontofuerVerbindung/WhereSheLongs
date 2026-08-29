extends StaticBody2D
class_name ParkourGreyboxSurface

@export var surface_size := Vector2(240.0, 80.0)
@export var surface_color := Color(0.2, 0.48, 0.38, 1.0)

var collision_shape: CollisionShape2D


func _ready() -> void:
    collision_shape = CollisionShape2D.new()
    var rectangle := RectangleShape2D.new()
    rectangle.size = surface_size
    collision_shape.shape = rectangle
    add_child(collision_shape)
    add_to_group("parkour_greybox_surface")
    queue_redraw()


func _draw() -> void:
    draw_rect(Rect2(-surface_size * 0.5, surface_size), surface_color, true)
    draw_rect(Rect2(-surface_size * 0.5, surface_size), surface_color.lightened(0.22), false, 2.0)
