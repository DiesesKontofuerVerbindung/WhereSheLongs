extends Node

## 无摄像头 / 无检测服务的隔离测试。
##
## macOS 首次运行几乎一定没有摄像头授权，CI runner 上更是既没有摄像头、也没有
## 带 MediaPipe 的 Python。这个测试把四条依赖设备的路径拉出来单独跑，确认它们
## 在设备缺席时**有界完成**，而不是把主线程或剧情永久卡住。
##
## 必须在**不带 `--verify`** 的普通模式下运行：verify 模式下各模块会走直通分支，
## 覆盖不到真正的“没有摄像头”路径。测试会先自检这一点。
##
## 覆盖：
##   1. BlinkSystem —— 它是 autoload，每帧都在轮询 WebSocket；没有检测服务时既不能
##      报告已连接，也不能阻塞主循环，F8 调试兜底仍要能发出 blink_detected。
##      （森林结尾 source 366 原本用这个信号做无期限门，门已移除；这条断言留作回归
##      保护：以后谁再拿 blink_detected 当剧情门，至少兜底还在。）
##   2. InnerObjectsStage.arm_fan() —— 不拉起摄像头桥接器，有界发出 objects_cleared；
##   3. TextInput（DOCX 157）—— 普通模式下自动完成风扇清场并发出 finished；
##   4. WeddingChecklist —— 不启摄像头，run() 协程有界返回。
##
## 每个异步断言都有 deadline：永久等待会变成 FAIL，而不是让 CI 挂死。

const InnerObjectsStageScript := preload("res://scripts/inner_objects_stage.gd")
const TextInputScene := preload("res://levels/minigames/text_input.tscn")
const WeddingChecklistScene := preload("res://scenes/wedding/modules/wedding_checklist.tscn")

const DETECTOR_SETTLE_FRAMES := 30
const BLINK_DEADLINE := 6.0
const INNER_FAN_DEADLINE := 10.0
const TEXT_INPUT_DEADLINE := 15.0
const CHECKLIST_DEADLINE := 15.0

var _blink_fired := false
var _objects_cleared := false
var _text_finished := false
var _checklist_returned := false


func _ready() -> void:
	var failures := PackedStringArray()
	if _is_verify_mode():
		print("CAMERA_UNAVAILABLE_ISOLATION_FAIL 本测试必须在不带 --verify 的普通模式下运行")
		get_tree().quit(1)
		return
	await _verify_blink_gate_without_detector(failures)
	await _verify_inner_objects_fan_without_camera(failures)
	await _verify_text_input_without_camera(failures)
	await _verify_wedding_checklist_without_camera(failures)

	if failures.is_empty():
		print("CAMERA_UNAVAILABLE_ISOLATION_PASS detector_service=absent camera_device=absent blink_f8_fallback=true inner_fan_auto_clear=true inner_fan_bridge_spawned=false text_input_auto_finish=true wedding_checklist_auto_complete=true checklist_camera=false blocking_wait=false")
		get_tree().quit(0)
		return
	for failure in failures:
		print("CAMERA_UNAVAILABLE_ISOLATION_FAIL %s" % failure)
	get_tree().quit(1)


func _is_verify_mode() -> bool:
	return "--verify" in OS.get_cmdline_user_args() or "--verify" in OS.get_cmdline_args()


