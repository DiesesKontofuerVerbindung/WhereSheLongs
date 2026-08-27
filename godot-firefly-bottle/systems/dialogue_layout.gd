extends RefCounted
class_name DialogueLayout

## Unified dialogue box layout for 960x540 viewport.

const VIEWPORT := Vector2(960.0, 540.0)

const PANEL_LEFT := -380.0
const PANEL_RIGHT := 380.0
const PANEL_TOP := -220.0
const PANEL_BOTTOM := -24.0

const FONT_TITLE := 22
const FONT_SPEAKER := 20
const FONT_BODY := 17
const FONT_CG := 18

const PANEL_MARGIN := 20
const PANEL_SEPARATION := 10


static func apply_panel_offsets(panel: Control) -> void:
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = PANEL_LEFT
	panel.offset_right = PANEL_RIGHT
	panel.offset_top = PANEL_TOP
	panel.offset_bottom = PANEL_BOTTOM


static func apply_cg_dialogue_offsets(label: Label) -> void:
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = PANEL_LEFT
	label.offset_right = PANEL_RIGHT
	label.offset_top = PANEL_TOP + 40.0
	label.offset_bottom = PANEL_BOTTOM + 40.0
