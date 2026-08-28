extends Node

## BlinkInteraction 模块定向测试。
##
## 覆盖：模块契约、单次 finished、闭眼/睁眼节奏、光敏安全、高清宿主分辨率适配、
## 重复输入保护，以及完成 payload 内容。
##
## 分辨率用例模拟主流程的 EmbeddedModuleHost：SubViewport 实际渲染尺寸随输出
## 分辨率变化，逻辑坐标始终固定为 1280x720（size_2d_override）。

const BlinkScene := preload("res://modules/blink_interaction/blink_interaction.tscn")

const VIEW_SIZE := Vector2(1280, 720)
const RESOLUTION_CASES := [
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

var _finished_count := 0
var _result: Dictionary = {}


func _ready() -> void:
	var failures := PackedStringArray()
	await _verify_main_flow(failures)
	await _verify_repeat_input(failures)
	await _verify_resolutions(failures)

	if failures.is_empty():
		print("BLINK_INTERACTION_MODULE_PASS source=360 finished_once=true blinks=1 resolution_cases=%d logical_viewport=1280x720 layout_relative=true flicker_safe=true" % RESOLUTION_CASES.size())
		get_tree().quit(0)
		return
	for failure in failures:
		print("BLINK_INTERACTION_MODULE_FAIL %s" % failure)
	get_tree().quit(1)


func _make_hosted_module(render_size: Vector2i) -> Control:
	var viewport := SubViewport.new()
	viewport.size = render_size
	viewport.size_2d_override = VIEW_SIZE
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = true
	add_child(viewport)

	var module: Control = BlinkScene.instantiate()
	module.setup({"source": 360, "id": "BlinkInteraction"})
	viewport.add_child(module)
	return module


func _release_module(module: Control) -> void:
	if module == null:
		return
	var viewport := module.get_parent()
	module.queue_free()
	await get_tree().process_frame
	if viewport != null:
		viewport.queue_free()
		await get_tree().process_frame


func _verify_main_flow(failures: PackedStringArray) -> void:
	var module := _make_hosted_module(Vector2i(2560, 1440))
	await get_tree().process_frame
	await get_tree().process_frame

	if not module.verify_contract():
		failures.append("初始布局或时序契约不完整")
	if not module.is_control_layout_ready():
		failures.append("根节点未铺满模块逻辑视口：%s" % module.size)
	if module.get_phase_name() != "ENTER":
		failures.append("进入时未从双手紧握的入场阶段开始：%s" % module.get_phase_name())
	if module.get_grip() <= 0.5:
		failures.append("入场阶段双手没有握在一起")
	if module.is_finished():
		failures.append("进入后立即发射了完成信号")

	var timing: Dictionary = module.get_timing_profile()
	if float(timing.get("close", 0.0)) < 0.25 or float(timing.get("close", 0.0)) > 0.5:
		failures.append("闭眼时长不在 0.25–0.5 秒安全区间：%s" % timing.get("close"))
	if float(timing.get("open", 0.0)) < 0.25 or float(timing.get("open", 0.0)) > 0.5:
		failures.append("睁眼时长不在 0.25–0.5 秒安全区间：%s" % timing.get("open"))
	if float(timing.get("min_dark_hold", 0.0)) <= 0.0:
		failures.append("闭眼后缺少最短停顿，会形成闪烁")
	if int(timing.get("required_blinks", 0)) != 1:
		failures.append("需要完成的眨眼次数不是 1")

	module.finished.connect(_on_finished)
	await get_tree().create_timer(0.6).timeout
	if module.get_phase_name() != "IDLE":
		failures.append("入场结束后未进入等待输入阶段：%s" % module.get_phase_name())
	if not module.debug_begin_close():
		failures.append("模块在 IDLE 阶段拒绝了闭眼输入")

	await get_tree().process_frame
	if module.get_phase_name() != "CLOSING":
		failures.append("闭眼输入未进入闭眼动画：%s" % module.get_phase_name())

	await _wait_until_phase(module, "CLOSED", 2.0)
	if module.get_phase_name() != "CLOSED":
		failures.append("未进入完全闭眼阶段：%s" % module.get_phase_name())
	if module.get_blink_count() != 1:
		failures.append("闭眼次数统计错误：%d/1" % module.get_blink_count())
	if module.get_close_progress() < 0.99:
		failures.append("闭眼遮罩未完整闭合：%.3f" % module.get_close_progress())
	if not module.is_eyes_closed():
		failures.append("闭眼状态标记缺失")
	if _finished_count != 0:
		failures.append("闭眼阶段就提前结束了模块")

	if not module.debug_release_close():
		failures.append("闭眼阶段无法松开")
	await _wait_until_phase(module, "DONE", 3.0)

	if _finished_count != 1:
		failures.append("finished 发射次数异常：%d/1" % _finished_count)
	if str(_result.get("result", "")) != "success":
		failures.append("完成结果不是 success")
	if int(_result.get("blinks", 0)) != 1:
		failures.append("完成结果未记录一次眨眼：%s" % _result.get("blinks"))
	if int(_result.get("source", 0)) != 360:
		failures.append("完成结果未保留 DOCX 来源行：%s" % _result.get("source"))
	if _result.has("text") or _result.has("answer"):
		failures.append("完成结果泄露了剧情文本")
	if not module.is_finished():
		failures.append("模块完成状态未标记")

	await _release_module(module)


func _verify_repeat_input(failures: PackedStringArray) -> void:
	var module := _make_hosted_module(Vector2i(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout

	_finished_count = 0
	_result = {}
	module.finished.connect(_on_finished)

	module.debug_begin_close()
	await _wait_until_phase(module, "CLOSED", 2.0)
	# 快速重复输入：闭眼中反复触发不应重复计数或提前结束。
	for i in range(6):
		module.debug_begin_close()
		module.debug_release_close()
	if module.get_blink_count() != 1:
		failures.append("重复输入造成眨眼计数漂移：%d/1" % module.get_blink_count())
	if _finished_count != 0:
		failures.append("重复输入造成提前结束")

	module.debug_release_close()
	await _wait_until_phase(module, "DONE", 3.0)
	if _finished_count != 1:
		failures.append("重复输入后 finished 发射次数异常：%d/1" % _finished_count)

	# 完成后的继续输入必须被忽略。
	module.debug_begin_close()
	module.debug_release_close()
	await get_tree().create_timer(0.4).timeout
	if _finished_count != 1:
		failures.append("完成后仍可再次发射 finished：%d" % _finished_count)

	await _release_module(module)


func _verify_resolutions(failures: PackedStringArray) -> void:
	for render_size in RESOLUTION_CASES:
		var module := _make_hosted_module(render_size)
		await get_tree().process_frame
		await get_tree().process_frame
		var root_rect := Rect2(Vector2.ZERO, module.size)
		var lid_rect: Rect2 = module.get_lid_rect()
		var world_rect: Rect2 = module.get_world_rect()
		var prompt_rect: Rect2 = module.get_prompt_rect()
		var hint_rect: Rect2 = module.get_hint_rect()
		if not root_rect.size.is_equal_approx(Vector2(VIEW_SIZE)):
			failures.append("%s 模块未使用 1280x720 逻辑坐标：%s" % [render_size, root_rect.size])
		if not lid_rect.size.is_equal_approx(Vector2(VIEW_SIZE)):
			failures.append("%s 遮罩未铺满模块画面：%s" % [render_size, lid_rect.size])
		if not world_rect.size.is_equal_approx(Vector2(VIEW_SIZE)):
			failures.append("%s 舞台未铺满模块画面：%s" % [render_size, world_rect.size])
		if prompt_rect.size.x > VIEW_SIZE.x or prompt_rect.position.x < -0.5:
			failures.append("%s 提示文字超出模块画面：%s" % [render_size, prompt_rect])
		if hint_rect.size.x > VIEW_SIZE.x or hint_rect.position.x < -0.5:
			failures.append("%s 底部提示超出模块画面：%s" % [render_size, hint_rect])
		if prompt_rect.size.x <= 0.0 or hint_rect.size.x <= 0.0:
			failures.append("%s 文字区域尺寸异常：%s / %s" % [render_size, prompt_rect.size, hint_rect.size])
		var prompt_center := prompt_rect.position.x + prompt_rect.size.x * 0.5
		if absf(prompt_center - VIEW_SIZE.x * 0.5) > 1.0:
			failures.append("%s 提示文字未居中：%.2f" % [render_size, prompt_center])
		var hint_center := hint_rect.position.x + hint_rect.size.x * 0.5
		if absf(hint_center - VIEW_SIZE.x * 0.5) > 1.0:
			failures.append("%s 底部提示未居中：%.2f" % [render_size, hint_center])
		if lid_rect.position.length() > 0.5 or world_rect.position.length() > 0.5:
			failures.append("%s 遮罩或舞台出现偏移：%s / %s" % [render_size, lid_rect.position, world_rect.position])

		# 闭眼过程中遮罩仍需完整覆盖，且随逻辑坐标同步。
		module.debug_begin_close()
		await _wait_until_phase(module, "CLOSED", 2.0)
		var closed_lid: Rect2 = module.get_lid_rect()
		if not closed_lid.size.is_equal_approx(Vector2(VIEW_SIZE)):
			failures.append("%s 闭眼时遮罩覆盖不完整：%s" % [render_size, closed_lid.size])
		if module.get_close_progress() < 0.99:
			failures.append("%s 闭眼遮罩未闭合：%.3f" % [render_size, module.get_close_progress()])

		await _release_module(module)


func _wait_until_phase(module: Object, phase_name: String, timeout: float) -> void:
	var elapsed := 0.0
	while elapsed < timeout:
		if str(module.call("get_phase_name")) == phase_name:
			return
		await get_tree().process_frame
		elapsed += 1.0 / 60.0


func _on_finished(result: Variant) -> void:
	_finished_count += 1
	_result = result if result is Dictionary else {"result": str(result)}
