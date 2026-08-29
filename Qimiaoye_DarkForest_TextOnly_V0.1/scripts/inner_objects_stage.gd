extends Control
class_name InnerObjectsStage

## DOCX 309「主观内心背景图0」，覆盖 310–315。
##
## 演出顺序：
##   1. 湖边谈心的 lake_talk 循环继续播，但整幅推成虚化；
##   2. 六件生活物件按 310–315 逐句淡入（不掉落，原地浮现）；
##   3. 315 起接 Prototype_2_Fan：摄像头捕捉张掌横扫，把物件挥散；
##   4. 挥净后黑屏，去掉虚化，lake_talk 循环原样接回去。
##
## 物理不在这里算。实体坐标由 fan_camera_bridge.py 侧的 interference_field
## 推过来（prototype2_physics_frame），本脚本只把 entity 的 x/y/opacity/dispersed
## 贴到对应物件上 —— 与玩法3 text_input.gd 的消费方式一致，不重写干扰场。

signal objects_cleared

const FanCameraBridgeScript := preload("res://levels/minigames/fan_camera_bridge.gd")

const SCENE_NAME := "主观内心背景图0"
## 手势解锁行：310–314 逐件浮现，315「然后慢慢忘记自己是谁」之后才允许挥开。
const FAN_ARM_SOURCE := 315
## Prototype_2 干扰场的逻辑画布，与 text_input.gd 的 PROTOTYPE_FIELD_SIZE 同源。
const PROTOTYPE_FIELD_SIZE := Vector2(1000.0, 700.0)
const OBJECT_FADE_IN_SECONDS := 1.6
const BLACKOUT_SECONDS := 0.9
const BLACKOUT_HOLD_SECONDS := 0.5
const CUTSCENE_BLUR_RADIUS := 0.016
const CUTSCENE_BLUR_SECONDS := 1.2

## 素材来自 Szene/物件33 的六张透明切图；构图照 0.png 的合成稿。
## laptop / ring box 没有素材，本轮不做。
## anchor 是物件中心占画面的比例，height_ratio 是物件高度占画面高度的比例。
const OBJECT_SPECS := [
	{
		"name_tag": "闹钟",
		"texture": "res://assets/inner_objects/alarm_clock.png",
		"anchor": Vector2(0.305, 0.755),
		"height_ratio": 0.56,
	},
	{
		"name_tag": "手机",
		"texture": "res://assets/inner_objects/phone.png",
		"anchor": Vector2(0.925, 0.560),
		"height_ratio": 0.77,
	},
	{
		"name_tag": "头纱",
		"texture": "res://assets/inner_objects/veil.png",
		"anchor": Vector2(0.750, 0.560),
		"height_ratio": 0.61,
	},
	{
		"name_tag": "奶瓶",
		"texture": "res://assets/inner_objects/baby_bottle.png",
		"anchor": Vector2(0.140, 0.650),
		"height_ratio": 0.70,
	},
	{
		"name_tag": "镜子",
		"texture": "res://assets/inner_objects/mirror.png",
		"anchor": Vector2(0.075, 0.430),
		"height_ratio": 0.81,
	},
	{
		"name_tag": "化妆品",
		"texture": "res://assets/inner_objects/cosmetics.png",
		"anchor": Vector2(0.710, 0.760),
		"height_ratio": 0.43,
	},
]

enum Phase { IDLE, APPEARING, ARMED, CLEARED }

var _objects: Array = []
var _blackout: ColorRect
var _prompt_label: Label
var _camera_bridge
var _cutscene_player
var _phase := Phase.IDLE
var _revealed_count := 0
var _camera_state := "idle"
var _physics_frame_seen := false
var _dispersed_ratio := 0.0
## 跨 deactivate 保留：全流程结束时舞台已合法退回 IDLE，只能靠计数证明挥开发生过。
var _cleared_count := 0
var _fade_tweens: Dictionary = {}


func _ready() -> void:
	name = "SubjectiveInnerObjectsStage"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_objects()
	_build_blackout()
	_build_prompt()
	resized.connect(_layout_objects)
	_layout_objects()
	visible = false


