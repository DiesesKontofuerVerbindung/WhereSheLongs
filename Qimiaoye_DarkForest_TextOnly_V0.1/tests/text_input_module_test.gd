extends Node

const TextInputScene := preload("res://levels/minigames/text_input.tscn")
const FanGestureDetectorScript := preload("res://levels/minigames/fan_gesture_detector.gd")

const EXPECTED_PHRASES := [
	"这样不好吗",
	"别跑这么远",
	"恭喜你被录用了",
	"可是我们要结婚……",
]

var _finished_count := 0
var _result: Dictionary = {}


func _ready() -> void:
	var failures := PackedStringArray()
	_verify_detector(failures)
	await _verify_length_limit(failures)

	var module = TextInputScene.instantiate()
	module.setup({"source": 157})
	add_child(module)
	await get_tree().process_frame
	await get_tree().process_frame

	if not module.verify_contract():
		failures.append("初始 UI / 杂念契约不完整")
	module.finished.connect(_on_finished)
	if module.debug_submit_for_verification("   "):
		failures.append("空白输入被错误接受")

	if not module.is_interference_active() or not module.is_waiting_for_fan():
		failures.append("模块启动后没有进入 Fan 等待状态")
	if not module.are_interference_entities_clustered():
		failures.append("杂念没有在输入区形成可挥散的聚集层")
	if module.is_input_editable():
		failures.append("完成 Fan 前输入框被错误解锁")
	if module.get_wave_started_count() != 1:
		failures.append("初始杂念场只应启动一次")
	_verify_interference_phrases(module.get_interference_phrases(), failures)
	if module.ingest_gesture("NotFan"):
		failures.append("非 Fan 手势被正式契约错误接受")
	for sample in _detector_samples():
		module.ingest_hand_sample(sample[0], sample[1], sample[2])
	await get_tree().create_timer(0.95).timeout

	if module.get_wave_cleared_count() != 1:
		failures.append("Fan 样本没有完整驱散杂念")
	if module.is_interference_active():
		failures.append("驱散后杂念仍处于阻塞状态")
	if not module.is_input_editable():
		failures.append("Fan 驱散后输入框没有恢复编辑")
	if _finished_count != 0:
		failures.append("驱散后提前结束，玩家无法输入")

	module.debug_set_text_for_verification("我在想但大家都已经替我决定了")
	if module.get_wave_started_count() != 1 or module.is_interference_active():
		failures.append("输入阶段不应重新启动杂念场")

	if not module.debug_submit_for_verification("我在想但大家都已经替我决定了"):
		failures.append("完成 Fan 后无法提交自己的想法")
	await get_tree().create_timer(0.35).timeout

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
	if bool(_result.get("private_text_logged", true)) or bool(_result.get("intrusive_text_logged", true)):
		failures.append("隐私标记错误")
	if not bool(_result.get("fan_cycle_completed", false)):
		failures.append("完成结果缺少 Fan 驱散记录")
	if int(_result.get("interference_waves_cleared", 0)) != 1:
		failures.append("完成结果没有记录初始 Fan 清场")
	if int(_result.get("interference_entity_count", 0)) != 12:
		failures.append("完成结果中的杂念实体数错误")
	if not bool(_result.get("input_resumed_after_fan", false)):
		failures.append("完成结果没有证明 Fan 后恢复输入")

	if failures.is_empty():
		print("TEXT_INPUT_FAN_FIRST_PASS source=157 fan_before_input=true cluster_ready=true opencv_fan=true sweeps=2 phrases=4 entities=12 input_unlocked=true finish_after_input=true raw_text_logged=false")
		get_tree().quit(0)
		return
	for failure in failures:
		print("TEXT_INPUT_INTERFERENCE_FAIL %s" % failure)
	get_tree().quit(1)


func _verify_detector(failures: PackedStringArray) -> void:
	var detector = FanGestureDetectorScript.new()
	var detector_update: Dictionary = {}
	for sample in _detector_samples():
		detector_update = detector.update(sample[0], sample[1], sample[2])
	if int(detector_update.get("sweep_count", 0)) < 2:
		failures.append("真实 Fan 状态机没有识别两次有效换向")
	if not bool(detector_update.get("completed", false)):
		failures.append("真实 Fan 状态机没有发出 completed")


func _verify_length_limit(failures: PackedStringArray) -> void:
	var length_module = TextInputScene.instantiate()
	length_module.setup({"source": 157})
	add_child(length_module)
	await get_tree().process_frame
	if length_module.debug_set_text_for_verification("界".repeat(140)) != 120:
		failures.append("输入没有严格限制为 120 字符")
	length_module.queue_free()
	await get_tree().process_frame


func _verify_interference_phrases(phrases: PackedStringArray, failures: PackedStringArray) -> void:
	if phrases.size() != 12:
		failures.append("杂念实体数不是 12：%d" % phrases.size())
	var seen: Dictionary = {}
	for phrase in phrases:
		seen[phrase] = true
	for expected in EXPECTED_PHRASES:
		if not seen.has(expected):
			failures.append("缺少 DOCX 杂念文案：%s" % expected)
	for phrase in seen:
		if phrase not in EXPECTED_PHRASES:
			failures.append("混入 DOCX 之外的杂念文案：%s" % phrase)


func _detector_samples() -> Array:
	return [
		[Vector2(640, 360), true, 0.00],
		[Vector2(640, 360), true, 0.06],
		[Vector2(640, 360), true, 0.13],
		[Vector2(720, 360), true, 0.20],
		[Vector2(800, 360), true, 0.26],
		[Vector2(500, 360), true, 0.32],
		[Vector2(380, 360), true, 0.38],
		[Vector2(700, 360), true, 0.44],
	]


func _on_finished(result: Variant) -> void:
	_finished_count += 1
	_result = result if result is Dictionary else {"result": str(result)}
