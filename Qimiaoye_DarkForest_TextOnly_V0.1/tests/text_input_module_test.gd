extends Node

const TextInputScene := preload("res://levels/minigames/text_input.tscn")

const EXPECTED_PHRASES := [
	"这样不好吗",
	"别跑这么远",
	"恭喜你被录用了",
	"可是我们要结婚……",
	"留在这里不好吗？",
	"外面情况已经这么糟糕了",
	"别人都这么选……",
	"为什么非得是你？",
	"你确定这是你想要的吗？",
	"先想清楚了再做决定",
	"万一后悔了怎么办？",
	"要是做错了就再也回不去了",
	"你这么做别人会怎么看？",
	"What if you're wrong?",
	"Bleib doch hier.",
	"Was, wenn du es bereust?",
	"Perché proprio tu?",
	"E se fosse un errore?",
	"Cosa diranno gli altri?",
	"Non puoi tornare indietro.",
	"Stay where it's safe.",
	"Don't risk everything.",
	"Reste ici.",
	"Et si tu regrettes ?",
	"Que vont penser les autres ?",
	"Quédate aquí.",
	"¿Y si te equivocas?",
	"No hay vuelta atrás.",
	"Fica aqui.",
	"E se te arrependeres?",
	"Blijf toch hier.",
	"Wat als je spijt krijgt?",
	"Stanna här.",
	"Tänk om du ångrar dig?",
	"Zostań tutaj.",
	"A jeśli pożałujesz?",
]
const ENTITY_COUNT := 72

var _finished_count := 0
var _result: Dictionary = {}


