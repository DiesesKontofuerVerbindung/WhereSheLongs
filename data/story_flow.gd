extends RefCounted

## Demo scene graph — add chapters/parts here. Dialogue text lives in data/dialogue/*.json

const START_SCENE := "title_screen"

const SCENES := {
	"title_screen": {
		"id": "title_screen",
		"type": "title",
		"next": "chapter1_prologue",
	},
	"chapter1_prologue": {
		"id": "chapter1_prologue",
		"type": "dialogue",
		"title": "章节一：新婚彩排",
		"dialogue_id": "chapter1_prologue",
		"on_complete": "chapter2_prologue",
		"effects": {"vars": {"current_chapter": "chapter_1", "current_part": "prologue"}},
	},
	"chapter2_prologue": {
		"id": "chapter2_prologue",
		"type": "dialogue",
		"title": "章节二：结婚前夜",
		"dialogue_id": "chapter2_prologue",
		"on_complete": "wonderful_night_intro",
		"effects": {"vars": {"current_chapter": "chapter_2", "current_part": "prologue"}},
	},
	"wonderful_night_intro": {
		"id": "wonderful_night_intro",
		"type": "level",
		"title": "奇妙夜 - 世界",
		"level_id": "world_collapse",
		"packed_scene": "res://levels/sequences/world_collapse.tscn",
		"on_complete": "part1_forest_dark",
		"effects": {"vars": {"current_part": "part_1"}},
	},
	"part1_forest_dark": {
		"id": "part1_forest_dark",
		"type": "level",
		"title": "黑暗森林",
		"level_id": "forest_dark",
		"packed_scene": "res://levels/maps/forest_dark.tscn",
		"on_complete": "part1_dialogue_end",
	},
	"part1_dialogue_end": {
		"id": "part1_dialogue_end",
		"type": "dialogue",
		"title": "PART 1",
		"dialogue_id": "part1_end",
		"on_complete": "part2_forest_path",
		"effects": {"vars": {"current_part": "part_2"}, "flags": {"part1_complete": true}},
	},
	"part2_forest_path": {
		"id": "part2_forest_path",
		"type": "level",
		"title": "森林岔路",
		"level_id": "forest_path",
		"packed_scene": "res://levels/maps/forest_path.tscn",
		"on_complete": "part2_parkour",
	},
	"part2_parkour": {
		"id": "part2_parkour",
		"type": "level",
		"title": "追逐阿麦",
		"level_id": "parkour",
		"packed_scene": "res://levels/minigames/parkour.tscn",
		"on_complete": "part2_waterfall_cg",
	},
	"part2_waterfall_cg": {
		"id": "part2_waterfall_cg",
		"type": "cg",
		"cg_id": "waterfall",
		"dialogue_id": "part2_waterfall",
		"on_complete": "part2_descent",
	},
	"part2_descent": {
		"id": "part2_descent",
		"type": "level",
		"title": "瀑降",
		"level_id": "waterfall_descent",
		"packed_scene": "res://levels/minigames/waterfall_descent.tscn",
		"on_complete": "part2_heart_qte",
	},
	"part2_heart_qte": {
		"id": "part2_heart_qte",
		"type": "level",
		"title": "心动互动",
		"level_id": "heart_qte",
		"packed_scene": "res://levels/maps/stream_area.tscn",
		"on_complete": "part2_stream_dialogue",
	},
	"part2_stream_dialogue": {
		"id": "part2_stream_dialogue",
		"type": "dialogue",
		"title": "溪流",
		"dialogue_id": "part2_stream",
		"on_complete": "part2_continue_placeholder",
	},
	"part2_continue_placeholder": {
		"id": "part2_continue_placeholder",
		"type": "dialogue",
		"title": "PART 2 后半",
		"dialogue_id": "part2_continue",
		"on_complete": "part3_lake",
		"effects": {"vars": {"current_part": "part_3", "affection_amai": {"value": 20, "op": "add"}}},
	},
	"part3_lake": {
		"id": "part3_lake",
		"type": "level",
		"title": "神秘湖",
		"level_id": "lake_area",
		"packed_scene": "res://levels/maps/lake_area.tscn",
		"on_complete": "part3_stone_jump",
	},
	"part3_stone_jump": {
		"id": "part3_stone_jump",
		"type": "level",
		"title": "跳石头",
		"level_id": "stone_jump",
		"packed_scene": "res://levels/minigames/stone_jump.tscn",
		"on_complete": "part3_lake_dialogue",
	},
	"part3_lake_dialogue": {
		"id": "part3_lake_dialogue",
		"type": "dialogue",
		"title": "PART 3",
		"dialogue_id": "part3_lake_end",
		"on_complete": "part4_mystery_girl",
	},
	"part4_mystery_girl": {
		"id": "part4_mystery_girl",
		"type": "cg",
		"cg_id": "mystery_girl_save",
		"dialogue_id": "part4_mystery_girl",
		"on_complete": "demo_end",
		"effects": {"vars": {"current_part": "part_4"}},
	},
	"demo_end": {
		"id": "demo_end",
		"type": "dialogue",
		"title": "Demo 结束",
		"dialogue_id": "demo_end",
		"choices": [
			{"id": "quit", "text": "结束 Demo", "next": "quit_game"},
		],
	},
}


static func has_scene(scene_id: String) -> bool:
	return SCENES.has(scene_id)


static func get_scene(scene_id: String) -> Dictionary:
	if not SCENES.has(scene_id):
		return {}
	return (SCENES[scene_id] as Dictionary).duplicate(true)
