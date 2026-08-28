extends Node

const TextInputScene := preload("res://levels/minigames/text_input.tscn")
const FanGestureDetectorScript := preload("res://levels/minigames/fan_gesture_detector.gd")

var _finished_count := 0
var _result: Dictionary = {}


func _ready() -> void:
	var failures := PackedStringArray()
	var detector = FanGestureDetectorScript.new()
	var detector_samples := [
		[Vector2(640, 360), true, 0.00],
		[Vector2(640, 360), true, 0.06],
		[Vector2(640, 360), true, 0.13],
		[Vector2(720, 360), true, 0.20],
		[Vector2(800, 360), true, 0.26],
		[Vector2(500, 360), true, 0.32],
		[Vector2(380, 360), true, 0.38],
		[Vector2(700, 360), true, 0.44],
	]
	var detector_update: Dictionary = {}
	for sample in detector_samples:
		detector_update = detector.update(sample[0], sample[1], sample[2])
	if int(detector_update.get("sweep_count", 0)) < 2:
		failures.append("真实 Fan 状态机没有识别两次有效换向")
	if not bool(detector_update.get("completed", false)):
		failures.append("真实 Fan 状态机没有发出 completed")

	var module = TextInputScene.instantiate()
	module.setup({"source": 157})
	add_child(module)
	await get_tree().process_frame

	if not module.verify_contract():
		failures.append("初始 UI 契约不完整")
	module.finished.connect(_on_finished)
	if module.debug_set_text_for_verification("界".repeat(140)) != 120:
		failures.append("输入没有严格限制为 120 字符")
	if module.debug_submit_for_verification("   "):
		failures.append("空白输入被错误接受")
	if not module.debug_submit_for_verification("我害怕让所有人失望"):
		failures.append("有效输入未被接受")
	if not module.is_waiting_for_fan():
		failures.append("提交后未进入 Fan 等待状态")
	if _finished_count != 0:
		failures.append("Fan 前提前发出了 finished")
	if module.ingest_gesture("NotFan"):
		failures.append("非 Fan 手势被正式契约错误接受")
	if not module.ingest_gesture("Fan"):
		failures.append("ingest_gesture(Fan) 未触发动画")
	await get_tree().create_timer(2.10).timeout

	if _finished_count == 0:
		failures.append("有效输入后未发出 finished")
	if _finished_count != 1:
		failures.append("finished 发射次数异常：%d/1" % _finished_count)
	if module.ingest_gesture("Fan"):
		failures.append("完成后重复 Fan 仍被接受")
	if str(_result.get("result", "")) != "success":
		failures.append("完成结果不是 success")
	if int(_result.get("source", 0)) != 157:
		failures.append("完成结果未保留 DOCX 来源行")
	if int(_result.get("character_count", 0)) <= 0:
		failures.append("完成结果缺少字符计数")
	if _result.has("answer") or _result.has("text"):
		failures.append("完成结果泄露玩家原文")
	if bool(_result.get("private_text_logged", true)):
		failures.append("隐私标记错误")
	if not bool(_result.get("fan_cycle_completed", false)):
		failures.append("完成结果缺少 Fan 循环")
	if not bool(_result.get("fan_returned_to_origin", false)):
		failures.append("Fan 扫出后没有回到原位")
	if module.get_fan_return_error() > 0.5:
		failures.append("Fan 返回位置误差过大：%.3f" % module.get_fan_return_error())

	if failures.is_empty():
		print("TEXT_INPUT_MODULE_PASS source=157 empty_rejected=true max_length=120 fan_before_finish=false ingest_gesture=true fan_state_machine=true sweeps=2 finished_once=true fan_return=true raw_text_logged=false")
		get_tree().quit(0)
		return
	for failure in failures:
		print("TEXT_INPUT_MODULE_FAIL %s" % failure)
	get_tree().quit(1)


func _on_finished(result: Variant) -> void:
	_finished_count += 1
	_result = result if result is Dictionary else {"result": str(result)}
