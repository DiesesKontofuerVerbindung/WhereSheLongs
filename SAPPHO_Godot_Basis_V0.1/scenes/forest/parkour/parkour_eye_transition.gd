extends CanvasLayer
class_name ParkourEyeTransition

@export var duration := 0.45

var busy := false

@onready var top_lid: ColorRect = $TopLid
@onready var bottom_lid: ColorRect = $BottomLid
@onready var caption: Label = $Caption


func _ready() -> void:
    _set_open_positions()
    visible = false


func close_eyes(message: String = "") -> void:
    if busy:
        return
    busy = true
    visible = true
    caption.text = message
    caption.visible = false
    var viewport_size := get_viewport().get_visible_rect().size
    var half_height := viewport_size.y * 0.5
    var tween := create_tween().set_parallel(true)
    tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(top_lid, "position:y", 0.0, duration)
    tween.tween_property(bottom_lid, "position:y", half_height, duration)
    await tween.finished
    caption.visible = not message.is_empty()


func open_eyes() -> void:
    caption.visible = false
    var viewport_size := get_viewport().get_visible_rect().size
    var half_height := viewport_size.y * 0.5
    var tween := create_tween().set_parallel(true)
    tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    tween.tween_property(top_lid, "position:y", -half_height, duration)
    tween.tween_property(bottom_lid, "position:y", viewport_size.y, duration)
    await tween.finished
    visible = false
    busy = false


func _set_open_positions() -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    var half_height := viewport_size.y * 0.5
    top_lid.position = Vector2(0.0, -half_height)
    top_lid.size = Vector2(viewport_size.x, half_height)
    bottom_lid.position = Vector2(0.0, viewport_size.y)
    bottom_lid.size = Vector2(viewport_size.x, half_height)
