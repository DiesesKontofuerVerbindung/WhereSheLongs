extends RefCounted

const PlaceholderAssets := preload("res://systems/placeholder_assets.gd")

const ENTRIES := {
	"xiaoling": Color(0.85, 0.75, 0.9),
	"amai": Color(0.3, 0.35, 0.55),
	"mystery_girl": Color(0.55, 0.45, 0.5),
}


static func get_texture(portrait_id: String) -> Texture2D:
	var color: Color = ENTRIES.get(portrait_id, Color.GRAY)
	return PlaceholderAssets.make_character_sprite(color, portrait_id)
