extends RefCounted

## Replace texture paths in Inspector-ready catalog when formal CG arrives.

const ENTRIES := {
	"forest_dark": {
		"title": "黑暗森林",
		"color": Color(0.04, 0.05, 0.08),
		"texture": "",
		"pan": Vector2(0, 0),
	},
	"amai_first_appear": {
		"title": "阿麦初次出现",
		"color": Color(0.08, 0.06, 0.12),
		"texture": "",
		"pan": Vector2(20, 0),
	},
	"waterfall": {
		"title": "瀑布",
		"color": Color(0.05, 0.1, 0.18),
		"texture": "",
		"pan": Vector2(0, -15),
	},
	"dive": {
		"title": "跳水",
		"color": Color(0.03, 0.08, 0.2),
		"texture": "",
		"pan": Vector2(0, 30),
	},
	"lake": {
		"title": "神秘湖",
		"color": Color(0.06, 0.02, 0.1),
		"texture": "",
		"pan": Vector2(-10, 0),
	},
	"xiaoling_fall": {
		"title": "小凌落水",
		"color": Color(0.02, 0.05, 0.12),
		"texture": "",
		"pan": Vector2(0, 20),
	},
	"mystery_girl_save": {
		"title": "神秘女孩",
		"color": Color(0.1, 0.06, 0.14),
		"texture": "",
		"pan": Vector2(0, 0),
	},
}


static func get_entry(cg_id: String) -> Dictionary:
	if not ENTRIES.has(cg_id):
		return {"title": cg_id, "color": Color.BLACK, "texture": "", "pan": Vector2.ZERO}
	return (ENTRIES[cg_id] as Dictionary).duplicate(true)
