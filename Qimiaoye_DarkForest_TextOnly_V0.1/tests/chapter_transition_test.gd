extends Node

const ChapterTransitionScript := preload("res://scripts/chapter_transition.gd")


func _ready() -> void:
	var failures := PackedStringArray()
	var transition = ChapterTransitionScript.new()
	add_child(transition)
	await get_tree().process_frame
	if not transition.verify_contract():
		failures.append("章节转场视觉契约不完整")
	var blocker := transition.get_node_or_null("TransitionUI/BlackFade") as ColorRect
	var loading_label := transition.get_node_or_null("TransitionUI/LoadingTitle") as Label
	if blocker == null or blocker.color != Color.BLACK or blocker.mouse_filter != Control.MOUSE_FILTER_STOP:
		failures.append("章节转场黑屏或输入拦截异常")
	if loading_label == null or loading_label.text != "Where She Longs":
		failures.append("章节转场右下角标题异常")
	elif not is_equal_approx(loading_label.anchor_left, 1.0) or not is_equal_approx(loading_label.anchor_top, 1.0):
		failures.append("章节转场标题没有锚定右下角")
	for scene_path in [
		"res://scenes/mystic_night/mystic_night.tscn",
		"res://main.tscn",
	]:
		if not ResourceLoader.exists(scene_path, "PackedScene"):
			failures.append("章节转场目标不存在：%s" % scene_path)
	transition.queue_free()
	if not failures.is_empty():
		for failure in failures:
			print("CHAPTER_TRANSITION_TEST_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("CHAPTER_TRANSITION_TEST_PASS text=Where_She_Longs anchor=bottom_right fade=black threaded_load=true targets=mystic_night_forest")
	get_tree().quit(0)
