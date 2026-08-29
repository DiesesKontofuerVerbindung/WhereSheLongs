extends Node

const HandInspectScene := preload("res://levels/minigames/hand_inspect.tscn")

const EXPECTED_IDS := ["ring", "palm_lines", "scar"]
# 界面实际展示的中文标题与细节文本（与模块内 SPOT_TITLES / SPOT_DETAIL 一致）
const EXPECTED_TITLES := {
	"ring": "戒指",
	"palm_lines": "掌纹",
	"scar": "伤疤",
}
const EXPECTED_DETAILS := {
	"ring": "一枚旧戒指，内壁刻着早已磨平的字母。",
	"palm_lines": "掌纹交叠如旧路，有一道分叉偏离了所有人。",
	"scar": "腕间一道浅疤，形状像被谁轻轻攥过。",
}
const EXPECTED_SOURCE := 353
const EXPECTED_SPOT_COUNT := 3

var _finished_count := 0
var _result: Dictionary = {}


func _ready() -> void:
	var failures := PackedStringArray()

	var module = HandInspectScene.instantiate()
	module.setup({"source": EXPECTED_SOURCE})
	add_child(module)
	await get_tree().process_frame
	await get_tree().process_frame

	if not module.verify_contract():
		failures.append("初始契约不完整 verify_contract 返回 false")
	module.finished.connect(_on_finished)

	# 完成入口必须存在（此前缺失导致真实玩法卡死）
	var button := module.get_node_or_null("FinishButton") as Button
	if button == null:
		failures.append("缺少 FinishButton 完成入口")
	var detail := module.get_node_or_null("DetailLabel") as Label
	if detail == null:
		failures.append("缺少 DetailLabel 细节反馈区域")

	# 0/3 时完成按钮必须禁用
	if button != null and not button.disabled:
		failures.append("0/3 时 FinishButton 应为禁用")

	# 通过真实 GUI 点击路径查看前两个热点，验证去重后仍不能完成
	for i in range(2):
		var early_id: String = EXPECTED_IDS[i]
		await _click_hotspot(module, early_id, failures)
		if module.get_inspect_count() != i + 1:
			failures.append("热点 %s 首次点击后计数应为 %d：%d" % [early_id, i + 1, module.get_inspect_count()])
		# 重复点击不应重复计数
		await _click_hotspot(module, early_id, failures)
		if module.get_inspect_count() != i + 1:
			failures.append("热点 %s 重复点击不应增加计数：%d" % [early_id, module.get_inspect_count()])
	if module.get_inspect_count() != 2:
		failures.append("检查两个热点后计数应为 2：%d" % module.get_inspect_count())

	# 每次查看必须显示对应细节文本
	_verify_detail_text(detail, failures, 2)

	# 2/3 时完成按钮仍必须禁用
	if button != null and not button.disabled:
		failures.append("2/3 时 FinishButton 应为禁用")

	# 提前无法完成
	if module.request_finish():
		failures.append("仅检查 2/3 时 request_finish 不应返回 true")
	if module.can_finish():
		failures.append("仅检查 2/3 时 can_finish 不应为 true")
	if module.is_complete():
		failures.append("仅检查 2/3 时 is_complete 不应为 true")
	if _finished_count != 0:
		failures.append("提前完成导致 finished 发射次数异常：%d/0" % _finished_count)

	# 通过真实 GUI 点击第三个热点
	await _click_hotspot(module, EXPECTED_IDS[2], failures)
	if module.get_inspect_count() != EXPECTED_SPOT_COUNT:
		failures.append("检查计数应为 %d：%d" % [EXPECTED_SPOT_COUNT, module.get_inspect_count()])

	# 全部三个热点的去重与列表完整性（此时已全部检查过）
	_verify_click_sequence(module, failures)

	# 三个都看过之后细节文本应全部出现
	_verify_detail_text(detail, failures, EXPECTED_SPOT_COUNT)

	if not module.is_complete():
		failures.append("三个热点全部检查后 is_complete 应为 true")
	if not module.can_finish():
		failures.append("三个热点全部检查后 can_finish 应为 true")

	# 3/3 时完成按钮必须启用
	if button != null and button.disabled:
		failures.append("3/3 时 FinishButton 应为启用，当前仍禁用")

	# 恰好发射一次：必须走真实按钮路径，而不是直接调内部方法
	if button == null:
		failures.append("无法通过 FinishButton 完成：节点缺失")
	elif not await _press_finish_button(button, module, failures):
		failures.append("FinishButton 按下后未进入完成流程")
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished_count != 1:
		failures.append("finished 发射次数异常：%d/1" % _finished_count)

	if module.request_finish():
		failures.append("完成后再次 request_finish 不应返回 true")
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished_count != 1:
		failures.append("完成后二次 request_finish 不应再次发射 finished：%d" % _finished_count)

	# 完成后再检查应为 no-op
	var count_after: int = module.get_inspect_count()
	if module.inspect_spot(EXPECTED_IDS[0]):
		failures.append("完成后再检查热点应返回 false")
	if module.get_inspect_count() != count_after:
		failures.append("完成后再检查不应改变检查计数")

	# 载荷形状
	_verify_payload(module, failures)

	# 三分辨率布局一致性（独立实例，不干扰点击序列）
	# 必须 await：该函数内部有 await，不等待会直接落到下面的失败判定并提前退出。
	await _verify_layout_across_resolutions(failures)

	if failures.is_empty():
		print("HAND_INSPECT_PASS source=%d spots=%d finish_once=true layout_stable=true" % [EXPECTED_SOURCE, EXPECTED_SPOT_COUNT])
		get_tree().quit(0)
		return
	for failure in failures:
		print("HAND_INSPECT_FAIL %s" % failure)
	get_tree().quit(1)


