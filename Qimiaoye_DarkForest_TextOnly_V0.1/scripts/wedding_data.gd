extends RefCounted
class_name WeddingData

## 婚礼前段剧本数据。
##
## source 是《开场直接是婚礼现场.docx》的段落行号，与森林正片的 DOCX 行号
## 各走各的坐标系——两份文档不是同一份，混编号只会让跳转定位失去意义。
##
## 婚礼段目前没有任何美术素材（Szene 与微信下载目录里只有森林、湖边、河流、
## 阿麦角色动画），所以场景一律走纯文字舞台占位，等背景图到位再替换。
## 结尾小凌闭眼，先接奇妙夜，再由奇妙夜黑屏进入森林正片 EYE_OPEN。

const SCENE_WEDDING_1 := "婚礼背景图1"
const SCENE_WEDDING_2 := "婚礼背景图2"
const SCENE_CAR := "车上背景图"
const SCENE_HOME := "家里场景"


static func build_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	events.append_array(_wedding_hall_events())
	events.append_array(_car_events())
	events.append_array(_home_events())
	return events


static func _wedding_hall_events() -> Array[Dictionary]:
	return [
		{"type": "scene", "source": 2, "name": SCENE_WEDDING_1},
		{"type": "audio", "source": 2, "action": "start", "channel": "bgm", "stream": "wedding_bgm_opening", "status": "开场婚礼主题 BGM 起"},
		{"type": "line", "source": 3, "speaker": "主持人", "text": "有人说，婚礼是两个人爱情的终点。"},
		{"type": "line", "source": 4, "speaker": "主持人", "text": "但我更愿意相信——"},
		{"type": "line", "source": 5, "speaker": "主持人", "text": "婚礼不是终点。"},
		{"type": "line", "source": 6, "speaker": "主持人", "text": "而是从今天开始，两个人决定把彼此放进自己未来的每一天。"},
		{"type": "line", "source": 7, "speaker": "主持人", "text": "从今天开始，你们不再只是彼此生命中的过客。"},
		{"type": "line", "source": 8, "speaker": "主持人", "text": "你们会成为对方最亲密的人。"},
		{"type": "line", "source": 9, "speaker": "主持人", "text": "一起分享快乐，也一起面对生活中的风雨。"},
		{"type": "line", "source": 10, "speaker": "主持人", "text": "当未来有一天回头看的时候，希望你们还能够记得——"},
		{"type": "line", "source": 11, "speaker": "主持人", "text": "今天为什么会选择站在这里。"},
		{"type": "line", "source": 12, "speaker": "主持人", "text": "那么接下来……"},
		{"type": "line", "source": 13, "speaker": "主持人", "text": "就请新郎，也对他即将共度一生的人，说出自己的心里话。"},
		{"type": "line", "source": 14, "speaker": "主持人", "text": "有请新郎——"},
		# 原文这里就是一个空拍，新郎没有出现。停顿本身是演出内容，不能省。
		{"type": "wait", "source": 15, "seconds": 2.5},
		{"type": "line", "source": 16, "speaker": "主持人", "text": "……"},
		{"type": "action", "source": 17, "id": "xiaoling_pull_veil", "status": "小凌一把抓下自己的头纱。"},
		{"type": "audio", "source": 17, "action": "start", "channel": "amb", "stream": "wedding_amb_rehearsal", "status": "婚礼彩排现实环境声起"},
		{"type": "line", "source": 17, "speaker": "小凌", "text": "他应该在忙，还没到。"},

		# 3–21 仍用司仪底图（婚礼背景图1）；誓词模块后再切婚礼背景图2。
		{"type": "line", "source": 19, "speaker": "主持人", "text": "那后面的流程还过吗？"},
		{"type": "line", "source": 20, "speaker": "小凌", "text": "我自己来吧。"},

		# 婚礼交互模块1：原文只写了模块名。按上下文补成"小凌独自把誓词念完"，
		# 让玩家亲手推完每一句——独角戏的空落感要玩家自己按出来。
		{
			"type": "module",
			"source": 21,
			"id": "WeddingVowSolo",
			"scene": "res://scenes/wedding/modules/wedding_vow_solo.tscn",
			"completion_signal": "finished",
			"result": "success",
		},

		# 群组 checklist 插件①：誓词后打勾（21–22 之间）。
		{
			"type": "module",
			"source": 21,
			"id": "WeddingChecklist1",
			"scene": "res://scenes/wedding/modules/wedding_checklist.tscn",
			"checklist_variant": "1",
			"completion_signal": "finished",
			"result": "success",
		},

		{"type": "scene", "source": 22, "name": SCENE_WEDDING_2},
		{"type": "audio", "source": 22, "action": "stop", "channel": "bgm", "fade": 6.0, "status": "开场婚礼主题 BGM 从22开始淡出至27"},
		{"type": "line", "source": 22, "speaker": "旁白", "text": "彩排快结束时，小凌的未婚夫思雨终于匆匆赶到。"},
		{"type": "line", "source": 23, "speaker": "思雨", "text": "抱歉，结束了吗？"},
		{"type": "line", "source": 24, "speaker": "小凌", "text": "差不多。"},
		{"type": "line", "source": 25, "speaker": "旁白", "text": "思雨看到小凌穿着婚纱。"},
		{"type": "line", "source": 26, "speaker": "思雨", "text": "挺好看的。"},
		{"type": "line", "source": 27, "speaker": "旁白", "text": "主持人把誓词卡交给思雨。"},
		{"type": "line", "source": 28, "speaker": "主持人", "text": "新郎来了，誓词要不要最后过一遍？"},
		{"type": "action", "source": 30, "id": "siyu_glance_vow_card", "status": "思雨看了眼誓词卡。"},
		{"type": "line", "source": 30, "speaker": "思雨", "text": "这个明天现场直接来就行吧？"},
		{"type": "action", "source": 31, "id": "xiaoling_sigh", "status": "小凌轻轻叹了口气。"},

		# 婚礼交互模块2：对应原文"手机屏幕上不断跳出新的消息"。
		# 玩家可以一条条划掉，但新的消息一直在来，划不完——划到最后是思雨抬头。
		{
			"type": "module",
			"source": 32,
			"id": "PhoneNotifications",
			"scene": "res://scenes/wedding/modules/phone_notifications.tscn",
			"completion_signal": "finished",
			"result": "success",
		},

		{"type": "line", "source": 33, "speaker": "旁白", "text": "思雨看了眼手机。"},
		{"type": "line", "source": 34, "speaker": "旁白", "text": "手机屏幕上不断跳出新的消息。"},
		{"type": "action", "source": 35, "id": "siyu_look_up", "status": "思雨抬起头。"},
		{"type": "line", "source": 35, "speaker": "思雨", "text": "那个……我可能得先走了。"},
		{"type": "line", "source": 36, "speaker": "小凌", "text": "现在？"},
		{"type": "line", "source": 37, "speaker": "思雨", "text": "嗯，今天我 on call，还要去公司修 bug。"},
		{"type": "line", "source": 38, "speaker": "小凌", "text": "可是彩排还没结束。"},
		{"type": "line", "source": 39, "speaker": "思雨", "text": "剩下的不是都差不多了吗？"},
		{"type": "line", "source": 40, "speaker": "小凌", "text": "还有时间。"},
		{"type": "line", "source": 41, "speaker": "思雨", "text": "这个你不是已经知道了吗？"},
		{"type": "line", "source": 42, "speaker": "小凌", "text": "……"},
		{"type": "line", "source": 43, "speaker": "思雨", "text": "明天我会准时到的。"},
		{"type": "line", "source": 44, "speaker": "旁白", "text": "思雨走过来，轻轻拍了一下她的肩膀。"},
		{"type": "line", "source": 45, "speaker": "思雨", "text": "别想太多，一会儿我先送你回家。"},

		# 群组 checklist 插件②：上车前再过一遍清单（46–47 之间）。
		{
			"type": "module",
			"source": 46,
			"id": "WeddingChecklist2",
			"scene": "res://scenes/wedding/modules/wedding_checklist.tscn",
			"checklist_variant": "2",
			"completion_signal": "finished",
			"result": "success",
		},
	]


