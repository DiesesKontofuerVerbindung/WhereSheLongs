extends CanvasLayer

var _rect: ColorRect


func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color.BLACK
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)


func fade(fade_out: bool, duration: float = 0.4) -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP if fade_out else Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	if fade_out:
		tween.tween_property(_rect, "modulate:a", 1.0, duration)
	else:
		tween.tween_property(_rect, "modulate:a", 0.0, duration)
	await tween.finished
	if not fade_out:
		_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
