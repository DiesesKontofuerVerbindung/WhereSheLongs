extends Node

## ESC 暂停菜单的结构与开关测试。
##
## 重点不在好不好看，在两件会把游戏卡死的事：
##   1. 关闭之后 SceneTree.paused 必须回到 false（残留 true 会让整个游戏停住）；
##   2. 暂停期间菜单自己必须还能收到 ESC（宿主章节被暂停后 _input 不再被调用，
##      兜不住这一下就会「进得去出不来」）。

const PauseMenuScript := preload("res://scripts/pause_menu.gd")

const ChapterIndexScript := preload("res://scripts/chapter_index.gd")

const EXPECTED_LABELS := ["场景回溯", "返回游戏", "选项", "返回主页面", "退出游戏"]
const ESC_DEADLINE := 4.0


func _ready() -> void:
	var failures := PackedStringArray()
	await _verify_contract_and_toggle(failures)
	await _verify_escape_closes(failures)
	await _verify_rollback_pane(failures)

	# 无论成败都不能把暂停状态留给下一个使用者。
	get_tree().paused = false

	if failures.is_empty():
		print("PAUSE_MENU_PASS labels=%s options_placeholder=true pause_on_open=true unpause_on_close=true escape_closes=true rollback_slide=true locked_shown_as_question_marks=true font=project" % "/".join(EXPECTED_LABELS))
		get_tree().quit(0)
		return
	for failure in failures:
		print("PAUSE_MENU_FAIL %s" % failure)
	get_tree().quit(1)


func _wait_until(predicate: Callable, deadline_seconds: float) -> bool:
	var end_ms := Time.get_ticks_msec() + int(deadline_seconds * 1000.0)
	while Time.get_ticks_msec() < end_ms:
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return bool(predicate.call())


func _verify_contract_and_toggle(failures: PackedStringArray) -> void:
	var menu := PauseMenuScript.new()
	add_child(menu)
	await get_tree().process_frame

	if not menu.verify_contract():
		failures.append("菜单结构契约不完整（层级/文案/字体/占位状态）")
	var labels: PackedStringArray = menu.get_menu_labels()
	if Array(labels) != EXPECTED_LABELS:
		failures.append("菜单项与顺序不符：%s" % str(labels))
	if menu.is_open():
		failures.append("菜单初始状态不该是打开的")
	if get_tree().paused:
		failures.append("菜单挂上去就把游戏暂停了")

	menu.open()
	await get_tree().process_frame
	if not menu.is_open():
		failures.append("open() 之后状态没有变成打开")
	if not get_tree().paused:
		failures.append("打开菜单没有暂停 SceneTree，玩法模块会继续跑")

	menu.close()
	await get_tree().process_frame
	if menu.is_open():
		failures.append("close() 之后状态没有变成关闭")
	if get_tree().paused:
		failures.append("关闭菜单没有解除暂停，整个游戏会卡死")

	menu.queue_free()
	await get_tree().process_frame


func _verify_escape_closes(failures: PackedStringArray) -> void:
	var menu := PauseMenuScript.new()
	add_child(menu)
	await get_tree().process_frame

	menu.open()
	await get_tree().process_frame
	if not menu.is_open():
		failures.append("ESC 用例的前置打开失败")
		menu.queue_free()
		return

	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)

	var closed := await _wait_until(func() -> bool: return not bool(menu.is_open()), ESC_DEADLINE)
	if not closed:
		failures.append("暂停期间按 ESC 没能在 %.1fs 内关闭菜单，会出现进得去出不来" % ESC_DEADLINE)
	if get_tree().paused:
		failures.append("ESC 关闭后暂停状态没有解除")

	menu.queue_free()
	await get_tree().process_frame


## 回溯面板：锁定态、滑动终点、ESC 逐层退。
func _verify_rollback_pane(failures: PackedStringArray) -> void:
	var menu := PauseMenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	menu.setup("forest")

	# 只解锁森林的头两个节点，其余必须是 ???。
	var forest_nodes := ChapterIndexScript.nodes_of("forest")
	if forest_nodes.size() < 3:
		failures.append("森林节点太少，无法验证锁定态")
		menu.queue_free()
		return
	ChapterProgress.debug_seed({"forest": [int(forest_nodes[0]["source"]), int(forest_nodes[1]["source"])]})

	menu.open()
	await get_tree().process_frame
	if menu.get_menu_anchors() != menu.MENU_ANCHOR_CENTER:
		failures.append("回溯未打开时菜单不在居中位：%s" % str(menu.get_menu_anchors()))
	if menu.is_rollback_open():
		failures.append("菜单刚打开时回溯面板不该是展开的")

	menu.debug_open_rollback()
	await get_tree().process_frame
	if not menu.is_rollback_open():
		failures.append("点击场景回溯后状态没有切换")
	if menu.get_menu_anchors() != menu.MENU_ANCHOR_LEFT:
		failures.append("回溯展开后菜单没有左移：%s" % str(menu.get_menu_anchors()))
	if menu.get_rollback_anchors() != menu.ROLLBACK_ANCHOR_ON:
		failures.append("回溯列表没有滑到位：%s" % str(menu.get_rollback_anchors()))

	var entries: Array[Dictionary] = menu.get_rollback_entries()
	var total := ChapterIndexScript.total_node_count()
	# get_rollback_entries 只数滚动列表里的节点；「返回」按钮在列表外面，不计入。
	if entries.size() != total:
		failures.append("回溯节点数不对：%d，应为 %d" % [entries.size(), total])
	var unlocked := 0
	var locked := 0
	for entry in entries:
		if bool(entry["enabled"]):
			unlocked += 1
			if str(entry["text"]) == "???":
				failures.append("可点的节点显示成了 ???")
		else:
			locked += 1
			if str(entry["text"]) != "???":
				failures.append("未解锁节点没有隐藏成 ???：%s" % str(entry["text"]))
	if unlocked != 2:
		failures.append("可点节点数不是 2：%d" % unlocked)
	if locked != total - 2:
		failures.append("锁定节点数不对：%d，应为 %d" % [locked, total - 2])

	# ESC 要逐层退：先收回溯，再关菜单。
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	var collapsed := await _wait_until(func() -> bool: return not bool(menu.is_rollback_open()), ESC_DEADLINE)
	if not collapsed:
		failures.append("展开回溯后按 ESC 没有先收起列表")
	if not menu.is_open():
		failures.append("第一次 ESC 就把整个菜单关掉了，应该只收回溯")

	menu.close()
	await get_tree().process_frame
	if get_tree().paused:
		failures.append("回溯用例结束后暂停状态没有解除")

	ChapterProgress.debug_seed({})
	menu.queue_free()
	await get_tree().process_frame