func set_cutscene_player(player) -> void:
	_cutscene_player = player


func _build_objects() -> void:
	for spec in OBJECT_SPECS:
		var name_tag := str(spec["name_tag"])
		var view := TextureRect.new()
		view.name = "InnerObject_%s" % name_tag
		view.texture = load(str(spec["texture"])) as Texture2D
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.set_meta("name_tag", name_tag)
		view.modulate.a = 0.0
		view.visible = false
		add_child(view)
		_objects.append(view)


func _build_blackout() -> void:
	_blackout = ColorRect.new()
	_blackout.name = "InnerBlackout"
	_blackout.color = Color.BLACK
	_blackout.modulate.a = 0.0
	_blackout.visible = false
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blackout)


func _build_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.name = "InnerFanPrompt"
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt_label.offset_left = -520.0
	_prompt_label.offset_right = 520.0
	_prompt_label.offset_top = 26.0
	_prompt_label.offset_bottom = 66.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.add_theme_color_override("font_color", Color("dbe4ef"))
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.visible = false
	add_child(_prompt_label)


func _layout_objects() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	for index in range(_objects.size()):
		var view := _objects[index] as TextureRect
		var spec: Dictionary = OBJECT_SPECS[index]
		var texture := view.texture
		if texture == null:
			continue
		var source_size := texture.get_size()
		if source_size.y <= 0.0:
			continue
		var target_height := size.y * float(spec["height_ratio"])
		var target_size := Vector2(source_size.x / source_size.y * target_height, target_height)
		var anchor: Vector2 = spec["anchor"]
		view.size = target_size
		view.position = Vector2(size.x * anchor.x, size.y * anchor.y) - target_size * 0.5


## 进入 DOCX 309：CG 推虚化，物件从 alpha 0 开始等着逐句浮现。
func activate(instant: bool) -> void:
	_phase = Phase.APPEARING
	_revealed_count = 0
	_physics_frame_seen = false
	_dispersed_ratio = 0.0
	visible = true
	_blackout.visible = false
	_blackout.modulate.a = 0.0
	_prompt_label.visible = false
	_layout_objects()
	for view in _objects:
		var rect := view as TextureRect
		_kill_fade_tween(rect)
		rect.visible = false
		rect.modulate.a = 0.0
	_apply_cutscene_blur(CUTSCENE_BLUR_RADIUS, instant)
	if instant:
		# verify / headless 不等淡入，直接摆成全部浮现。
		for view in _objects:
			var rect := view as TextureRect
			rect.visible = true
			rect.modulate.a = 1.0
		_revealed_count = _objects.size()


## 310–315 每推进一行浮现一件；315 之外的行不重复触发。
func sync_for_source(source: int) -> void:
	if _phase != Phase.APPEARING:
		return
	var wanted := clampi(source - 309, 0, _objects.size())
	while _revealed_count < wanted:
		_reveal_object(_revealed_count)
		_revealed_count += 1


func _reveal_object(index: int) -> void:
	if index < 0 or index >= _objects.size():
		return
	var view := _objects[index] as TextureRect
	view.visible = true
	_kill_fade_tween(view)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "modulate:a", 1.0, OBJECT_FADE_IN_SECONDS)
	_fade_tweens[view] = tween


func _kill_fade_tween(view: TextureRect) -> void:
	var tween = _fade_tweens.get(view)
	if tween is Tween and tween.is_running():
		tween.kill()
	_fade_tweens.erase(view)


## DOCX 315：开摄像头，交给 Prototype_2_Fan 的干扰场。
func arm_fan() -> void:
	# 还没浮现完的直接补齐，避免手势打在看不见的物件上。
	for index in range(_revealed_count, _objects.size()):
		_reveal_object(index)
	_revealed_count = _objects.size()
	_phase = Phase.ARMED
	_prompt_label.visible = true
	_prompt_label.text = "正在连接摄像头……"
	if _camera_bridge != null:
		return
	_camera_bridge = FanCameraBridgeScript.new()
	_camera_bridge.name = "InnerFanCameraBridge"
	# 干扰场默认 72 个实体；这一幕只有六件物件，实体数必须对齐才收得到帧。
	_camera_bridge.entity_count = _objects.size()
	_camera_bridge.physics_frame_received.connect(_on_physics_frame)
	_camera_bridge.status_changed.connect(_on_camera_status_changed)
	add_child(_camera_bridge)
	_camera_bridge.start_bridge()


