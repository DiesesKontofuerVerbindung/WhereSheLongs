class_name BlinkDebugUI
extends CanvasLayer

var label: Label


func _ready() -> void:
	layer = 129
	label = Label.new()
	label.position = Vector2(12, 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.7))
	add_child(label)


func set_text(text: String) -> void:
	if label:
		label.text = text
