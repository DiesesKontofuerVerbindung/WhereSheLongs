extends Node

## 跑酷 1eb99bc + DOCX 157 风扇玩法 b198616 的阻塞性冒烟测试。

const ParkourScene := preload("res://scenes/forest/parkour/parkour_prototype.tscn")
const TextInputScene := preload("res://levels/minigames/text_input.tscn")
const FanCameraBridgeScript := preload("res://levels/minigames/fan_camera_bridge.gd")


func _ready() -> void:
	var failures := PackedStringArray()
	_verify_fan_runtime_bundle(failures)
	await _verify_text_input_module(failures)
	await _verify_parkour_runtime(failures)
	if failures.is_empty():
		print("GAMEPLAY_INTEGRATION_BLOCKER_PASS parkour=1eb99bc fan=b198616 source157=true runtime_bundle=true blocking_bug=false")
		get_tree().quit(0)
		return
	for failure in failures:
		print("GAMEPLAY_INTEGRATION_BLOCKER_FAIL %s" % failure)
	get_tree().quit(1)


func _verify_fan_runtime_bundle(failures: PackedStringArray) -> void:
	var bridge = FanCameraBridgeScript.new()
	var runtime_paths: Dictionary = bridge.prepare_runtime_bundle_for_verification()
	if runtime_paths.is_empty():
		failures.append("风扇 Python/模型运行时无法从 res:// 释放到 user://")
		bridge.free()
		return
	if int(runtime_paths.get("file_count", 0)) != FanCameraBridgeScript.RUNTIME_RESOURCE_PATHS.size():
		failures.append("风扇运行时释放文件数不完整")
	for key in ["bridge", "model", "config"]:
		var path := str(runtime_paths.get(key, ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			failures.append("风扇运行时物理文件缺失：%s" % key)
	bridge.free()


func _verify_text_input_module(failures: PackedStringArray) -> void:
	var module = TextInputScene.instantiate()
	module.setup({"source": 157})
	add_child(module)
	await get_tree().process_frame
	await get_tree().process_frame
	if not module.verify_contract():
		failures.append("DOCX 157 TextInput / Prototype_2_Fan 契约不完整")
	if not module.is_camera_bridge_attached():
		failures.append("DOCX 157 没有挂载风扇摄像头桥接器")
	if not module.is_waiting_for_fan() or not module.is_input_editable():
		failures.append("DOCX 157 启动后没有进入可输入的风扇清场阶段")
	if module.get_interference_phrases().size() != 72:
		failures.append("DOCX 157 杂念实体不是 72 个")
	module.queue_free()
	await get_tree().process_frame


func _verify_parkour_runtime(failures: PackedStringArray) -> void:
	var parkour = ParkourScene.instantiate()
	add_child(parkour)
	await get_tree().process_frame
	await get_tree().physics_frame
	var vine_floor := parkour.get_node_or_null("Gameplay/Segment02_Vines/VineRunFloor")
	if vine_floor == null or vine_floor.get_node_or_null("CollisionPolygon2D") == null:
		failures.append("Segment 02 没有应用 1eb99bc 的分段地面碰撞")
	var root02 = parkour.get_node_or_null("Gameplay/Segment02_Vines/RootObstacles/Root02")
	if root02 == null or not is_equal_approx(float(root02.get("collision_y")), 0.0):
		failures.append("Root02 碰撞高度没有更新")
	var player_runner = parkour.get_node_or_null("Player/RunnerActionController")
	var amai_runner = parkour.get_node_or_null("AmaiEcho/RunnerActionController")
	for runner in [player_runner, amai_runner]:
		if runner == null:
			failures.append("跑酷 RunnerActionController 缺失")
			continue
		if runner.get("slide_visual_offset") != Vector2(0, 22) or not is_equal_approx(float(runner.get("slide_visual_scale_y")), 0.72):
			failures.append("跑酷滑行视觉适配参数缺失")
	if player_runner != null:
		player_runner._set_slide(true)
		player_runner._execute_ground_action(1)
		if bool(player_runner.is_sliding):
			failures.append("滑行中切换跳跃没有退出 slide")
	var coordinator = parkour.get_node_or_null("VineEchoCoordinator")
	if coordinator == null:
		failures.append("VineEchoCoordinator 缺失")
	else:
		var route: PackedVector2Array = coordinator.get("echo_fixed_route")
		if route.size() < 3 or not is_equal_approx(route[2].y, 624.0):
			failures.append("阿麦固定路线没有更新到 1eb99bc")
		coordinator._running = true
		coordinator.action_locked = true
		coordinator._action_executed = true
		coordinator._locked_player_action = 1
		if not coordinator.retry_locked_player_action(2):
			failures.append("动作锁定后不能改走另一条路线")
	parkour.queue_free()
	await get_tree().process_frame
