extends Node

## 婚礼前段推进门控回归测试。
##
## 复现的缺陷：`_show_line()` 只 await 了 `present()`（入场动画播完就返回），
## 没有像森林正片那样 `set_advance_waiting(true)` + `await advance_requested`，
## 于是 124 条台词全部自动流过去，按 Enter 也没反应——`request_advance()` 会被
## `_waiting_for_advance == false` 直接挡回。
##
## 这里跑的是非 verify 模式（verify 模式本来就跳过等待），并且用真实的
## `push_input` 走一遍 `_unhandled_key_input`，把输入路由一起验掉。

const WeddingScene := preload("res://scenes/wedding/wedding_prologue.tscn")

const WAIT_FOR_GATE_SECONDS := 12.0
const HOLD_CHECK_SECONDS := 1.5
const WAIT_AFTER_INPUT_SECONDS := 6.0


func _ready() -> void:
	var failures: PackedStringArray = []
	var wedding := WeddingScene.instantiate()
	add_child(wedding)

	if bool(wedding._verify_mode):
		failures.append("测试必须跑在非 verify 模式，否则等待路径根本不会执行")

	# 1. 第一条台词必须停下来等玩家，而不是自己流走。
	if not await _wait_until(func() -> bool:
		return not str(wedding._active_line_channel).is_empty()
	, WAIT_FOR_GATE_SECONDS):
		failures.append("台词没有进入等待推进状态：旁白/对白仍然是自动播放")
		_report(failures)
		return

	var channel := str(wedding._active_line_channel)
	var gated_index := int(wedding._event_index)

	# 2. 等待期间提示必须可见，否则玩家不知道该按什么。
	if not bool(wedding._advance_hint.visible):
		failures.append("等待推进时“按 Enter / Space 继续”提示没有显示")

	# 3. 停住就要真的停住：不按键的话事件指针不能自己往前走。
	await _sleep(HOLD_CHECK_SECONDS)
	if int(wedding._event_index) != gated_index:
		failures.append("没有按键，事件指针从 %d 自己走到了 %d" % [
			gated_index, int(wedding._event_index)
		])
	if str(wedding._active_line_channel) != channel:
		failures.append("没有按键，台词通道从 %s 自己变成了 %s" % [
			channel, str(wedding._active_line_channel)
		])

	# 4. 按 Enter 必须推进。走 push_input 而不是直接调 request_advance()，
	#    这样 _unhandled_key_input 的通道路由也在测试范围内。
	_press_enter()
	if not await _wait_until(func() -> bool:
		return int(wedding._event_index) > gated_index
	, WAIT_AFTER_INPUT_SECONDS):
		failures.append("按下 Enter 之后事件指针停在 %d 没有推进" % gated_index)
		_report(failures)
		return

	# 5. 推进之后要么落到下一条台词的等待态，要么正在跑非台词事件；
	#    无论哪种，提示都不能停在“可以按 Enter”的假象上。
	var advanced_index := int(wedding._event_index)
	if str(wedding._active_line_channel).is_empty() and bool(wedding._advance_hint.visible):
		failures.append("不在等待台词时提示仍然亮着")

	print("WEDDING_ADVANCE_GATE_DEBUG channel=%s gated_index=%d advanced_index=%d" % [
		channel, gated_index, advanced_index
	])
	_report(failures)


func _press_enter() -> void:
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_ENTER
	key_event.physical_keycode = KEY_ENTER
	key_event.pressed = true
	get_viewport().push_input(key_event)
	var release := InputEventKey.new()
	release.keycode = KEY_ENTER
	release.physical_keycode = KEY_ENTER
	release.pressed = false
	get_viewport().push_input(release)


func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_seconds:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	return bool(predicate.call())


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _report(failures: PackedStringArray) -> void:
	if not failures.is_empty():
		for failure in failures:
			print("WEDDING_ADVANCE_GATE_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("WEDDING_ADVANCE_GATE_PASS narration_and_dialogue_gated=true enter_advances=true hint_follows_gate=true")
	get_tree().quit(0)
