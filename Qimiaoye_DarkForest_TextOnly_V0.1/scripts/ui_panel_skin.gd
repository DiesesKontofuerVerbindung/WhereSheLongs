extends RefCounted

const PANEL_TEXTURE_PATH := "res://assets/ui/panel/panel.png"
const INPUT_TEXTURE_PATH := "res://assets/ui/panel/input_box.png"
const BUTTON_TEXTURE_PATH := "res://assets/ui/panel/primary_button.png"

const PANEL_RECT := Rect2(302.0, 223.0, 676.0, 274.0)
const INPUT_RECT := Rect2(334.0, 329.0, 616.0, 44.0)
const BUTTON_RECT := Rect2(581.0, 418.0, 118.0, 49.0)

const PANEL_SOURCE_REGION := Rect2(302.0, 223.0, 676.0, 274.0)
const INPUT_SOURCE_REGION := Rect2(668.0, 658.0, 1232.0, 88.0)
const BUTTON_SOURCE_REGION := Rect2(1162.0, 836.0, 236.0, 98.0)


static func panel_style() -> StyleBoxTexture:
	return _cropped_style(PANEL_TEXTURE_PATH, PANEL_SOURCE_REGION)


static func input_style() -> StyleBoxTexture:
	return _cropped_style(INPUT_TEXTURE_PATH, INPUT_SOURCE_REGION)


static func button_style() -> StyleBoxTexture:
	return _cropped_style(BUTTON_TEXTURE_PATH, BUTTON_SOURCE_REGION)


static func empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func apply_fixed_rect(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size


static func _cropped_style(path: String, region: Rect2) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(path) as Texture2D
	atlas.region = region
	var style := StyleBoxTexture.new()
	style.texture = atlas
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	return style
