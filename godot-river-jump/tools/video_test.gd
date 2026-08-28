extends SceneTree

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://assets/backgrounds/river_bg.ogv"
	print("exists=", ResourceLoader.exists(path))
	var loaded = ResourceLoader.load(path)
	print("loaded=", loaded, " type=", typeof(loaded))
	if loaded is VideoStream:
		print("video ok")
	quit(0)
