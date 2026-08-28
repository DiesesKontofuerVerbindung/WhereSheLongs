extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level_scene: PackedScene = load("res://levels/river_jump.tscn")
	var level: Node = level_scene.instantiate()
	root.add_child(level)
	for i in 10:
		await process_frame
	var top := level.get_node_or_null("TopLayer")
	var refs := level.get_node_or_null("Reflections")
	print("TopLayer children=", top.get_child_count() if top else -1)
	print("Reflections children=", refs.get_child_count() if refs else -1)
	print("player_tex=", load("res://assets/characters/player.png") != null)
	print("guide_tex=", load("res://assets/characters/guide.png") != null)
	if top:
		for c in top.get_children():
			print("  ", c.name, " visible=", c.visible, " z=", c.z_index)
	quit(0)