func _click_hotspot(module: Node, spot_id: String, failures: PackedStringArray) -> void:
	## 通过真实 gui_input 路径点击热点，模拟玩家鼠标左键按下再松开。
	var node := module.get_node_or_null("Hotspot_" + spot_id) as Control
	if node == null:
		failures.append("缺少热点节点 Hotspot_%s" % spot_id)
		return
	var center := node.get_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	press.global_position = center
	node.gui_input.emit(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = center
	release.global_position = center
	node.gui_input.emit(release)
	await get_tree().process_frame


func _press_finish_button(button: Button, module: Node, failures: PackedStringArray) -> bool:
	## 触发真实按钮 pressed 路径，并等待 finished 信号。
	if button.disabled:
		failures.append("FinishButton 处于禁用状态，无法完成")
		return false
	button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	if _finished_count != 1:
		failures.append("通过 FinishButton 完成后 finished 应恰好发射 1 次：%d" % _finished_count)
		return false
	if not bool(module.get_inspect_count() == EXPECTED_SPOT_COUNT):
		failures.append("完成后检查计数异常")
		return false
	return true


func _verify_detail_text(detail: Label, failures: PackedStringArray, expected_count: int) -> void:
	## 每查看一个热点，必须显示对应标题与细节文本。
	## 界面显示的是中文标题与描述（如【戒指】…），不是内部 id，因此按标题校验。
	if detail == null:
		return
	var text: String = detail.text
	for i in range(expected_count):
		var spot_id: String = EXPECTED_IDS[i]
		var title: String = EXPECTED_TITLES[spot_id]
		if not text.contains(title):
			failures.append("细节反馈未包含已查看热点 %s 的标题「%s」" % [spot_id, title])
		var detail_text: String = EXPECTED_DETAILS[spot_id]
		if not text.contains(detail_text):
			failures.append("细节反馈未包含热点 %s 的细节文本" % spot_id)
	# 未查看的热点不应提前出现
	for i2 in range(EXPECTED_IDS.size()):
		if i2 < expected_count:
			continue
		var later_id: String = EXPECTED_IDS[i2]
		if text.contains(EXPECTED_TITLES[later_id]):
			failures.append("细节反馈提前显示了尚未查看的热点 %s" % later_id)
	if expected_count == 0 and text.is_empty():
		failures.append("未查看前应显示中性提示文案")


func _verify_click_sequence(module: Node, failures: PackedStringArray) -> void:
	# 调用时机：三个热点均已被检查过，此处只验证去重与列表完整性。
	for id in EXPECTED_IDS:
		var spot_id: String = id
		if module.inspect_spot(spot_id):
			failures.append("热点 %s 重复检查不应返回 true（重复计数）" % spot_id)
		if module.get_inspect_count() != (module.get_inspected_ids().size()):
			failures.append("检查计数与已检查列表长度不一致")
	var inspected: PackedStringArray = module.get_inspected_ids()
	if inspected.size() != EXPECTED_SPOT_COUNT:
		failures.append("已检查列表长度应为 %d：%d" % [EXPECTED_SPOT_COUNT, inspected.size()])
	for id in EXPECTED_IDS:
		if id not in inspected:
			failures.append("已检查列表缺少热点 %s" % id)


func _verify_payload(module: Node, failures: PackedStringArray) -> void:
	if str(_result.get("result", "")) != "success":
		failures.append("完成结果 result 不是 success：%s" % str(_result.get("result", "")))
	var inspected = _result.get("inspected", [])
	if not (inspected is Array):
		failures.append("完成结果 inspected 应为数组")
	else:
		if inspected.size() != EXPECTED_SPOT_COUNT:
			failures.append("完成结果 inspected 长度应为 %d：%d" % [EXPECTED_SPOT_COUNT, inspected.size()])
		for id in EXPECTED_IDS:
			if id not in inspected:
				failures.append("完成结果 inspected 缺少 %s" % id)
		for item in inspected:
			if str(item) not in EXPECTED_IDS:
				failures.append("完成结果 inspected 混入意外项：%s" % str(item))
	if int(_result.get("source", 0)) != EXPECTED_SOURCE:
		failures.append("完成结果 source 应为 %d：%d" % [EXPECTED_SOURCE, int(_result.get("source", 0))])
	if int(_result.get("spot_count", 0)) != EXPECTED_SPOT_COUNT:
		failures.append("完成结果 spot_count 应为 %d：%d" % [EXPECTED_SPOT_COUNT, int(_result.get("spot_count", 0))])
	# 不应泄露纹理/资源对象
	for key in _result.keys():
		var value = _result[key]
		if value is Resource or value is Texture2D or value is Object:
			failures.append("完成结果泄露非预期对象字段 %s" % key)


func _verify_layout_across_resolutions(failures: PackedStringArray) -> void:
	var resolutions := [Vector2(1280, 720), Vector2(1920, 1080), Vector2(2560, 1440)]
	# 每个热点在各分辨率下的归一化矩形，用于真正的“跨分辨率”比较。
	var per_spot: Dictionary = {}
	for res in resolutions:
		var inst = HandInspectScene.instantiate()
		inst.setup({"source": EXPECTED_SOURCE})
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame

		inst.size = res
		inst.resized.emit()
		await get_tree().process_frame
		await get_tree().process_frame

		if (inst.size - res).length() >= 1.0:
			failures.append("分辨率未生效，实际尺寸 %s / 期望 %s" % [str(inst.size), str(res)])

		var rects: Dictionary = inst.get_hotspot_rects()
		for id in EXPECTED_IDS:
			var spot_id: String = id
			if not rects.has(spot_id):
				failures.append("分辨率 %s 缺少热点矩形 %s" % [str(res), spot_id])
				continue
			var r: Rect2 = rects[spot_id]
			if r.size.x <= 0.0 or r.size.y <= 0.0:
				failures.append("分辨率 %s 热点 %s 矩形退化（非正宽高）" % [str(res), spot_id])
				continue
			var bounds := Rect2(Vector2.ZERO, res)
			if not bounds.encloses(r):
				failures.append("分辨率 %s 热点 %s 矩形超出边界" % [str(res), spot_id])
				continue

			# 点击区域必须与实际绘制的热点区域重合（验收 4）
			var click_node := inst.get_node_or_null("Hotspot_" + spot_id) as Control
			if click_node == null:
				failures.append("分辨率 %s 热点 %s 缺少可点击节点" % [str(res), spot_id])
				continue
			var click_rect := click_node.get_rect()
			if not _nearly_equal_rect(click_rect, r, 1.0):
				failures.append("分辨率 %s 热点 %s 点击区域与热点区域不一致：%s vs %s" % [str(res), spot_id, str(click_rect), str(r)])
				continue
			if click_node.mouse_filter != Control.MOUSE_FILTER_STOP:
				failures.append("分辨率 %s 热点 %s 点击区域未接收输入" % [str(res), spot_id])
				continue

			if not per_spot.has(spot_id):
				per_spot[spot_id] = []
			var samples: Array = per_spot[spot_id]
			samples.append(Rect2(r.position / res, r.size / res))
			per_spot[spot_id] = samples

		inst.queue_free()
		await get_tree().process_frame

	# 同一热点在三种分辨率下的归一化矩形必须一致（无漂移）
	for id in EXPECTED_IDS:
		var spot_id2: String = id
		if not per_spot.has(spot_id2):
			failures.append("热点 %s 未采集到任何分辨率样本" % spot_id2)
			continue
		var samples2: Array = per_spot[spot_id2]
		if samples2.size() != resolutions.size():
			failures.append("热点 %s 样本数应为 %d：%d" % [spot_id2, resolutions.size(), samples2.size()])
			continue
		var first: Rect2 = samples2[0]
		for i in range(1, samples2.size()):
			var other: Rect2 = samples2[i]
			if not _nearly_equal_rect(first, other, 1e-3):
				failures.append("热点 %s 归一化布局跨分辨率漂移：%s vs %s" % [spot_id2, str(first), str(other)])


func _nearly_equal_rect(a: Rect2, b: Rect2, tol: float) -> bool:
	return abs(a.position.x - b.position.x) <= tol \
		and abs(a.position.y - b.position.y) <= tol \
		and abs(a.size.x - b.size.x) <= tol \
		and abs(a.size.y - b.size.y) <= tol


func _on_finished(result: Variant) -> void:
	_finished_count += 1
	_result = result if result is Dictionary else {"result": str(result)}
