extends RefCounted

const START_SCENE := "title"

const SCENES := {
	"title": {
		"id": "title",
		"type": "menu",
		"title": "河上跳石",
		"subtitle": "2D 俯视 · 素材版",
		"body": "俯视跳石头，玩法不变。\n你站在石头上，水里是你的倒影；前方石头上有一个小光人。\n按住蓄力，松手起跳。落水一次即结束。",
		"buttons": [
			{"id": "start", "text": "开始跳", "next": "play"},
		],
	},
	"play": {
		"id": "play",
		"type": "level",
		"title": "河上跳石",
		"level_id": "river_jump",
		"packed_scene": "res://levels/river_jump.tscn",
		"on_complete": "gameover",
	},
	"gameover": {
		"id": "gameover",
		"type": "menu",
		"title": "落水了",
		"subtitle": "",
		"show_result": true,
		"buttons": [
			{"id": "retry", "text": "再跳一次", "next": "play"},
			{"id": "home", "text": "返回标题", "next": "title"},
		],
	},
}


static func has_scene(scene_id: String) -> bool:
	return SCENES.has(scene_id)


static func get_scene(scene_id: String) -> Dictionary:
	if not SCENES.has(scene_id):
		return {}
	return (SCENES[scene_id] as Dictionary).duplicate(true)
