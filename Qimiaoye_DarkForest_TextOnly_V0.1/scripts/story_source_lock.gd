class_name DarkForestStorySourceLock
extends RefCounted

## Stable developer-jump anchors frozen after baseline commit 53ba079.
## New visible beats may share an existing source number, but must not renumber
## the original DOCX coordinate system.

const VISIBLE_LINES_BY_SOURCE := {
	105: [
		{"speaker": "旁白", "text": "阿麦指了指右边。"},
		{"speaker": "阿麦", "text": "那边有瀑布。"},
	],
	127: [
		{"speaker": "旁白", "text": "阿麦回头。"},
		{"speaker": "阿麦", "text": "你怕吗？"},
	],
	140: [
		{"speaker": "旁白", "text": "阿麦接住了小凌。\n小凌看到他心脏中闪烁的光，如同自己的呼吸一般。小凌忍不住触摸那束光，光线散出一团光丝缠绕着小凌的手。"},
	],
	144: [
		{"speaker": "旁白", "text": "阿麦向上看着刚才跳下来的瀑布顶端。"},
	],
	151: [
		{"speaker": "旁白", "text": "阿麦低头看着水里的自己。"},
		{"speaker": "阿麦", "text": "所以你对自己可以不用这么严格。"},
	],
	153: [
		{"speaker": "旁白", "text": "阿麦抬起头看着小凌。"},
		{"speaker": "阿麦", "text": "想做什么就做什么。"},
	],
	158: [
		{"speaker": "旁白", "text": "阿麦拉起小凌的手。"},
		{"speaker": "阿麦", "text": "那就只做你最想做的那件事"},
	],
	179: [
		{"speaker": "旁白", "text": "阿麦站在水中央，张开双臂。"},
		{"speaker": "阿麦", "text": "你不想试试吗？"},
	],
	218: [
		{"speaker": "女孩", "text": "（皱眉）"},
		{"speaker": "女孩", "text": "（递外套）"},
		{"speaker": "女孩", "text": "冷吗？"},
	],
	223: [
		{"speaker": "旁白", "text": "女孩把外套披在你身上。"},
		{"speaker": "旁白", "text": "两个人并排坐在湖边。谁也没有说话。"},
	],
	232: [
		{"speaker": "小凌", "text": "（低头看向湖面）"},
		{"speaker": "女孩", "text": "你刚才为什么跳下去？"},
	],
	236: [
		{"speaker": "小凌", "text": "（摇头）"},
		{"speaker": "女孩", "text": "那是因为你自己想跳？"},
	],
	249: [
		{"speaker": "小凌", "text": "（没有说话，把膝盖抱在怀里）"},
		{"speaker": "小凌", "text": "你怎么知道？"},
	],
	252: [
		{"speaker": "女孩", "text": "（笑）因为我也这样"},
	],
	254: [
		{"speaker": "小凌", "text": "（转头看向女孩）"},
		{"speaker": "女孩", "text": "（看着湖面）有一段时间，我特讨厌别人问我“以后想干什么”。"},
	],
	278: [
		{"speaker": "女孩", "text": "（笑）我不敢。"},
	],
	290: [
		{"speaker": "旁白", "text": "女孩深深地看着小凌。"},
		{"speaker": "女孩", "text": "因为有一些东西，我还是舍不得。"},
	],
	319: [
		{"speaker": "女孩", "text": "（轻轻说）有时候"},
	],
	326: [
		{"speaker": "小凌", "text": "（慢慢把头靠在女孩肩膀上）"},
		{"speaker": "女孩", "text": "（身体僵了一下，却没有躲开）"},
		{"speaker": "旁白", "text": "过了一会儿，她轻轻靠在小凌头上。"},
		{"speaker": "女孩", "text": "其实我觉得……"},
	],
	340: [
		{"speaker": "女孩", "text": "（看着湖面）"},
		{"speaker": "女孩", "text": "我啊……"},
	],
	351: [],
	355: [
		{"speaker": "女孩", "text": "（笑）可能吧"},
	],
}

const REQUIRED_NON_LINE_EVENTS := {
	51: {"type": "interaction", "id": "light_hover"},
	52: {"type": "action", "id": "light_trigger"},
	64: {"type": "action", "id": "amai_walk_waypoint"},
	118: {"type": "action", "id": "amai_run_entry"},
	121: {"type": "movement", "id": "forest_run_entry"},
	122: {"type": "module", "id": "ForestRun"},
	351: {"type": "action", "id": "hand_inspect_prepare"},
}


static func validate(events: Array[Dictionary]) -> PackedStringArray:
	var errors := PackedStringArray()
	for source_key in VISIBLE_LINES_BY_SOURCE:
		var source := int(source_key)
		var source_events: Array[Dictionary] = []
		var visible_lines: Array[Dictionary] = []
		for event in events:
			if int(event.get("source", 0)) != source:
				continue
			source_events.append(event)
			if str(event.get("type", "")) == "line":
				visible_lines.append({
					"speaker": str(event.get("speaker", "")),
					"text": str(event.get("text", "")),
				})
		if source_events.is_empty():
			errors.append("锁定的 DOCX 来源行缺失：%d" % source)
			continue
		var expected_lines: Array = VISIBLE_LINES_BY_SOURCE[source]
		if visible_lines.size() != expected_lines.size():
			errors.append("DOCX 第 %d 行可见事件数量漂移：%d/%d" % [source, visible_lines.size(), expected_lines.size()])
			continue
		for index in range(expected_lines.size()):
			var expected: Dictionary = expected_lines[index]
			var actual: Dictionary = visible_lines[index]
			if actual != expected:
				errors.append("DOCX 第 %d 行第 %d 个可见事件漂移：%s / %s" % [source, index + 1, actual, expected])

	for source_key in REQUIRED_NON_LINE_EVENTS:
		var source := int(source_key)
		var expected: Dictionary = REQUIRED_NON_LINE_EVENTS[source]
		var found := false
		for event in events:
			if (
				int(event.get("source", 0)) == source
				and str(event.get("type", "")) == str(expected.get("type", ""))
				and str(event.get("id", "")) == str(expected.get("id", ""))
			):
				found = true
				break
		if not found:
			errors.append("DOCX 第 %d 行缺少锁定事件：%s" % [source, expected])
	return errors
