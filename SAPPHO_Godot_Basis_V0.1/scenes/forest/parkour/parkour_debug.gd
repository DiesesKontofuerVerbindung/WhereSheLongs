extends Node2D
class_name ParkourDebug

@export var controller_path: NodePath = ^".."
@export var platforms_path: NodePath = ^"../Gameplay/Platforms"

var _debug_visible := false
var _collision_visible := true
var _labels_visible := true

const EXTRA_SHAPE_PATHS := [
    ^"../Gameplay/Segment02_Vines/VineGate/StaticBody2D/CollisionShape2D",
    ^"../Gameplay/Segment02_Vines/VineGate/JumpSensor/CollisionShape2D",
    ^"../Gameplay/Segment02_Vines/VineGate/SlideSensor/CollisionShape2D",
    ^"../Gameplay/Segment03_PredatorPlant/PredatorPlant/HazardArea/CollisionShape2D",
    ^"../Gameplay/Segment03_PredatorPlant/PredatorPlant/RiskRouteSensor/CollisionShape2D",
    ^"../Gameplay/SectionTransitions/Segment01Exit/CollisionShape2D",
    ^"../Gameplay/SectionTransitions/Segment02Exit/CollisionShape2D",
    ^"../Gameplay/SectionTransitions/Segment03Finish/CollisionShape2D",
]

@onready var controller: ParkourController = get_node(controller_path)
@onready var platforms_root: Node = get_node(platforms_path)
@onready var debug_canvas: CanvasLayer = $CanvasLayer
@onready var debug_label: Label = $CanvasLayer/PanelContainer/DebugText


func _ready() -> void:
    debug_canvas.visible = _debug_visible


func _process(_delta: float) -> void:
    if not _debug_visible:
        return
    debug_label.text = controller.get_debug_text()
    queue_redraw()


func toggle_debug() -> void:
    _debug_visible = not _debug_visible
    debug_canvas.visible = _debug_visible
    queue_redraw()


func toggle_collision() -> void:
    _collision_visible = not _collision_visible
    queue_redraw()


func toggle_labels() -> void:
    _labels_visible = not _labels_visible
    queue_redraw()


func _draw() -> void:
    if not _debug_visible:
        return
    for child in platforms_root.get_children():
        if not child is ParkourPlatform:
            continue
        var platform := child as ParkourPlatform
        if _collision_visible:
            var body_rectangle := platform.body_shape.shape as RectangleShape2D
            var body_center := platform.global_position + platform.static_body.position
            draw_rect(Rect2(body_center - body_rectangle.size * 0.5, body_rectangle.size), Color(0.2, 0.9, 1.0, 0.32), true)
            draw_rect(Rect2(body_center - body_rectangle.size * 0.5, body_rectangle.size), Color(0.2, 0.9, 1.0, 0.95), false, 3.0)

            var sensor_rectangle := platform.sensor_shape.shape as RectangleShape2D
            var sensor_center := platform.global_position + platform.landing_sensor.position
            draw_rect(Rect2(sensor_center - sensor_rectangle.size * 0.5, sensor_rectangle.size), Color(1.0, 0.35, 0.75, 0.32), true)
            draw_rect(Rect2(sensor_center - sensor_rectangle.size * 0.5, sensor_rectangle.size), Color(1.0, 0.35, 0.75, 0.95), false, 2.0)
        if _labels_visible:
            var label_text := str(platform.platform_id).replace("_", ".")
            draw_string(ThemeDB.fallback_font, platform.global_position + Vector2(-28.0, -54.0), label_text, HORIZONTAL_ALIGNMENT_CENTER, 56.0, 24, Color(1.0, 0.95, 0.3))
    if _collision_visible:
        for shape_path in EXTRA_SHAPE_PATHS:
            var collision_shape := get_node_or_null(shape_path) as CollisionShape2D
            if collision_shape == null or not collision_shape.shape is RectangleShape2D:
                continue
            var rectangle := collision_shape.shape as RectangleShape2D
            var center := collision_shape.global_position
            draw_rect(Rect2(center - rectangle.size * 0.5, rectangle.size), Color(1.0, 0.55, 0.15, 0.22), true)
            draw_rect(Rect2(center - rectangle.size * 0.5, rectangle.size), Color(1.0, 0.55, 0.15, 0.9), false, 2.0)