func _ready() -> void:
	var failures := PackedStringArray()
	await _verify_length_limit(failures)
	await _verify_submit_during_interference(failures)

	var module = TextInputScene.instantiate()
	module.setup({"source": 157})
	add_child(module)
	await get_tree().process_frame
	await get_tree().process_frame

	module.finished.connect(_on_finished)
	if module.debug_submit_for_verification("   "):
		failures.append("空白输入被错误接受")
	module.debug_set_text_for_verification("")
	if not module.is_interference_active() or not module.is_waiting_for_fan():
		failures.append("模块启动后没有进入物理清场阶段")
	if not module.is_input_editable():
		failures.append("物理清场前输入框被错误锁死")
	if module.get_wave_started_count() != 1:
		failures.append("初始杂念场只应启动一次")
	if not module.is_camera_bridge_attached():
		failures.append("玩法3没有挂载 Prototype_2_Fan 运行时桥接器")
	if not module.does_interference_cover_screen():
		failures.append("摄像头物理首帧到达前杂念没有立即铺满屏幕")

	var initial_frame := _physics_frame(0.0, false, false)
	if not module.ingest_prototype2_physics_frame(initial_frame):
		failures.append("玩法3拒绝 Prototype_2_Fan 初始物理帧")
	if not module.verify_contract():
		failures.append("初始 UI / Prototype_2_Fan 契约不完整")
	var font_families: PackedStringArray = module.get_ui_font_families()
	if font_families.is_empty() or font_families[0] != "Times New Roman" or not font_families.has("SimSun"):
		failures.append("玩法3没有使用 Times New Roman 与中文宋体回退链")
	if not module.has_prototype_physics_frame():
		failures.append("玩法3没有记录 Prototype_2_Fan 物理帧")
	if not module.does_interference_cover_screen():
		failures.append("杂念没有覆盖足够大的屏幕区域")
	_verify_interference_phrases(module.get_interference_phrases(), failures)
	if module.get_input_latency_seconds() < 3.19:
		failures.append("零清除率时输入延迟不是 3.2 秒")
	if not module.debug_type_for_verification("S"):
		failures.append("杂念未清时无法接收输入意图")
	if module.get_pending_text_change_count() != 1:
		failures.append("杂念未清时字符没有进入延迟队列")
	await get_tree().create_timer(0.20).timeout
	if not module.get_displayed_input_text().is_empty():
		failures.append("杂念未清时字符过早显现")
	await get_tree().create_timer(3.15).timeout
	if module.get_displayed_input_text() != "S":
		failures.append("3.2 秒延迟后字符没有显现")
	if module.debug_set_text_for_verification("") != 0:
		failures.append("延迟输入测试清理失败")
	var initial_position: Vector2 = module.get_interference_entity_position(0)

	var active_frame := _physics_frame(0.45, false, true)
	if not module.ingest_prototype2_physics_frame(active_frame):
		failures.append("玩法3拒绝 Prototype_2_Fan 运动物理帧")
	if module.get_interference_entity_position(0).is_equal_approx(initial_position):
		failures.append("逐帧物理位置没有更新到 Godot 文本实体")
	var metrics: Dictionary = module.get_last_physics_metrics()
	if not bool(metrics.get("hand_force_active", false)):
		failures.append("局部掌风状态没有进入玩法3")
	if float(metrics.get("auto_dispersion_strength", 0.0)) <= 0.0:
		failures.append("双侧自动扩散强度没有进入玩法3")
	if int(metrics.get("last_impulse_stroke_id", 0)) != 2:
		failures.append("冲程冲量编号没有进入玩法3")
	if not module.is_input_editable():
		failures.append("文字仍在物理运动时输入框被错误锁死")
	if module.get_input_latency_seconds() < 2.2:
		failures.append("杂念未清时输入延迟不足")
	if not module.debug_reset_for_verification():
		failures.append("玩法3无法执行重置")
	if module.get_wave_started_count() != 1 or module.get_wave_cleared_count() != 0:
		failures.append("重置后杂念场计数没有回到初始状态")
	if not module.is_waiting_for_fan() or not module.is_input_editable():
		failures.append("重置后玩法3没有恢复可输入的受阻状态")
	if module.has_prototype_physics_frame() or not module.get_last_physics_metrics().is_empty():
		failures.append("重置后仍保留上一轮物理帧数据")
	if not module.ingest_prototype2_physics_frame(initial_frame):
		failures.append("重置后玩法3拒绝新的 Prototype_2_Fan 初始物理帧")

	var clear_frame := _physics_frame(1.0, false, true)
	if not module.ingest_prototype2_physics_frame(clear_frame):
		failures.append("玩法3拒绝 Prototype_2_Fan 清场物理帧")
	await get_tree().create_timer(0.25).timeout
	if module.get_wave_cleared_count() != 1:
		failures.append("物理世界完全清场后没有完成阶段")
	if module.is_interference_active():
		failures.append("物理清场后杂念仍处于阻塞状态")
	if not module.is_input_editable():
		failures.append("物理清场后输入框没有恢复编辑")
	if module.get_input_latency_seconds() > 0.01:
		failures.append("物理清场后输入延迟没有归零")
	if _finished_count != 0:
		failures.append("物理清场后提前结束，玩家无法输入")

	module.debug_set_text_for_verification("我在想但大家都已经替我决定了")
	if not module.is_submit_enabled():
		failures.append("有文字时说出来按钮未启用")
	if not module.debug_submit_for_verification("我在想但大家都已经替我决定了"):
		failures.append("完成物理清场后无法提交自己的想法")
	await get_tree().create_timer(0.35).timeout

	if _finished_count != 1:
		failures.append("finished 发射次数异常：%d/1" % _finished_count)
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
	if int(_result.get("interference_entity_count", 0)) != ENTITY_COUNT:
		failures.append("完成结果中的杂念实体数错误")
	if str(_result.get("physics_runtime", "")) != "Prototype_2_Fan":
		failures.append("完成结果没有记录权威物理运行时")
	if not bool(_result.get("prototype_physics_received", false)):
		failures.append("完成结果没有记录逐帧物理接入")

	if failures.is_empty():
		print("TEXT_INPUT_PROTOTYPE2_PHYSICS_PASS source=157 runtime=Prototype_2_Fan entities=72 phrases=36 serif_ui=true field_frames=true force_metrics=true reset=true delayed_input=true submit_independent=true physics_clear=true input_unlocked=true raw_text_logged=false")
		get_tree().quit(0)
		return
	for failure in failures:
		print("TEXT_INPUT_PROTOTYPE2_PHYSICS_FAIL %s" % failure)
	get_tree().quit(1)


