extends Node

## 奇妙夜事件表与独立场景契约测试。

const MysticNightDataScript := preload("res://scripts/mystic_night_data.gd")
const DevJumpPanelScript := preload("res://scripts/dev_jump_panel.gd")
const MysticNightScene := preload("res://scenes/mystic_night/mystic_night.tscn")

const EXPECTED_CGS := [
	"奇妙夜场景1",
	"奇妙夜场景2",
	"奇妙夜拉手图",
	"奇妙夜鸟图",
	"奇妙夜星星图",
	"奇妙夜送花图",
	"奇妙夜追逐图",
	"奇妙夜发光动物图",
	"奇妙夜湿地图",
	"奇妙夜森林轮廓图",
	"奇妙夜别去图",
	"奇妙夜女孩身影图",
	"黑屏",
]
const EXPECTED_CG_SOURCES := [16, 37, 61, 71, 89, 95, 96, 96, 96, 105, 134, 138, 146]
const EXPECTED_VIDEO_RANGES := [Vector2i(37, 60), Vector2i(89, 94), Vector2i(105, 133)]
const EXPECTED_ART_SCENES := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0]
const EXPECTED_SHOTS := [
	"shot_01_wake",
	"shot_02_turn",
	"shot_03_landing_pulse",
	"shot_04_walk",
	"shot_05_reveal",
	"shot_06_run",
	"shot_07_forest_push",
	"shot_08_still",
	"shot_09_last_look",
]
const EXPECTED_STAGE_DIRECTIONS := [
	[37, "小凌", "（回头）"],
	[40, "小凌", "（后退一步）"],
	[48, "女孩", "（点点头）"],
	[58, "小凌", "（犹豫）"],
	[64, "女孩", "回头"],
	[66, "小凌", "（摸了一下自己的脸）"],
	[82, "小凌", "（抬起头）"],
	[122, "女孩", "（看向森林深处）"],
	[122, "小凌", "（向前走了一步）"],
	[134, "女孩", "（没有回答我，只是摇了摇头）"],
]
const EXPECTED_SOURCE_96_NARRATION := [
	"一只发光的小动物突然从高高的草丛里钻了出来，沿着草叶间飞快地跑远。",
	"女孩和小凌对视一眼，不约而同地追了上去。",
	"两个人一前一后穿过大片起伏的高草，发光的小动物时隐时现，像一颗在草丛里跳动的小星星。",
	"女孩忽然放慢脚步，伸出双手，小心翼翼地将它捧在掌心。",
	"小动物蜷缩起来，身体一点点亮起蓝色的光。",
	"光映在女孩的脸上，也照亮了小凌的眼睛。",
	"女孩低头看着掌心的小动物，忍不住笑了。",
]


