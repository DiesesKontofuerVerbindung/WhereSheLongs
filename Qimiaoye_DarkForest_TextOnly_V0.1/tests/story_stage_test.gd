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
	if int(initial.get("world_z_index", -100)) <= -100:
		failures.append("森林长图层级没有高于主黑色底板")
	var back_z := int(initial.get("forest_back_z_index", -100))
	var front_z := int(initial.get("forest_front_z_index", -100))
	var xiaoling_z := int(initial.get("xiaoling_z_index", -100))
	var amai_z := int(initial.get("amai_z_index", -100))
	if not back_z < xiaoling_z or not xiaoling_z < front_z or amai_z != xiaoling_z:
		failures.append("人物没有稳定夹在森林后景与前景之间")
	if float(initial.get("xiaoling_visual_scale", 0.0)) < 0.28:
		failures.append("小凌人物尺寸低于剧情舞台基准")
	if float(initial.get("amai_visual_scale", 0.0)) < 0.34:
		failures.append("阿麦没有按要求再次放大")
	if not is_equal_approx(float(initial.get("xiaoling_gaussian_blur_strength", -1.0)), 0.90):
		failures.append("小凌没有应用90%高斯模糊")
	if float(initial.get("actor_ground_ratio", 0.0)) < 0.83:
		failures.append("人物地面基准线仍然过高，视觉上会悬空")
	var ground_y := float(initial.get("actor_ground_y", -100.0))
	if absf(float(initial.get("xiaoling_feet_y", -200.0)) - ground_y) > 0.5:
		failures.append("小凌脚底没有落在森林地面基准线上")
	if absf(float(initial.get("amai_feet_y", -200.0)) - ground_y) > 0.5:
		failures.append("阿麦脚底没有落在森林地面基准线上")
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
	stage.prepare_dialogue("阿麦")
	face_to_face = stage.get_debug_snapshot()
	if not bool(face_to_face.get("xiaoling_facing_right", false)) or bool(face_to_face.get("amai_facing_right", true)):
		failures.append("对白出现时小凌与阿麦没有自动面对面")
	if not is_equal_approx(float(face_to_face.get("amai_alpha", 0.0)), 1.0):
		failures.append("阿麦淡入结束后没有完全不透明")
	stage.restore_for_source(53, "环境背景图1")
	if not is_equal_approx(float(stage.get_debug_snapshot().get("amai_alpha", 0.0)), 1.0):
		failures.append("开发跳转到第53行时阿麦停在半透明状态")
	stage.set_scene("环境背景图1")
	stage.begin_light_interaction()
	await stage.play_action("light_trigger", true)
	stage.prepare_dialogue("阿麦")

	# 玩家按住 D 跟随时，阿麦必须同步进入奔跑，否则 idle 贴图会贴着地面漂移。
	stage.update_manual_movement(1.0, 0.1, "follow_right")
	await get_tree().physics_frame
	var following: Dictionary = stage.get_debug_snapshot()
	if str(following.get("amai_animation", "")) == "idle":
		failures.append("跟随卷动时阿麦仍是 idle，会出现贴地漂移")
	if is_zero_approx(float(following.get("amai_velocity_x", 0.0))):
		failures.append("跟随卷动时阿麦没有同步速度信号")
	stage.finish_manual_movement("follow_right")
	await get_tree().physics_frame
	if not is_zero_approx(float(stage.get_debug_snapshot().get("amai_velocity_x", 1.0))):
		failures.append("跟随结束后阿麦没有停下")

	await stage.play_action("heart_light", true)
	var heart_snapshot: Dictionary = stage.get_debug_snapshot()
	if not bool(heart_snapshot.get("heart_glow_visible", false)):
		failures.append("阿麦出现后心口光源没有启用")
	var heart_offset := float(heart_snapshot.get("actor_ground_y", 0.0)) - float(heart_snapshot.get("heart_glow_y", 0.0))
	var expected_heart_offset := 579.0 * float(heart_snapshot.get("amai_visual_scale", 0.0))
	if absf(heart_offset - expected_heart_offset) > 0.5:
		failures.append("阿麦光晕没有对准源图暖黄心口核心")
	if not is_equal_approx(float(heart_snapshot.get("amai_heart_from_feet_source", 0.0)), 579.0):
		failures.append("阿麦心口锚点仍使用旧的嘴部偏高坐标")
	if not bool(heart_snapshot.get("heart_glow_warm_yellow", false)):
		failures.append("阿麦心口光晕不是暖黄色")

	var before_back := float(stage.get_debug_snapshot().get("xiaoling_x", 0.0))
	await stage.play_action("xiaoling_back_two", true)
	if float(stage.get_debug_snapshot().get("xiaoling_x", 0.0)) >= before_back:
		failures.append("小凌没有按技术说明后退两步")

	await stage.travel_to_scene("环境背景图2", "FIREFLY_GUIDE", true)
	var scene_two: Dictionary = stage.get_debug_snapshot()
	if float(scene_two.get("world_scroll_ratio", 0.0)) <= 0.0 or float(scene_two.get("world_scroll_x", 0.0)) <= 0.0:
		failures.append("进入背景图2剧情锚点时长场景没有连续向右卷动")
	if str(scene_two.get("last_continuous_transition", "")) != "FIREFLY_GUIDE":
		failures.append("森林内部转换没有走持续跑动转场")
	if float(scene_two.get("last_continuous_transition_duration", 0.0)) < 2.4:
		failures.append("森林持续跑动转场仍然太快")
	if not bool(scene_two.get("last_continuous_transition_ran_actors", false)):
		failures.append("长图卷动时人物没有同步进入跑动状态")
	var amai_before_walk := float(stage.get_debug_snapshot().get("amai_x", 0.0))
	await stage.play_action("amai_walk_waypoint", true)
	var amai_after_walk := float(stage.get_debug_snapshot().get("amai_x", 0.0))
	if amai_after_walk <= amai_before_walk:
		failures.append("背景图2阿麦没有慢慢往前走一段")
	if amai_after_walk >= float(stage.get_debug_snapshot().get("stage_width", 0.0)) - 70.0:
		failures.append("阿麦慢走时跑出了画面")

	stage.play_line_cue("amai_run_ahead", false)
	await get_tree().physics_frame
	var running_snapshot: Dictionary = stage.get_debug_snapshot()
	if str(running_snapshot.get("amai_animation", "")) != "run":
		failures.append("阿麦向右脚本位移时没有立即播放循环奔跑动作")
	if not bool(running_snapshot.get("amai_facing_right", false)):
		failures.append("阿麦向右脚本位移时奔跑方向仍然朝左")
	await get_tree().create_timer(0.35).timeout
	var run_snapshot: Dictionary = stage.get_debug_snapshot()
	if float(run_snapshot.get("amai_x", 0.0)) <= amai_after_walk:
		failures.append("旁白写阿麦跑起来时人物没有同步向前跑")
	if float(run_snapshot.get("amai_x", 0.0)) > float(run_snapshot.get("stage_width", 0.0)) - 70.0:
		failures.append("阿麦跑动后离开了屏幕约束")
	if str(run_snapshot.get("amai_animation", "")) != "idle":
		failures.append("阿麦脚本位移结束后没有恢复待机动作")

	stage.set_scene("环境背景图4", true)
	var waterfall_snapshot: Dictionary = stage.get_debug_snapshot()
	if not is_equal_approx(float(waterfall_snapshot.get("world_scroll_ratio", 0.0)), 1.0):
		failures.append("瀑布前锚点没有到达长场景最右端")
	if not bool(waterfall_snapshot.get("waterfall_active", false)) or not bool(waterfall_snapshot.get("waterfall_assets_loaded", false)):
		failures.append("环境背景图4没有切入真实瀑布三层美术")
	if waterfall_snapshot.get("waterfall_source_size", Vector2.ZERO) != Vector2(2560.0, 1440.0):
		failures.append("瀑布美术尺寸契约不是2560x1440")
	if not is_equal_approx(float(waterfall_snapshot.get("waterfall_anchor_source_x", -1.0)), 9342.0):
		failures.append("瀑布没有无缝追加在森林长图右端")
	var waterfall_back_z := int(waterfall_snapshot.get("waterfall_back_z_index", -100))
	var waterfall_front_z := int(waterfall_snapshot.get("waterfall_front_z_index", -100))
	if not waterfall_back_z < int(waterfall_snapshot.get("xiaoling_z_index", -100)) or not int(waterfall_snapshot.get("xiaoling_z_index", -100)) < waterfall_front_z:
		failures.append("小凌在瀑布段没有夹在后景与前景之间")
	var stage_width := float(waterfall_snapshot.get("stage_width", 0.0))
	var stage_height := float(stage.size.y)
	var xiaoling_stop_ratio := float(waterfall_snapshot.get("waterfall_xiaoling_stop_ratio", 0.0))
	var amai_stop_ratio := float(waterfall_snapshot.get("waterfall_amai_stop_ratio", 0.0))
	if not is_equal_approx(float(waterfall_snapshot.get("xiaoling_x", 0.0)), stage_width * xiaoling_stop_ratio):
		failures.append("小凌没有停在瀑布左侧蓝框区域")
	if not is_equal_approx(float(waterfall_snapshot.get("amai_x", 0.0)), stage_width * amai_stop_ratio):
		failures.append("阿麦没有停在瀑布左侧蓝框区域")
	if not bool(waterfall_snapshot.get("waterfall_slope_up_right", false)):
		failures.append("瀑布前地面没有按要求向右上形成小斜坡")
	if not bool(waterfall_snapshot.get("waterfall_slope_gentle", false)):
		failures.append("瀑布前坡度过陡，人物脚底无法贴合美术地面")
	if not bool(waterfall_snapshot.get("waterfall_stop_before_fall", false)):
		failures.append("人物终点仍然进入了瀑布水体")
	if float(waterfall_snapshot.get("xiaoling_feet_y", 0.0)) <= float(waterfall_snapshot.get("amai_feet_y", 0.0)):
		failures.append("人物脚底没有沿向右上坡道逐渐抬升")
	var amai_feet_ratio := float(waterfall_snapshot.get("amai_feet_y", stage_height)) / stage_height
	if amai_feet_ratio < 0.66 or amai_feet_ratio > 0.69:
		failures.append("阿麦脚底没有贴住瀑布前小斜坡")
	stage.restore_for_source(125, "环境背景图4")
	var restored_waterfall: Dictionary = stage.get_debug_snapshot()
	if not is_equal_approx(float(restored_waterfall.get("xiaoling_x", 0.0)), stage_width * xiaoling_stop_ratio):
		failures.append("开发者跳到第125行后，小凌又被放回瀑布水体")
	if not is_equal_approx(float(restored_waterfall.get("amai_x", 0.0)), stage_width * amai_stop_ratio):
		failures.append("开发者跳到第125行后，阿麦又被放回瀑布水体")
	var expected_scroll := float(waterfall_snapshot.get("world_width", 0.0)) - float(waterfall_snapshot.get("stage_width", 0.0))
	if not is_equal_approx(float(waterfall_snapshot.get("world_scroll_x", 0.0)), expected_scroll):
		failures.append("长场景最右端卷动距离与画布宽度不匹配")
	if not stage.uses_continuous_forest("环境背景图3"):
		failures.append("原环境背景图锚点没有统一映射到持续森林长场景")

	# 神秘湖是独立世界：不得并入森林长场景，也不得与森林图层同时显示。
	if stage.uses_continuous_forest("环境背景图6"):
		failures.append("神秘湖被错误并入森林-瀑布连续长场景")
	if not stage.uses_lake_stage("环境背景图6") or not stage.uses_art_stage("环境背景图6"):
		failures.append("环境背景图6没有接入湖边美术舞台")
	stage.set_scene("环境背景图6", true)
	var lake_snapshot: Dictionary = stage.get_debug_snapshot()
	if not bool(lake_snapshot.get("lake_stage_ready", false)):
		failures.append("湖边三层美术没有全部建立")
	if not is_equal_approx(float(lake_snapshot.get("lake_source_width", 0.0)), 6117.0):
		failures.append("湖边底图宽度与交付素材 6117 不一致")
	if not bool(lake_snapshot.get("lake_active", false)):
		failures.append("进入环境背景图6后湖边世界没有显示")
	if not bool(lake_snapshot.get("lake_world_exclusive", false)):
		failures.append("湖边世界与森林长场景同时可见")
	if not bool(lake_snapshot.get("lake_actor_between_layers", false)):
		failures.append("人物没有夹在湖边后景与前景之间")
	var lake_feet_ratio := float(lake_snapshot.get("amai_feet_y", 0.0)) / float(stage.size.y)
	if not is_equal_approx(lake_feet_ratio, float(lake_snapshot.get("lake_ground_ratio", 0.0))):
		failures.append("人物脚底没有踩在湖岸滩地上")
	stage.set_scene("环境背景图4", true)
	var back_to_forest: Dictionary = stage.get_debug_snapshot()
	if bool(back_to_forest.get("lake_active", true)):
		failures.append("离开环境背景图6后湖边世界没有关闭")

	if failures.is_empty():
		print("STORY_STAGE_PASS persistent_dialogue_stage=true continuous_long_scene=true source_size=11902x1440 waterfall_source_size=2560x1440 waterfall_appended=true waterfall_layers=back_front_particles actor_between_waterfall_layers=true waterfall_slope_up_right=true waterfall_slope_gentle=true waterfall_stop_before_fall=true dev_jump_125_restores_waterfall_approach=true scroll_right=true no_scene_hard_cut=true light_hover_walk=true mouse_exit_stop=true light_trigger=true darkness=80_percent face_to_face=true heart_glow=true heart_glow_source_y=606 heart_glow_source_offset=579 heart_glow_chest_aligned=true heart_glow_warm_yellow=true xiaoling_gaussian_blur=0.90 amai_visual_scale=0.34 amai_scripted_run_sync=true amai_run_facing_right=true scripted_steps=true amai_bounded=true animations=idle_run_start_run lake_stage=true lake_source_size=6117x1440 lake_layers=back_front_particles lake_world_exclusive=true lake_actor_between_layers=true lake_ground_ratio=0.86")
		get_tree().quit(0)
		return
	for failure in failures:
		print("STORY_STAGE_FAIL %s" % failure)
	get_tree().quit(1)