## 轮询等待，带硬 deadline。用 wall clock 而不是累加 delta：headless 下帧率不定。
func _wait_until(predicate: Callable, deadline_seconds: float) -> bool:
	var end_ms := Time.get_ticks_msec() + int(deadline_seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


## 1. 没有检测服务时的 BlinkSystem。
##
## 故意不 unlock()：BlinkSystem 在 `_on_detector_blink` 里先发 `blink_detected`、
## 再交给 controller 判定，所以 LOCKED 状态下 F8 也必须能发出信号。保持 LOCKED
## 还能避免触发 controller 的空场景切换。
func _verify_blink_gate_without_detector(failures: PackedStringArray) -> void:
	var blink := get_node_or_null("/root/BlinkSystem")
	if blink == null:
		failures.append("BlinkSystem autoload 缺失：眨眼兜底来源不存在")
		return
	if not bool(blink.config.allow_debug_key_blink):
		failures.append("allow_debug_key_blink=false：没有摄像头时 F8 兜底被关闭")

	# 检测服务不在时，WebSocket 轮询不得阻塞主循环，也不得报告已连接。
	for _i in range(DETECTOR_SETTLE_FRAMES):
		await get_tree().process_frame
	if bool(blink._hub_connected):
		failures.append("测试环境连上了眨眼检测服务，隔离前提不成立")

	_blink_fired = false
	blink.blink_detected.connect(_on_blink_detected)
	var key := InputEventKey.new()
	key.keycode = KEY_F8
	key.physical_keycode = KEY_F8
	key.pressed = true
	Input.parse_input_event(key)
	var fired := await _wait_until(func() -> bool: return _blink_fired, BLINK_DEADLINE)
	blink.blink_detected.disconnect(_on_blink_detected)
	if not fired:
		failures.append("无摄像头时 F8 没有在 %.1fs 内发出 blink_detected，眨眼兜底已失效" % BLINK_DEADLINE)
	blink.reset()


func _on_blink_detected() -> void:
	_blink_fired = true


## 2. DOCX 315 主观内心物件：没有摄像头也要能挥净。
func _verify_inner_objects_fan_without_camera(failures: PackedStringArray) -> void:
	var stage := InnerObjectsStageScript.new()
	add_child(stage)
	await get_tree().process_frame
	stage.size = Vector2(1280.0, 720.0)
	stage.activate(true)
	await get_tree().process_frame

	_objects_cleared = false
	stage.objects_cleared.connect(_on_objects_cleared)
	stage.arm_fan()
	var cleared := await _wait_until(func() -> bool: return _objects_cleared, INNER_FAN_DEADLINE)
	var snapshot: Dictionary = stage.get_debug_snapshot()
	if not cleared:
		failures.append(
			"无摄像头时 arm_fan 没有在 %.1fs 内发出 objects_cleared（camera_state=%s）"
			% [INNER_FAN_DEADLINE, str(snapshot.get("inner_fan_camera_state", "?"))]
		)
	if bool(snapshot.get("inner_fan_bridge_attached", false)):
		failures.append("自动兜底路径仍然拉起了摄像头桥接器，会在无 Python 环境下留下悬挂进程")
	if int(snapshot.get("inner_objects_cleared_count", 0)) != 1:
		failures.append("物件挥净次数异常：%s" % str(snapshot.get("inner_objects_cleared_count", 0)))

	stage.objects_cleared.disconnect(_on_objects_cleared)
	stage.deactivate()
	stage.queue_free()
	await get_tree().process_frame


func _on_objects_cleared() -> void:
	_objects_cleared = true


## 3. DOCX 157 TextInput：普通模式下风扇清场必须自动结束。
func _verify_text_input_without_camera(failures: PackedStringArray) -> void:
	var module := TextInputScene.instantiate()
	module.setup({"source": 157})
	add_child(module)
	await get_tree().process_frame
	await get_tree().process_frame

	if not bool(module.is_waiting_for_fan()):
		failures.append("TextInput 启动后没有进入风扇清场阶段，无法验证无摄像头兜底")

	_text_finished = false
	module.finished.connect(_on_text_finished)
	var finished := await _wait_until(func() -> bool: return _text_finished, TEXT_INPUT_DEADLINE)
	if not finished:
		failures.append("无摄像头时 TextInput 没有在 %.1fs 内发出 finished，玩法3 会卡在杂念波" % TEXT_INPUT_DEADLINE)
	elif bool(module.is_waiting_for_fan()):
		failures.append("TextInput 结束后仍停留在风扇清场阶段")

	module.queue_free()
	await get_tree().process_frame


func _on_text_finished(_result: Variant) -> void:
	_text_finished = true


## 4. 婚礼 checklist：无摄像头时 run() 协程必须有界返回。
func _verify_wedding_checklist_without_camera(failures: PackedStringArray) -> void:
	var module := WeddingChecklistScene.instantiate()
	if module.has_method("setup"):
		module.call("setup", "1")
	add_child(module)
	await get_tree().process_frame

	_checklist_returned = false
	_drive_checklist(module)
	var returned := await _wait_until(func() -> bool: return _checklist_returned, CHECKLIST_DEADLINE)
	var snapshot: Dictionary = module.get_debug_snapshot()
	if not returned:
		failures.append("无摄像头时 WeddingChecklist.run() 没有在 %.1fs 内返回，婚礼序章会卡在打勾" % CHECKLIST_DEADLINE)
	if not bool(snapshot.get("checklist_done", false)):
		failures.append("WeddingChecklist 未标记完成：%s" % str(snapshot))
	if bool(snapshot.get("checklist_camera", false)):
		failures.append("自动兜底路径仍然报告摄像头已连接，隔离前提不成立")

	if is_instance_valid(module):
		module.queue_free()
	await get_tree().process_frame


func _drive_checklist(module: Node) -> void:
	await module.call("run", false)
	_checklist_returned = true
