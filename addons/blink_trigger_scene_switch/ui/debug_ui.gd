class_name BlinkDebugUI
extends CanvasLayer

## Text-only status. No camera preview image.

var label: Label


func _ready() -> void:
	layer = 129
	label = Label.new()
	label.position = Vector2(12, 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.7))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)


func set_text(text: String) -> void:
	if label:
		label.text = text


func hide_preview() -> void:
	pass


func set_jpeg_preview(_b64: String) -> void:
	# Intentionally ignored — no in-game camera preview.
	pass
