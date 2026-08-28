extends Node

const StoryStageScript := preload("res://scripts/story_stage.gd")

var _light_reached_count := 0


func _ready() -> void:
	var failures := PackedStringArray()
	var host := Control.new()
	host.size = Vector2(1280.0, 720.0)
	add_child(host)
	var stage = StoryStageScript.new()
	stage.light_reached.connect(func() -> void: _light_reached_count += 1)
	host.add_child(stage)
	await get_tree().process_frame
	await get_tree().process_frame

	if not stage.verify_contract():
		failures.append("持续剧情舞台或人物三态动画契约不完整")
	stage.set_scene("环境背景图1")
	stage.begin_light_interaction()
	var initial: Dictionary = stage.get_debug_snapshot()
	if not bool(initial.get("long_scene_enabled", false)):
		failures.append("森林到瀑布前没有启用持续长场景")
	if float(initial.get("world_width", 0.0)) <= float(initial.get("stage_width", 0.0)):
		failures.append("长场景宽度不足，无法持续向右卷动")
	if not is_zero_approx(float(initial.get("world_scroll_ratio", -1.0))):
		failures.append("背景图1锚点没有从长场景起点开始")
	if not bool(initial.get("entry_curtain_visible", false)):
		failures.append("长场景进场黑幕层没有启用")
	if not bool(initial.get("xiaoling_visible", false)) or bool(initial.get("amai_visible", true)):
		failures.append("背景图1开始时应只显示小凌与右侧光源")
	if not bool(initial.get("light_visible", false)):
		failures.append("背景图1右侧独立光源没有出现")

	stage.debug_advance_light(0.5, true)
	var walking: Dictionary = stage.get_debug_snapshot()
	if float(walking.get("xiaoling_x", 0.0)) <= float(initial.get("xiaoling_x", 0.0)):
		failures.append("悬停光源时小凌没有自动向右走")
	stage.debug_advance_light(0.5, false)
	var stopped_x := float(stage.get_debug_snapshot().get("xiaoling_x", 0.0))
	stage.debug_advance_light(0.5, false)
	if not is_equal_approx(float(stage.get_debug_snapshot().get("xiaoling_x", 0.0)), stopped_x):
		failures.append("鼠标移出光源后小凌没有停止")
	for _step in range(12):
		stage.debug_advance_light(0.5, true)
		if _light_reached_count > 0:
			break
	if _light_reached_count != 1:
		failures.append("小凌抵达光源 trigger 后完成信号次数异常：%d/1" % _light_reached_count)

	await stage.play_action("light_trigger", true)
	var face_to_face: Dictionary = stage.get_debug_snapshot()
	if bool(face_to_face.get("light_visible", true)) or not bool(face_to_face.get("amai_visible", false)):
		failures.append("光源 trigger 后没有光灭并显示阿麦")
	if not is_equal_approx(float(face_to_face.get("darkness", 0.0)), 0.80):
		failures.append("光源 trigger 后背景黑暗覆盖不是80%")
	if int(face_to_face.get("darkness_z_index", 0)) >= 0:
		failures.append("森林黑暗遮罩层级会盖住旁白或对白 UI")
	await stage.play_action("heart_light", true)
	if not bool(stage.get_debug_snapshot().get("heart_glow_visible", false)):
		failures.append("阿麦出现后心口光源没有启用")

	var before_back := float(stage.get_debug_snapshot().get("xiaoling_x", 0.0))
	await stage.play_action("xiaoling_back_two", true)
	if float(stage.get_debug_snapshot().get("xiaoling_x", 0.0)) >= before_back:
		failures.append("小凌没有按技术说明后退两步")

	stage.set_scene("环境背景图2", true)
	var scene_two: Dictionary = stage.get_debug_snapshot()
	if float(scene_two.get("world_scroll_ratio", 0.0)) <= 0.0 or float(scene_two.get("world_scroll_x", 0.0)) <= 0.0:
		failures.append("进入背景图2剧情锚点时长场景没有连续向右卷动")
	var amai_before_walk := float(stage.get_debug_snapshot().get("amai_x", 0.0))
	await stage.play_action("amai_walk_waypoint", true)
	var amai_after_walk := float(stage.get_debug_snapshot().get("amai_x", 0.0))
	if amai_after_walk <= amai_before_walk:
		failures.append("背景图2阿麦没有慢慢往前走一段")
	if amai_after_walk >= float(stage.get_debug_snapshot().get("stage_width", 0.0)) - 70.0:
		failures.append("阿麦慢走时跑出了画面")

	stage.play_line_cue("amai_run_ahead", true)
	await get_tree().process_frame
	await get_tree().process_frame
	var run_snapshot: Dictionary = stage.get_debug_snapshot()
	if float(run_snapshot.get("amai_x", 0.0)) <= amai_after_walk:
		failures.append("旁白写阿麦跑起来时人物没有同步向前跑")
	if float(run_snapshot.get("amai_x", 0.0)) > float(run_snapshot.get("stage_width", 0.0)) - 70.0:
		failures.append("阿麦跑动后离开了屏幕约束")

	stage.set_scene("环境背景图4", true)
	var waterfall_snapshot: Dictionary = stage.get_debug_snapshot()
	if not is_equal_approx(float(waterfall_snapshot.get("world_scroll_ratio", 0.0)), 1.0):
		failures.append("瀑布前锚点没有到达长场景最右端")
	var expected_scroll := float(waterfall_snapshot.get("world_width", 0.0)) - float(waterfall_snapshot.get("stage_width", 0.0))
	if not is_equal_approx(float(waterfall_snapshot.get("world_scroll_x", 0.0)), expected_scroll):
		failures.append("长场景最右端卷动距离与画布宽度不匹配")
	if not stage.uses_continuous_forest("环境背景图3"):
		failures.append("原环境背景图锚点没有统一映射到持续森林长场景")

	if failures.is_empty():
		print("STORY_STAGE_PASS persistent_dialogue_stage=true continuous_long_scene=true source_size=9342x1440 scroll_right=true no_scene_hard_cut=true light_hover_walk=true mouse_exit_stop=true light_trigger=true darkness=80_percent face_to_face=true heart_glow=true scripted_steps=true amai_bounded=true animations=idle_run_start_run")
		get_tree().quit(0)
		return
	for failure in failures:
		print("STORY_STAGE_FAIL %s" % failure)
	get_tree().quit(1)