static func _car_events() -> Array[Dictionary]:
	return [
		{"type": "scene", "source": 47, "name": SCENE_CAR},
		{"type": "audio", "source": 47, "action": "stop", "channel": "amb", "status": "彩排环境声淡出"},
		{"type": "audio", "source": 47, "action": "start", "channel": "bgm", "stream": "wedding_bgm_car", "status": "小凌车内未说出口 BGM 起"},
		{"type": "line", "source": 48, "speaker": "旁白", "text": "天已经有些暗了。"},
		{"type": "line", "source": 50, "speaker": "旁白", "text": "彩排结束。思雨开车，小凌坐在副驾驶的座位上。"},
		{"type": "line", "source": 51, "speaker": "旁白", "text": "晚高峰的街边车流不断，路边的人群也在涌向不同的方向。"},
		{"type": "line", "source": 52, "speaker": "旁白", "text": "红灯亮起，车停在人行道前。"},
		{"type": "line", "source": 53, "speaker": "旁白", "text": "思雨无聊地调着车里的广播频道。"},
		{"type": "line", "source": 54, "speaker": "小凌", "text": "你觉得今天怎么样？"},
		{"type": "line", "source": 55, "speaker": "思雨", "text": "什么？"},
		{"type": "line", "source": 56, "speaker": "小凌", "text": "彩排。"},
		{"type": "line", "source": 57, "speaker": "思雨", "text": "挺好的啊。"},
		{"type": "line", "source": 58, "speaker": "小凌", "text": "我是说……"},
		# 关广播是玩家的动作：把车里唯一的声音掐掉，才好开口问那句话。
		{
			"type": "interaction",
			"source": 59,
			"id": "xiaoling_turn_off_radio",
			"prompt": "关掉广播",
			"status": "小凌把广播关掉。",
		},
		{"type": "line", "source": 60, "speaker": "小凌", "text": "你有没有觉得哪里不太对？"},
		{"type": "action", "source": 61, "id": "siyu_finally_look_up", "status": "思雨终于抬头。"},
		{"type": "line", "source": 61, "speaker": "思雨", "text": "哪里？"},
		{"type": "line", "source": 62, "speaker": "小凌", "text": "……"},
		{"type": "action", "source": 63, "id": "xiaoling_shake_head", "status": "小凌摇摇头。"},
		{"type": "line", "source": 64, "speaker": "小凌", "text": "没什么。"},
		{"type": "line", "source": 65, "speaker": "旁白", "text": "绿灯亮起。"},
		{"type": "line", "source": 66, "speaker": "旁白", "text": "街边的人群开始向前涌。"},
		{"type": "line", "source": 67, "speaker": "旁白", "text": "思雨重新发动了车。"},
		{"type": "line", "source": 68, "speaker": "思雨", "text": "对了，明天早上八点化妆，千万别迟到。"},
		{"type": "line", "source": 69, "speaker": "小凌", "text": "嗯。"},
		{"type": "line", "source": 70, "speaker": "思雨", "text": "然后九点家里人过来，十点合影，十一点……"},
		{"type": "line", "source": 71, "speaker": "旁白", "text": "思雨一边开车，一边说着明天的流程。"},
		{"type": "line", "source": 72, "speaker": "旁白", "text": "小凌却没有再听。"},
		{"type": "line", "source": 73, "speaker": "旁白", "text": "她看着窗外路边的人。"},
		{"type": "line", "source": 74, "speaker": "旁白", "text": "所有的人都在往前走。"},
		{"type": "line", "source": 75, "speaker": "旁白", "text": "只有她好像不知道自己为什么要走。"},
		{"type": "line", "source": 76, "speaker": "小凌", "text": "你明天真的会准时吗？"},
		{"type": "line", "source": 77, "speaker": "思雨", "text": "当然。"},
		{"type": "line", "source": 78, "speaker": "小凌", "text": "……"},
		{"type": "line", "source": 79, "speaker": "思雨", "text": "怎么了？"},
		{"type": "line", "source": 80, "speaker": "小凌", "text": "没什么。"},
		{"type": "line", "source": 81, "speaker": "旁白", "text": "思雨看了她一会儿。"},
		{"type": "line", "source": 82, "speaker": "思雨", "text": "你是不是紧张？"},
		{"type": "line", "source": 83, "speaker": "小凌", "text": "可能吧。"},
		{"type": "line", "source": 84, "speaker": "思雨", "text": "很正常。"},
		{"type": "line", "source": 85, "speaker": "小凌", "text": "你不紧张吗？"},
		{"type": "line", "source": 86, "speaker": "思雨", "text": "我？"},
		{"type": "action", "source": 87, "id": "siyu_laugh", "status": "思雨笑了一下。"},
		{"type": "line", "source": 88, "speaker": "思雨", "text": "流程都准备好了，有什么好紧张的。"},
		{"type": "line", "source": 89, "speaker": "小凌", "text": "……"},
		{"type": "line", "source": 90, "speaker": "小凌", "text": "如果明天不结呢？"},
		{"type": "action", "source": 91, "id": "siyu_sudden_brake", "status": "思雨突然刹车。"},
		{"type": "line", "source": 91, "speaker": "思雨", "text": "什么？"},
		{"type": "line", "source": 92, "speaker": "旁白", "text": "又一个红灯，空气突然安静下来。"},
		{"type": "line", "source": 93, "speaker": "小凌", "text": "没什么。"},
		{"type": "line", "source": 94, "speaker": "思雨", "text": "你今天怎么怪怪的？"},
		{"type": "line", "source": 95, "speaker": "小凌", "text": "我哪里怪？"},
		{"type": "line", "source": 96, "speaker": "思雨", "text": "就是……"},
		{"type": "wait", "source": 97, "seconds": 2.5, "status": "按原文停留 2-3 秒。"},
		{"type": "line", "source": 98, "speaker": "思雨", "text": "有点情绪化。"},
		{"type": "line", "source": 99, "speaker": "小凌", "text": "……"},
		{"type": "line", "source": 100, "speaker": "思雨", "text": "是不是婚前焦虑？"},
		{"type": "line", "source": 101, "speaker": "小凌", "text": "……"},
		{"type": "line", "source": 102, "speaker": "思雨", "text": "回去早点休息吧。"},
		{"type": "line", "source": 103, "speaker": "旁白", "text": "夜晚，路边大楼的霓虹灯全都亮起来了。小凌靠在副驾驶的车窗上。玻璃上倒影出她模糊的脸。"},
	]