func _ready() -> void:
	var failures: PackedStringArray = []
	var events := MysticNightDataScript.build_events()
	var type_counts: Dictionary = {}
	var speaker_counts: Dictionary = {}
	var cg_names := PackedStringArray()
	var cg_sources := PackedInt32Array()
	var art_scenes := PackedInt32Array()
	var camera_ids := PackedStringArray()
	var source_63_texts := PackedStringArray()
	var source_96_narration := PackedStringArray()
	var source_96_cgs := PackedStringArray()
	var video_count := 0
	var video_ranges: Array[Vector2i] = []
	var stage_direction_count := 0

	for event in events:
		var event_type := str(event.get("type", ""))
		type_counts[event_type] = int(type_counts.get(event_type, 0)) + 1
		if event_type == "line":
			var speaker := str(event.get("speaker", ""))
			var text := str(event.get("text", ""))
			var is_stage_direction := bool(event.get("stage_direction", false))
			var is_psychology := speaker.begins_with("心理")
			speaker_counts[speaker] = int(speaker_counts.get(speaker, 0)) + 1
			if ("（" in text or "）" in text) and not is_stage_direction and not is_psychology:
				failures.append("未标记的括号演出提示进入显示文字：%s" % text)
			if is_stage_direction:
				stage_direction_count += 1
			if int(event.get("source", 0)) == 63:
				source_63_texts.append(text)
			if int(event.get("source", 0)) == 96 and speaker == "旁白":
				source_96_narration.append(text)
		elif event_type == "cg":
			var cg_name := str(event.get("name", ""))
			var asset_path := str(event.get("asset", ""))
			var video_path := str(event.get("video_asset", ""))
			cg_names.append(cg_name)
			cg_sources.append(int(event.get("source", 0)))
			art_scenes.append(int(event.get("art_scene_index", 0)))
			if cg_name != "黑屏" and (asset_path.is_empty() or not ResourceLoader.exists(asset_path)):
				failures.append("CG 资源不存在：%s / %s" % [cg_name, asset_path])
			if not video_path.is_empty():
				video_count += 1
				video_ranges.append(Vector2i(int(event.get("source", 0)), int(event.get("video_end_source", 0))))
				if not ResourceLoader.exists(video_path):
					failures.append("CG 视频不存在：%s / %s" % [cg_name, video_path])
			if int(event.get("source", 0)) == 96:
				source_96_cgs.append(cg_name)
		elif event_type == "camera":
			camera_ids.append(str(event.get("id", "")))

	var expected_type_counts := {
		"scene": 1,
		"cg": 13,
		"camera": 9,
		"line": 106,
		"interaction": 1,
		"endpoint": 1,
	}
	if events.size() != 131 or type_counts != expected_type_counts:
		failures.append("事件统计异常：events=%d types=%s" % [events.size(), str(type_counts)])
	var expected_speaker_counts := {"旁白": 56, "小凌": 24, "女孩": 21, "？？？": 1, "心理": 4}
	if speaker_counts != expected_speaker_counts:
		failures.append("显示台词统计异常：%s" % str(speaker_counts))
	if stage_direction_count != 10:
		failures.append("动作对白数量异常：%d" % stage_direction_count)
	if video_count != 3:
		failures.append("场景 2/5/10 视频数量异常：%d" % video_count)
	if video_ranges != EXPECTED_VIDEO_RANGES:
		failures.append("场景 2/5/10 视频区间异常：%s" % str(video_ranges))
	if DevJumpPanelScript.source_bounds(events) != Vector2i(1, 146):
		failures.append("DOCX 来源范围异常：%s" % DevJumpPanelScript.source_bounds(events))
	if cg_names != PackedStringArray(EXPECTED_CGS):
		failures.append("CG 资源槽顺序异常：%s" % str(cg_names))
	if cg_sources != PackedInt32Array(EXPECTED_CG_SOURCES):
		failures.append("CG F4 行号映射异常：%s" % str(cg_sources))
	if art_scenes != PackedInt32Array(EXPECTED_ART_SCENES):
		failures.append("1–12 号美术场景映射异常：%s" % str(art_scenes))
	if camera_ids != PackedStringArray(EXPECTED_SHOTS):
		failures.append("重点镜头顺序异常：%s" % str(camera_ids))
	if source_63_texts != PackedStringArray(["远处偶尔传来不知道什么动物的叫声。", "前面是一片很高的草坡。"]):
		failures.append("DOCX 第 63 段没有拆成两条旁白")
	if source_96_narration != PackedStringArray(EXPECTED_SOURCE_96_NARRATION):
		failures.append("DOCX 第 96 段替换叙事异常：%s" % str(source_96_narration))
	if source_96_cgs != PackedStringArray(["奇妙夜追逐图", "奇妙夜发光动物图", "奇妙夜湿地图"]):
		failures.append("DOCX 第 96 段没有按 7→8→9 切场：%s" % str(source_96_cgs))

	_assert_line(events, failures, 39, "旁白", "她静静面对着小凌。")
	_assert_line(events, failures, 45, "女孩", "可能是因为，我迷路了。")
	_assert_line(events, failures, 64, "女孩", "你刚才在哭吗？")
	_assert_line(events, failures, 82, "小凌", "我明天要结婚了。")
	for direction in EXPECTED_STAGE_DIRECTIONS:
		_assert_stage_direction(events, failures, int(direction[0]), str(direction[1]), str(direction[2]))
	for forbidden_source in [102, 135, 140]:
		if _events_at_source(events, forbidden_source) > 0:
			failures.append("未编号技术效果进入事件表：DOCX 第 %d 段" % forbidden_source)

	var interaction_jump := DevJumpPanelScript.resolve_source_line(events, 58)
	var interaction_events := _events_for_source(events, 58)
	if interaction_jump.is_empty() or interaction_events.size() != 2 or str(interaction_events[1].get("id", "")) != "follow_girl":
		failures.append("F4 第 58 行没有按动作对白→跟随交互排列")
	for cg_source in [37, 61, 71, 89, 95, 96, 105, 134, 138]:
		var source_events := _events_for_source(events, cg_source)
		if not source_events.any(func(event: Dictionary) -> bool: return str(event.get("type", "")) == "cg"):
			failures.append("F4 第 %d 行没有映射到新 CG" % cg_source)
	var endpoint_events := events.filter(func(event: Dictionary) -> bool:
		return str(event.get("type", "")) == "endpoint"
	)
	if endpoint_events.size() != 1 or str(endpoint_events[0].get("next", "")) != "森林正片 EYE_OPEN":
		failures.append("奇妙夜 endpoint 没有接到森林 EYE_OPEN")

	var scene_root := MysticNightScene.instantiate()
	if not scene_root is Control or scene_root.get_script() == null:
		failures.append("奇妙夜独立场景根节点或脚本缺失")
	scene_root.free()

	if not failures.is_empty():
		for failure in failures:
			print("MYSTIC_NIGHT_TEST_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("MYSTIC_NIGHT_TEST_PASS events=131 source_bounds=(1,146) narration_lines=56 dialogue_lines=50 stage_directions=10 cgs=13 videos=3 video_ranges=37_60,89_94,105_133 camera_shots=9 interactions=1 endpoint=true art_scenes=1_to_12 source96=7_to_8_to_9")
	get_tree().quit(0)


func _assert_line(events: Array[Dictionary], failures: PackedStringArray, source: int, speaker: String, text: String) -> void:
	var matches := 0
	for event in events:
		if str(event.get("type", "")) != "line" or int(event.get("source", 0)) != source:
			continue
		if str(event.get("speaker", "")) == speaker and str(event.get("text", "")) == text:
			matches += 1
	if matches != 1:
		failures.append("DOCX 第 %d 段拆分结果异常" % source)


func _assert_stage_direction(events: Array[Dictionary], failures: PackedStringArray, source: int, speaker: String, text: String) -> void:
	for event in events:
		if int(event.get("source", 0)) == source and str(event.get("speaker", "")) == speaker and str(event.get("text", "")) == text and bool(event.get("stage_direction", false)):
			return
	failures.append("DOCX 第 %d 段动作对白缺失：%s %s" % [source, speaker, text])


func _events_for_source(events: Array[Dictionary], source: int) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for event in events:
		if int(event.get("source", 0)) == source:
			matches.append(event)
	return matches


func _events_at_source(events: Array[Dictionary], source: int) -> int:
	return _events_for_source(events, source).size()
