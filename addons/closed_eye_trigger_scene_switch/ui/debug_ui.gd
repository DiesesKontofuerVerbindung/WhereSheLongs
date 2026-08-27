class_name ClosedEyeDebugUI
extends CanvasLayer

var label: Label
var preview: TextureRect
var _image := Image.new()
var _texture := ImageTexture.new()


func _ready() -> void:
	layer = 130
	label = Label.new()
	label.position = Vector2(12, 12)
	label.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	add_child(label)
	preview = TextureRect.new()
	preview.position = Vector2(12, 148)
	preview.size = Vector2(240, 180)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(preview)


func set_text(text: String) -> void:
	if label:
		label.text = text


func set_jpeg_preview(b64: String) -> void:
	if b64.is_empty() or preview == null:
		return
	var raw := Marshalls.base64_to_raw(b64)
	if raw.is_empty():
		return
	if _image.load_jpg_from_buffer(raw) != OK:
		return
	_texture.set_image(_image)
	preview.texture = _texture
