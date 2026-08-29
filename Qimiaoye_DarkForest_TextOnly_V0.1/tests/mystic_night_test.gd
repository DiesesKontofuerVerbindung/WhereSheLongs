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
	"奇妙夜发光动物图",
	"奇妙夜湿地图",
	"奇妙夜森林轮廓图",
	"奇妙夜别去图",
	"奇妙夜女孩身影图",
	"黑屏",
]
const EXPECTED_CG_SOURCES := [16, 35, 59, 87, 90, 93, 98, 100, 105, 133, 142, 146]
const EXPECTED_ART_PARAGRAPHS := [15, 24, 43, 60, 76, 78, 82, 85, 95, 118, 125, 129]
const EXPECTED_SHOTS := [
	"shot_01_wake",
	"shot_02_turn",
	"shot_03_landing_pulse",
	"shot_04_reveal",
	"shot_05_run",
	"shot_06_forest_push",
	"shot_07_still",
	"shot_08_last_look",
]


func _ready() -> void:
	var failures: PackedStringArray = []
	var events := MysticNightDataScript.build_events()
	var type_counts: Dictionary = {}
	var speaker_counts: Dictionary = {}
	var cg_names := PackedStringArray()
	var cg_sources := PackedInt32Array()
	var art_paragraphs := PackedInt32Array()
	var camera_ids := PackedStringArray()
	var source_63_texts := PackedStringArray()

	for event in events:
		var event_type := str(event.get("type", ""))
		type_counts[event_type] = int(type_counts.get(event_type, 0)) + 1
		if event_type == "line":
			var speaker := str(event.get("speaker", ""))
			var text := str(event.get("text", ""))
			speaker_counts[speaker] = int(speaker_counts.get(speaker, 0)) + 1
			if "（" in text or "）" in text:
				failures.append("括号演出提示进入了显示文字：%s" % text)
			if int(event.get("source", 0)) == 63:
				source_63_texts.append(text)
		elif event_type == "cg":
			var cg_name := str(event.get("name", ""))
			var asset_path := str(event.get("asset", ""))
			cg_names.append(cg_name)
			cg_sources.append(int(event.get("source", 0)))
			art_paragraphs.append(int(event.get("art_docx_paragraph", 0)))
			if cg_name != "黑屏" and (asset_path.is_empty() or not ResourceLoader.exists(asset_path)):
				failures.append("CG 资源不存在：%s / %s" % [cg_name, asset_path])
		elif event_type == "camera":
			camera_ids.append(str(event.get("id", "")))

	var expected_type_counts := {
		"scene": 1,
		"cg": 12,
		"camera": 8,
		"line": 91,
		"interaction": 1,
		"endpoint": 1,
	}
	if events.size() != 114 or type_counts != expected_type_counts:
		failures.append("事件统计异常：events=%d types=%s" % [events.size(), str(type_counts)])
	var expected_speaker_counts := {"旁白": 51, "小凌": 18, "女孩": 17, "？？？": 1, "心理": 4}
	if speaker_counts != expected_speaker_counts:
		failures.append("显示台词统计异常：%s" % str(speaker_counts))
	if DevJumpPanelScript.source_bounds(events) != Vector2i(1, 146):
		failures.append("DOCX 来源范围异常：%s" % DevJumpPanelScript.source_bounds(events))
	if cg_names != PackedStringArray(EXPECTED_CGS):
		failures.append("CG 资源槽顺序异常：%s" % str(cg_names))
	if cg_sources != PackedInt32Array(EXPECTED_CG_SOURCES):
		failures.append("CG F4 行号映射异常：%s" % str(cg_sources))
	if art_paragraphs != PackedInt32Array(EXPECTED_ART_PARAGRAPHS):
		failures.append("CG 美术 DOCX 段落映射异常：%s" % str(art_paragraphs))
	if camera_ids != PackedStringArray(EXPECTED_SHOTS):
		failures.append("重点镜头顺序异常：%s" % str(camera_ids))
	if source_63_texts != PackedStringArray(["远处偶尔传来不知道什么动物的叫声。", "前面是一片很高的草坡。"]):
		failures.append("DOCX 第 63 段没有拆成两条旁白")

	_assert_line(events, failures, 39, "旁白", "她静静面对着小凌。")
	_assert_line(events, failures, 45, "女孩", "可能是因为，我迷路了。")
	_assert_line(events, failures, 64, "女孩", "你刚才在哭吗？")
	_assert_line(events, failures, 82, "小凌", "我明天要结婚了。")
	for forbidden_source in [102, 135, 140]:
		if _events_at_source(events, forbidden_source) > 0:
			failures.append("未编号技术效果进入事件表：DOCX 第 %d 段" % forbidden_source)

	var gap_jump := DevJumpPanelScript.resolve_source_line(events, 17)
	if gap_jump.is_empty() or int(gap_jump.get("source", 0)) != 18 or bool(gap_jump.get("exact", true)):
		failures.append("动作提示段没有正确跳过：17 -> 18")
	var interaction_jump := DevJumpPanelScript.resolve_source_line(events, 58)
	var interaction_event: Dictionary = interaction_jump.get("event", {})
	if str(interaction_event.get("id", "")) != "follow_girl" or int(interaction_event.get("art_docx_paragraph", 0)) != 42:
		failures.append("F4 第 58 行与美术 DOCX 第 42 段交互映射异常")
	for cg_source in [98, 100, 133]:
		var cg_jump := DevJumpPanelScript.resolve_source_line(events, cg_source)
		var cg_event: Dictionary = cg_jump.get("event", {})
		if cg_jump.is_empty() or str(cg_event.get("type", "")) != "cg":
			failures.append("F4 第 %d 行没有优先落到新增 CG" % cg_source)
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
	print("MYSTIC_NIGHT_TEST_PASS events=114 source_bounds=(1, 146) narration_lines=55 dialogue_lines=36 cgs=12 camera_shots=8 interactions=1 endpoint=true art_assets=true dual_docx_mapping=true technical_notes_hidden=true")
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


func _events_at_source(events: Array[Dictionary], source: int) -> int:
	var count := 0
	for event in events:
		if int(event.get("source", 0)) == source:
			count += 1
	return count