func _on_camera_status_changed(state: String, detail: String) -> void:
	_camera_state = state
	match state:
		"starting":
			_prompt_label.text = "正在连接摄像头……"
		"ready":
			_prompt_label.text = "张开手掌，水平往返挥扫，把这些挥开"
			print("INNER_OBJECTS_PROTOTYPE2_RUNTIME_READY %s" % detail)
		"reset":
			_prompt_label.text = "物理场已重置 · 张开手掌，水平往返挥扫"
		"error":
			_prompt_label.text = "摄像头无法启动：%s" % detail
			push_warning("INNER_OBJECTS_PROTOTYPE2_RUNTIME_ERROR %s" % detail)


func _on_physics_frame(frame: Dictionary) -> void:
	if _phase != Phase.ARMED:
		return
	var entities: Variant = frame.get("entities", [])
	if not entities is Array or (entities as Array).size() != _objects.size():
		return
	_physics_frame_seen = true
	_apply_entities(entities as Array)
	var metrics: Variant = frame.get("metrics", {})
	if metrics is Dictionary:
		_dispersed_ratio = float((metrics as Dictionary).get("dispersed_ratio", 0.0))
	_update_fan_prompt(frame)
	if _dispersed_ratio >= 1.0:
		_mark_cleared()


## entity 坐标在 1000x700 的逻辑场里，按比例铺到当前画面。
func _apply_entities(entities: Array) -> void:
	for entity_value in entities:
		if not entity_value is Dictionary:
			continue
		var entity: Dictionary = entity_value
		var index := int(entity.get("index", -1))
		if index < 0 or index >= _objects.size():
			continue
		var view := _objects[index] as TextureRect
		var field_x := float(entity.get("x", PROTOTYPE_FIELD_SIZE.x * 0.5)) / PROTOTYPE_FIELD_SIZE.x
		var field_y := float(entity.get("y", PROTOTYPE_FIELD_SIZE.y * 0.5)) / PROTOTYPE_FIELD_SIZE.y
		view.position = Vector2(size.x * field_x, size.y * field_y) - view.size * 0.5
		var dispersed := bool(entity.get("dispersed", false))
		view.visible = not dispersed
		view.modulate.a = 0.0 if dispersed else clampf(float(entity.get("opacity", 1.0)), 0.0, 1.0)


func _update_fan_prompt(frame: Dictionary) -> void:
	var clear_percent := int(round(_dispersed_ratio * 100.0))
	if not bool(frame.get("hand_detected", false)):
		_prompt_label.text = "把张开的手放进镜头"
		return
	if not bool(frame.get("open_palm", false)):
		_prompt_label.text = "请张开手掌，再水平往返挥动"
		return
	match str(frame.get("state", "TRACKING")):
		"PALM_ARMING":
			_prompt_label.text = "张开手掌，稳住……"
		"FAN_READY":
			_prompt_label.text = "开始水平挥扫"
		"FANNING":
			var direction_text := "向右" if str(frame.get("direction", "center")) == "right" else "向左"
			_prompt_label.text = "%s · 挥开 %d%%" % [direction_text, clear_percent]
		_:
			_prompt_label.text = "张开手掌，水平往返挥扫"


func _mark_cleared() -> void:
	if _phase == Phase.CLEARED:
		return
	_phase = Phase.CLEARED
	_cleared_count += 1
	_prompt_label.visible = false
	objects_cleared.emit()


## verify / 无摄像头兜底：直接判定挥净。
func debug_force_clear() -> void:
	for view in _objects:
		var rect := view as TextureRect
		rect.visible = false
		rect.modulate.a = 0.0
	_dispersed_ratio = 1.0
	_mark_cleared()