static func _home_events() -> Array[Dictionary]:
	return [
		{"type": "scene", "source": 105, "name": SCENE_HOME},
		{"type": "audio", "source": 105, "action": "stop", "channel": "bgm", "status": "车内 BGM 淡出"},
		{"type": "audio", "source": 105, "action": "start", "channel": "bgm", "stream": "wedding_bgm_home", "status": "现实家中被安排的循环 BGM 起"},
		{"type": "line", "source": 106, "speaker": "旁白", "text": "屋子里已经堆满了明天婚礼要用的东西。"},
		{"type": "line", "source": 107, "speaker": "旁白", "text": "客厅角落放着几个没有拆开的纸箱。"},
		# 群组「选中查看物品」：进入 108–109 旁白前先点看客厅回忆物。
		{
			"type": "module",
			"source": 107,
			"id": "WeddingLivingroomInspect",
			"scene": "res://scenes/wedding/modules/wedding_livingroom_inspect.tscn",
			"completion_signal": "finished",
			"result": "success",
		},
		{"type": "line", "source": 108, "speaker": "旁白", "text": "桌子上摆着请柬、婚礼流程册、宾客名单，还有一束明天要带去酒店的花。"},
		{"type": "line", "source": 109, "speaker": "旁白", "text": "小凌一个人坐到沙发上，盯着柜子发呆。"},
		{"type": "line", "source": 110, "speaker": "旁白", "text": "小凌的妈妈从卧室出来。"},
		{"type": "line", "source": 111, "speaker": "妈妈", "text": "彩排结束了？"},
		{"type": "line", "source": 112, "speaker": "小凌", "text": "嗯。"},
		{"type": "line", "source": 113, "speaker": "妈妈", "text": "怎么样？"},
		{"type": "line", "source": 114, "speaker": "小凌", "text": "还行。"},
		{"type": "line", "source": 115, "speaker": "妈妈", "text": "明天妆发八点就开始，你可千万别迟到。"},
		{"type": "line", "source": 116, "speaker": "小凌", "text": "知道了。"},
		{"type": "line", "source": 117, "speaker": "妈妈", "text": "还有婚纱，记得放好。你从小就丢三落四的，明天可不能再出问题。"},
		{"type": "line", "source": 118, "speaker": "小凌", "text": "知道了。"},
		{"type": "line", "source": 119, "speaker": "妈妈", "text": "宾客名单呢？你有没有再确认一遍？"},
		{"type": "line", "source": 120, "speaker": "小凌", "text": "确认过了。"},
		{"type": "line", "source": 121, "speaker": "妈妈", "text": "还有你们两个的誓词……"},
		# 三次震动逐级加强，最后一次直接把她晃倒——这是通往森林的门。
		{"type": "effect", "source": 122, "id": "world_shake", "intensity": 0.35, "status": "这时候世界开始震动。"},
		{"type": "line", "source": 123, "speaker": "妈妈", "text": "你听见没有？"},
		{"type": "line", "source": 124, "speaker": "小凌", "text": "听见了。"},
		{"type": "line", "source": 125, "speaker": "妈妈", "text": "你这孩子怎么回事？"},
		{"type": "line", "source": 126, "speaker": "小凌", "text": "我说听见了。"},
		{"type": "line", "source": 127, "speaker": "妈妈", "text": "明天就结婚了，你还这个样子。"},
		{"type": "line", "source": 128, "speaker": "小凌", "text": "我什么样子？"},
		{"type": "line", "source": 129, "speaker": "妈妈", "text": "从小到大你就这样。"},
		{"type": "line", "source": 130, "speaker": "小凌", "text": "哪样？"},
		{"type": "line", "source": 131, "speaker": "妈妈", "text": "遇到事情就犹犹豫豫的。"},
		{"type": "line", "source": 132, "speaker": "小凌", "text": "……"},
		{"type": "effect", "source": 133, "id": "world_shake", "intensity": 0.6, "status": "世界又震动了一下。"},
		{"type": "line", "source": 134, "speaker": "妈妈", "text": "结婚这么大的事情，你自己不上心，难道让别人替你操心？"},
		{"type": "line", "source": 135, "speaker": "小凌", "text": "我没有不上心。"},
		{"type": "line", "source": 136, "speaker": "妈妈", "text": "那你现在是在干什么？"},
		{"type": "line", "source": 137, "speaker": "小凌", "text": "我不知道。"},
		{"type": "wait", "source": 138, "seconds": 2.5, "status": "按原文停留 2-3 秒。"},
		{"type": "line", "source": 139, "speaker": "妈妈", "text": "又来了。"},
		{"type": "line", "source": 140, "speaker": "小凌", "text": "什么叫又来了？"},
		{"type": "line", "source": 141, "speaker": "妈妈", "text": "你马上三十岁了。"},
		{"type": "line", "source": 142, "speaker": "小凌", "text": "……"},
		{"type": "effect", "source": 143, "id": "world_shake", "intensity": 1.0, "status": "世界开始不断地晃动。"},
		{"type": "line", "source": 144, "speaker": "妈妈", "text": "这个年纪的人，不能总是什么都不知道。"},
		{"type": "line", "source": 145, "speaker": "旁白", "text": "小凌觉得头晕目眩，瘫倒在沙发上，闭上眼睛。"},
		# 闭眼是婚礼段的终点，下一章先进入奇妙夜。
		{"type": "endpoint", "source": 145, "id": "WEDDING_PROLOGUE_END", "text": "小凌闭上了眼睛。", "next": "奇妙夜"},
	]