func _verify_length_limit(failures: PackedStringArray) -> void:
	var length_module = TextInputScene.instantiate()
	length_module.setup({"source": 157})
	add_child(length_module)
	await get_tree().process_frame
	if length_module.debug_set_text_for_verification("界".repeat(140)) != 120:
		failures.append("输入没有严格限制为 120 字符")
	length_module.queue_free()
	await get_tree().process_frame


func _verify_submit_during_interference(failures: PackedStringArray) -> void:
	var submit_module = TextInputScene.instantiate()
	submit_module.setup({"source": 157})
	add_child(submit_module)
	await get_tree().process_frame
	await get_tree().process_frame
	if not submit_module.is_interference_active():
		failures.append("提交独立性测试未进入杂念物理阶段")
	submit_module.debug_set_text_for_verification("我现在就要说")
	if not submit_module.is_submit_enabled():
		failures.append("杂念仍在时说出来按钮未启用")
	if not submit_module.debug_submit_for_verification("我现在就要说"):
		failures.append("杂念仍在时无法提交文字")
	submit_module.queue_free()
	await get_tree().process_frame


func _verify_interference_phrases(phrases: PackedStringArray, failures: PackedStringArray) -> void:
	if phrases.size() != ENTITY_COUNT:
		failures.append("杂念实体数不是 %d：%d" % [ENTITY_COUNT, phrases.size()])
	var seen: Dictionary = {}
	for phrase in phrases:
		seen[phrase] = true
	for expected in EXPECTED_PHRASES:
		if not seen.has(expected):
			failures.append("缺少 DOCX 杂念文案：%s" % expected)
	for phrase in seen:
		if phrase not in EXPECTED_PHRASES:
			failures.append("混入 DOCX 之外的杂念文案：%s" % phrase)


func _physics_frame(dispersed_ratio: float, clear_ready: bool, moving: bool) -> Dictionary:
	var entities: Array[Dictionary] = []
	for index in range(ENTITY_COUNT):
		var column := index % 9
		var row := (index / 9) % 8
		var start := Vector2(
			55.0 + float(column) * 111.0,
			92.0 + float(row) * 80.0
		) + Vector2(
			float((index * 13) % 49) - 24.0,
			float((index * 7) % 31) - 15.0
		)
		var side := -1 if start.x < 500.0 else 1
		var x := start.x + float(side) * dispersed_ratio * 820.0
		entities.append({
			"index": index,
			"text": EXPECTED_PHRASES[index % EXPECTED_PHRASES.size()],
			"x": x,
			"y": start.y,
			"width": 180.0,
			"height": 40.0,
			"mass": 1.0 + float(index % 3) * 0.08,
			"font_size": 30 + index % 13,
			"color": [235, 104, 115] if index % 2 == 0 else [112, 168, 255],
			"opacity": 0.82,
			"velocity_x": float(side) * 640.0 if moving else 0.0,
			"velocity_y": 0.0,
			"side": side,
			"dispersed": clear_ready,
		})
	return {
		"event": "prototype2_physics_frame",
		"field_width": 1000,
		"field_height": 700,
		"state": "FANNING" if moving else "PALM_ARMING",
		"direction": "right",
		"sweep_count": 2 if moving else 0,
		"fan_strength": 0.86 if moving else 0.0,
		"gesture_completed": moving,
		"event_completed": moving,
		"hand_detected": true,
		"open_palm": true,
		"entities": entities,
		"metrics": {
			"dispersed_count": ENTITY_COUNT if clear_ready else int(round(ENTITY_COUNT * dispersed_ratio)),
			"dispersed_ratio": dispersed_ratio,
			"hand_force_active": moving,
			"local_force_strength": 0.92 if moving else 0.0,
			"texts_inside_influence_area": 8 if moving else 0,
			"last_impulse_strength": 168.0 if moving else 0.0,
			"last_impulse_stroke_id": 2 if moving else 0,
			"stroke_phase": "active" if moving else "ready",
			"stroke_direction": 1 if moving else 0,
			"auto_dispersion_strength": 0.78 if moving else 0.0,
			"mean_velocity_x": 12.0 if moving else 0.0,
			"mean_velocity_y": 0.0,
		},
		"clear_ready": clear_ready,
	}


func _on_finished(result: Variant) -> void:
	_finished_count += 1
	_result = result if result is Dictionary else {"result": str(result)}