## 挥净之后：黑屏 → 收物件、去虚化 → 亮回 lake_talk 循环。
func play_blackout_and_restore(instant: bool) -> void:
	var fade_seconds := 0.012 if instant else BLACKOUT_SECONDS
	_blackout.visible = true
	if instant:
		_blackout.modulate.a = 1.0
	else:
		var to_black := create_tween()
		to_black.tween_property(_blackout, "modulate:a", 1.0, fade_seconds)
		await to_black.finished
		await get_tree().create_timer(BLACKOUT_HOLD_SECONDS).timeout
	_hide_objects()
	_stop_camera_bridge()
	_apply_cutscene_blur(0.0, instant)
	if instant:
		_blackout.modulate.a = 0.0
	else:
		var from_black := create_tween()
		from_black.tween_property(_blackout, "modulate:a", 0.0, fade_seconds)
		await from_black.finished
	_blackout.visible = false
	# 物件没了，湖边循环恢复清晰；这一层退成完全透明，不再挡画面。
	visible = false
	_phase = Phase.CLEARED


func _hide_objects() -> void:
	for view in _objects:
		var rect := view as TextureRect
		_kill_fade_tween(rect)
		rect.visible = false
		rect.modulate.a = 0.0


func _apply_cutscene_blur(radius: float, instant: bool) -> void:
	if _cutscene_player == null or not _cutscene_player.has_method("set_frame_blur"):
		return
	_cutscene_player.set_frame_blur(radius, 0.0 if instant else CUTSCENE_BLUR_SECONDS)


func _stop_camera_bridge() -> void:
	if _camera_bridge == null:
		return
	_camera_bridge.stop_bridge()
	_camera_bridge.queue_free()
	_camera_bridge = null


func deactivate() -> void:
	if _phase == Phase.IDLE and not visible:
		return
	_hide_objects()
	_stop_camera_bridge()
	_apply_cutscene_blur(0.0, true)
	if _blackout != null:
		_blackout.visible = false
		_blackout.modulate.a = 0.0
	if _prompt_label != null:
		_prompt_label.visible = false
	visible = false
	_phase = Phase.IDLE


func uses_inner_stage(scene_name: String) -> bool:
	return scene_name == SCENE_NAME


func is_active() -> bool:
	return _phase != Phase.IDLE


func name_tags() -> PackedStringArray:
	var tags := PackedStringArray()
	for view in _objects:
		tags.append(str((view as TextureRect).get_meta("name_tag", "")))
	return tags


func verify_contract() -> bool:
	if _objects.size() != OBJECT_SPECS.size():
		return false
	if _blackout == null or _prompt_label == null:
		return false
	for index in range(_objects.size()):
		var view := _objects[index] as TextureRect
		if view == null or view.texture == null:
			return false
		if str(view.get_meta("name_tag", "")) != str(OBJECT_SPECS[index]["name_tag"]):
			return false
		if view.texture.get_size().x <= 0.0 or view.texture.get_size().y <= 0.0:
			return false
	# 手势侧必须是 b198616 原样搬来的那套运行时，不是本地重写的替身。
	for runtime_path in [
		"res://levels/minigames/fan_camera_bridge.gd",
		"res://levels/minigames/fan_camera_bridge.py",
		"res://levels/minigames/fan_runtime/interference_field.py",
		"res://levels/minigames/hand_landmarker.task",
	]:
		if not FileAccess.file_exists(runtime_path):
			return false
	return true


func get_debug_snapshot() -> Dictionary:
	return {
		"inner_stage_scene": SCENE_NAME,
		"inner_stage_active": is_active(),
		"inner_stage_visible": visible,
		"inner_stage_phase": Phase.keys()[_phase],
		"inner_object_count": _objects.size(),
		"inner_object_name_tags": name_tags(),
		"inner_objects_revealed": _revealed_count,
		"inner_fan_arm_source": FAN_ARM_SOURCE,
		"inner_fan_bridge_attached": _camera_bridge != null,
		"inner_fan_camera_state": _camera_state,
		"inner_fan_physics_frame_seen": _physics_frame_seen,
		"inner_fan_dispersed_ratio": _dispersed_ratio,
		"inner_objects_cleared_count": _cleared_count,
		"inner_cutscene_blur_radius": CUTSCENE_BLUR_RADIUS,
	}
