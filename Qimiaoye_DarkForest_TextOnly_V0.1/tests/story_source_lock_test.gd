extends Node

const StoryData := preload("res://scripts/story_data.gd")
const StorySourceLock := preload("res://scripts/story_source_lock.gd")


func _ready() -> void:
	var errors := StorySourceLock.validate(StoryData.get_events())
	if errors.is_empty():
		print("STORY_SOURCE_LOCK_PASS anchors=22 baseline=53ba079 source_351_visible_lines=0")
		get_tree().quit(0)
		return
	for error in errors:
		print("STORY_SOURCE_LOCK_FAIL %s" % error)
	get_tree().quit(1)
