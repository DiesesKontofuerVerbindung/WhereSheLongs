@tool
extends Node2D
class_name RootObstacle

@export var root_id: StringName = &"Root01"
@export var root_size := Vector2(215.0, 104.0)
@export var collision_size := Vector2(130.0, 22.0)
@export var collision_x := 0.0
@export var collision_y := -42.0
@export_range(0, 5, 1) var visual_variant := 0
@export var debug_marker_visible := false
@export var visual_enabled := true

@export_group("Palette")
@export var front_color := Color(0.20, 0.14, 0.075, 1.0)
@export var side_color := Color(0.105, 0.075, 0.052, 1.0)
@export var highlight_color := Color(0.34, 0.265, 0.12, 1.0)
@export var moss_color := Color(0.30, 0.46, 0.16, 1.0)

@onready var upper_collision: StaticBody2D = $UpperCollision
@onready var collision_shape: CollisionShape2D = $UpperCollision/CollisionShape2D
@onready var debug_marker: Label = $DebugMarker


func _ready() -> void:
    add_to_group("segment02_root_obstacle")
    _configure_collision()
    debug_marker.visible = debug_marker_visible
    debug_marker.text = str(root_id)
    queue_redraw()


func _configure_collision() -> void:
    if collision_shape == null:
        return
    var rectangle := RectangleShape2D.new()
    rectangle.size = collision_size
    collision_shape.shape = rectangle
    collision_shape.position = Vector2(collision_x, collision_y)


func get_outer_width() -> float:
    return root_size.x


func get_outer_height() -> float:
    return root_size.y


func get_opening_clearance() -> float:
    return -collision_y - collision_size.y * 0.5


func get_perspective_signature() -> String:
    return "%d:%.0f:%.0f" % [visual_variant, root_size.x, root_size.y]


func _draw() -> void:
    if not visual_enabled:
        return
    var width := root_size.x
    var height := root_size.y
    var half_width := width * 0.5
    var skews := PackedFloat32Array([0.04, 0.10, -0.04, 0.13, -0.08, 0.07])
    var skew: float = skews[visual_variant]
    var crown_shift: float = width * skew
    var front_thickness := clampf(height * 0.25, 21.0, 37.0)
    var far_thickness := front_thickness * 0.58

    var ground_shadow := PackedVector2Array([
        Vector2(-half_width * 0.78, -4.0),
        Vector2(-half_width * 0.22, -12.0),
        Vector2(half_width * 0.72, -8.0),
        Vector2(half_width + 38.0, 8.0),
        Vector2(-half_width - 34.0, 10.0),
    ])
    draw_colored_polygon(ground_shadow, Color(0.055, 0.045, 0.035, 0.9))

    # The rear contour is laterally shifted, lower, and shorter. Together with the
    # broad near leg this produces an oblique 3/4 projection instead of a front-on hoop.
    var far_shift := width * (0.13 + 0.015 * float(visual_variant % 3))
    var far_points := PackedVector2Array([
        Vector2(-width * 0.33 + far_shift, -1.0),
        Vector2(-width * 0.25 + far_shift, -height * 0.42),
        Vector2(-width * 0.08 + crown_shift + far_shift, -height * 0.76),
        Vector2(width * 0.16 + crown_shift + far_shift, -height * 0.67),
        Vector2(width * 0.30 + far_shift, -height * 0.32),
        Vector2(width * 0.38 + far_shift, -4.0),
    ])
    draw_polyline(far_points, side_color, far_thickness, true)
    for point in far_points:
        draw_circle(point, far_thickness * 0.48, side_color)

    var front_points := PackedVector2Array([
        Vector2(-width * 0.56, 2.0),
        Vector2(-width * 0.48, -height * 0.25),
        Vector2(-width * (0.35 + 0.012 * float(visual_variant % 3)), -height * 0.64),
        Vector2(-width * 0.10 + crown_shift, -height),
        Vector2(width * 0.14 + crown_shift, -height * 0.83),
        Vector2(width * 0.31, -height * 0.46),
        Vector2(width * 0.40, -height * 0.08),
    ])
    var crown_depth := PackedVector2Array([
        front_points[3] + Vector2(front_thickness * 0.28, front_thickness * 0.18),
        front_points[4] + Vector2(front_thickness * 0.20, front_thickness * 0.24),
        far_points[3] + Vector2(0.0, far_thickness * 0.22),
        far_points[2] + Vector2(0.0, far_thickness * 0.22),
    ])
    draw_colored_polygon(crown_depth, side_color.lightened(0.07))
    draw_polyline(front_points, front_color, front_thickness, true)
    for point in front_points:
        draw_circle(point, front_thickness * 0.48, front_color)
    draw_polyline(front_points, highlight_color, maxf(3.0, front_thickness * 0.11), true)

    # The near foot is deliberately larger than the compressed far foot.
    var left_foot := PackedVector2Array([
        Vector2(-width * 0.68 - 18.0, 5.0),
        Vector2(-width * 0.48, -front_thickness * 0.62),
        Vector2(-width * 0.22, -7.0),
        Vector2(width * 0.02, 8.0),
        Vector2(-width * 0.40, 14.0),
    ])
    var right_foot := PackedVector2Array([
        Vector2(width * 0.30, -front_thickness * 0.28),
        Vector2(width * 0.50, -2.0),
        Vector2(width * 0.66 + visual_variant * 2.0, 10.0),
        Vector2(width * 0.22, 12.0),
    ])
    draw_colored_polygon(left_foot, front_color.darkened(0.08))
    draw_colored_polygon(right_foot, side_color)

    # Sparse moss follows only part of the near contour; a full green outline would
    # turn the placeholder back into a tidy tube.
    var moss_points := PackedVector2Array([
        front_points[1] + Vector2(1.0, -front_thickness * 0.34),
        front_points[2] + Vector2(2.0, -front_thickness * 0.38),
        front_points[3] + Vector2(0.0, -front_thickness * 0.34),
        front_points[4] + Vector2(-2.0, -front_thickness * 0.24),
    ])
    draw_polyline(moss_points, moss_color, maxf(5.0, front_thickness * 0.18), true)
    draw_circle(Vector2(-width * 0.37, -height * 0.58), 5.0 + visual_variant % 2, moss_color.lightened(0.12))
    draw_circle(Vector2(crown_shift, -height * 0.90), 4.0 + (visual_variant + 1) % 3, moss_color)
