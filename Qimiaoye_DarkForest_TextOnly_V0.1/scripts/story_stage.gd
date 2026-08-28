extends Control
class_name DarkForestStoryStage

signal light_progress_changed(progress: float)
signal light_reached

const AmaiVisualScene := preload("res://scenes/forest/parkour/characters/amai_parkour_visual.tscn")
const XiaolingVisualScene := preload("res://scenes/forest/parkour/characters/xiaoling_parkour_visual.tscn")
const ForestBackTexture := preload("res://assets/backgrounds/forest_before_waterfall/forest_back.png")
const ForestFrontTexture := preload("res://assets/backgrounds/forest_before_waterfall/forest_front.png")
const ForestEntryCurtainTexture := preload("res://assets/backgrounds/forest_before_waterfall/forest_entry_curtain.png")
const ForestAmaiLightTexture := preload("res://assets/backgrounds/forest_before_waterfall/forest_amai_light.png")
const ForestParticlesTexture := preload("res://assets/backgrounds/forest_before_waterfall/forest_particles.png")

const STAGE_SCENES := ["环境背景图1", "环境背景图2", "环境背景图3", "环境背景图4"]
const XIAOLING_START_RATIO := 0.16
const LIGHT_TRIGGER_RATIO := 0.66
const AMAI_FACE_RATIO := 0.78
# 人物脚位必须停在底部对白框上沿之上，避免持续舞台穿进对白 UI。
const ACTOR_GROUND_RATIO := 0.60
const ACTOR_MARGIN := 78.0
const LIGHT_WALK_SPEED := 190.0
const MANUAL_WALK_SPEED := 205.0
const PROMPT_LIGHT := "将鼠标持续停留在右侧光源"
const LONG_SCENE_SOURCE_SIZE := Vector2(9342.0, 1440.0)
const LIGHT_SOURCE_POSITION := Vector2(2534.0, 720.0)
const SCENE_SCROLL_RATIOS := {
	"环境背景图1": 0.0,
	"环境背景图2": 0.31,
	"环境背景图3": 0.65,
	"环境背景图4": 1.0,
}

var _current_scene := "环境背景图0"
var _phase := 0.0
var _darkness_level := 0.0
var _light_visible := false
var _heart_glow_visible := false
var _light_interaction_active := false
var _light_hovered := false
var _light_reached_once := false
var _actor_tweens: Dictionary = {}
var _world_scale := 0.5
var _world_scroll_ratio := 0.0
var _world_scroll_tween: Tween

var _world_root: Node2D
var _forest_back: Sprite2D
var _forest_front: Sprite2D
var _entry_curtain: Sprite2D
var _amai_light_art: Sprite2D
var _forest_particles: Sprite2D
var _world_dark_overlay: ColorRect
var _xiaoling: CharacterBody2D
var _amai: CharacterBody2D
var _xiaoling_visual: AnimatedSprite2D
var _amai_visual: AnimatedSprite2D
var _light_hover_area: Control
var _prompt_panel: PanelContainer
var _prompt_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_long_scene()
	_build_characters()
	_build_light_hover_area()
	_build_prompt()
	resized.connect(_layout_stage)
	_layout_stage()
	visible = false


func _build_long_scene() -> void:
	_world_root = Node2D.new()
	_world_root.name = "ForestBeforeWaterfallLongScene"
	_world_root.z_index = -20
	add_child(_world_root)

	_forest_back = _make_world_layer("ForestBack", ForestBackTexture, 0)
	_entry_curtain = _make_world_layer("ForestEntryCurtain", ForestEntryCurtainTexture, 1)
	_amai_light_art = _make_world_layer("ForestAmaiLight", ForestAmaiLightTexture, 2)
	_forest_front = _make_world_layer("ForestFront", ForestFrontTexture, 4)
	_forest_particles = _make_world_layer("ForestParticles", ForestParticlesTexture, 5)
	_forest_particles.visible = false

	_world_dark_overlay = ColorRect.new()
	_world_dark_overlay.name = "LongSceneDarknessOverlay"
	_world_dark_overlay.color = Color.BLACK
	_world_dark_overlay.modulate.a = 0.0
	_world_dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 只压暗森林和角色所在的舞台底层，旁白/对白 UI 保持清晰可读。
	_world_dark_overlay.z_index = -10
	add_child(_world_dark_overlay)


func _make_world_layer(layer_name: String, texture: Texture2D, layer_z: int) -> Sprite2D:
	var layer := Sprite2D.new()
	layer.name = layer_name
	layer.texture = texture
	layer.centered = false
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.z_index = layer_z
	_world_root.add_child(layer)
	return layer


func _build_characters() -> void:
	_xiaoling = CharacterBody2D.new()
	_xiaoling.name = "StoryXiaoling"
	_xiaoling.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_xiaoling.z_index = 8
	add_child(_xiaoling)
	_xiaoling_visual = XiaolingVisualScene.instantiate() as AnimatedSprite2D
	_xiaoling_visual.name = "StoryXiaolingVisual"
	_xiaoling_visual.scale = Vector2(0.125, 0.125)
	_xiaoling_visual.position = Vector2(0.0, -20.0)
	_xiaoling_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_xiaoling.add_child(_xiaoling_visual)

	_amai = CharacterBody2D.new()
	_amai.name = "StoryAmai"
	_amai.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_amai.z_index = 8
	add_child(_amai)
	_amai_visual = AmaiVisualScene.instantiate() as AnimatedSprite2D
	_amai_visual.name = "StoryAmaiVisual"
	_amai_visual.scale = Vector2(0.125, 0.125)
	_amai_visual.position = Vector2(0.0, -20.0)
	_amai_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_amai.add_child(_amai_visual)
	_amai.visible = false


func _build_light_hover_area() -> void:
	_light_hover_area = Control.new()
	_light_hover_area.name = "IndependentLightHoverArea"
	_light_hover_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_light_hover_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_light_hover_area.mouse_entered.connect(_on_light_mouse_entered)
	_light_hover_area.mouse_exited.connect(_on_light_mouse_exited)
	add_child(_light_hover_area)


func _build_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "StoryStagePrompt"
	_prompt_panel.offset_left = 22.0
	_prompt_panel.offset_top = 54.0
	_prompt_panel.offset_right = 390.0
	_prompt_panel.offset_bottom = 98.0
	_prompt_panel.z_index = 20
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.052, 0.88)
	style.border_color = Color(0.48, 0.72, 0.86, 0.40)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	_prompt_panel.add_theme_stylebox_override("panel", style)
	add_child(_prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.text = PROMPT_LIGHT
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color("dce7f2"))
	_prompt_panel.add_child(_prompt_label)
	_prompt_panel.visible = false


func _layout_stage() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	_layout_long_scene()
	var ground_y := size.y * ACTOR_GROUND_RATIO
	if _xiaoling != null and _xiaoling.position == Vector2.ZERO:
		_xiaoling.position = Vector2(size.x * XIAOLING_START_RATIO, ground_y)
	if _amai != null and _amai.position == Vector2.ZERO:
		_amai.position = Vector2(size.x * AMAI_FACE_RATIO, ground_y)
	if _light_hover_area != null:
		var light_position := _light_position()
		_light_hover_area.position = light_position - Vector2(112.0, 112.0)
		_light_hover_area.size = Vector2(224.0, 224.0)


func _layout_long_scene() -> void:
	if _world_root == null:
		return
	_world_scale = size.y / LONG_SCENE_SOURCE_SIZE.y
	_world_root.scale = Vector2(_world_scale, _world_scale)
	_apply_world_scroll_ratio(_world_scroll_ratio)


func _process(delta: float) -> void:
	_phase += delta
	if _heart_glow_visible:
		queue_redraw()
	_advance_light_interaction(delta)


func _draw() -> void:
	if not visible:
		return
	if _heart_glow_visible and _amai != null and _amai.visible:
		var heart_position := _amai.position + Vector2(0.0, -72.0)
		var pulse := 1.0 + sin(_phase * 2.2) * 0.07
		for ring in range(7, 0, -1):
			var radius := (16.0 + float(ring) * 13.0) * pulse
			draw_circle(heart_position, radius, Color(0.82, 0.65, 0.96, 0.020 * float(8 - ring)))
		draw_circle(heart_position, 10.0 * pulse, Color(0.94, 0.84, 1.0, 0.90))


func set_scene(scene_name: String, instant_scroll := false) -> void:
	var changed := scene_name != _current_scene
	_current_scene = scene_name
	visible = scene_name in STAGE_SCENES
	if not visible:
		hide_control_prompt()
		return
	_scroll_long_scene_to(scene_name, instant_scroll)
	if scene_name == "环境背景图1" and changed:
		_reset_for_light_approach()
	elif scene_name == "环境背景图4" and changed:
		_set_actor_ratio(_xiaoling, 0.48)
		_set_actor_ratio(_amai, 0.64)
		_xiaoling.visible = true
		_amai.visible = true
		_set_facing(_xiaoling_visual, true)
		_set_facing(_amai_visual, false)
		_stop_actor("小凌")
		_stop_actor("阿麦")
	queue_redraw()


func uses_continuous_forest(scene_name: String) -> bool:
	return scene_name in STAGE_SCENES


func _scroll_long_scene_to(scene_name: String, instant: bool) -> void:
	var target_ratio := float(SCENE_SCROLL_RATIOS.get(scene_name, _world_scroll_ratio))
	target_ratio = clampf(target_ratio, 0.0, 1.0)
	if _world_scroll_tween != null and _world_scroll_tween.is_running():
		_world_scroll_tween.kill()
	if instant or is_equal_approx(target_ratio, _world_scroll_ratio):
		_apply_world_scroll_ratio(target_ratio)
		return
	_world_scroll_tween = create_tween()
	_world_scroll_tween.set_trans(Tween.TRANS_SINE)
	_world_scroll_tween.set_ease(Tween.EASE_IN_OUT)
	_world_scroll_tween.tween_method(_apply_world_scroll_ratio, _world_scroll_ratio, target_ratio, 0.95)


func _apply_world_scroll_ratio(scroll_ratio: float) -> void:
	_world_scroll_ratio = clampf(scroll_ratio, 0.0, 1.0)
	if _world_root == null:
		return
	var scaled_width := LONG_SCENE_SOURCE_SIZE.x * _world_scale
	var max_scroll := maxf(0.0, scaled_width - size.x)
	_world_root.position = Vector2(-max_scroll * _world_scroll_ratio, 0.0)
	if _light_hover_area != null:
		var light_position := _light_position()
		_light_hover_area.position = light_position - Vector2(112.0, 112.0)


func _reset_for_light_approach() -> void:
	_cancel_all_actor_tweens()
	_set_actor_ratio(_xiaoling, XIAOLING_START_RATIO)
	_set_actor_ratio(_amai, AMAI_FACE_RATIO)
	_xiaoling.visible = true
	_amai.visible = false
	_xiaoling.modulate = Color.WHITE
	_amai.modulate = Color.WHITE
	_set_facing(_xiaoling_visual, true)
	_set_facing(_amai_visual, false)
	_light_visible = true
	_heart_glow_visible = false
	_darkness_level = 0.0
	if _entry_curtain != null:
		_entry_curtain.visible = true
		_entry_curtain.modulate.a = 1.0
	if _amai_light_art != null:
		_amai_light_art.visible = true
	if _forest_particles != null:
		_forest_particles.visible = false
	if _world_dark_overlay != null:
		_world_dark_overlay.modulate.a = 0.0
	_light_interaction_active = false
	_light_hovered = false
	_light_reached_once = false
	if _light_hover_area != null:
		_light_hover_area.mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func begin_light_interaction() -> void:
	visible = true
	_xiaoling.visible = true
	_light_visible = true
	if _amai_light_art != null:
		_amai_light_art.visible = true
	_light_interaction_active = true
	_light_reached_once = false
	show_control_prompt(PROMPT_LIGHT)
	queue_redraw()


func _advance_light_interaction(delta: float) -> void:
	if not _light_interaction_active or _xiaoling == null:
		return
	if not _light_hovered:
		_xiaoling.velocity = Vector2.ZERO
		return
	var trigger_x := size.x * LIGHT_TRIGGER_RATIO
	_xiaoling.velocity = Vector2(LIGHT_WALK_SPEED, 0.0)
	_xiaoling.position.x = minf(trigger_x, _xiaoling.position.x + LIGHT_WALK_SPEED * delta)
	var start_x := size.x * XIAOLING_START_RATIO
	var progress := clampf(inverse_lerp(start_x, trigger_x, _xiaoling.position.x), 0.0, 1.0)
	light_progress_changed.emit(progress)
	if _xiaoling.position.x < trigger_x - 0.5:
		return
	_xiaoling.velocity = Vector2.ZERO
	_light_interaction_active = false
	_light_hovered = false
	hide_control_prompt()
	if not _light_reached_once:
		_light_reached_once = true
		light_reached.emit()


func _on_light_mouse_entered() -> void:
	if _light_interaction_active:
		_light_hovered = true


func _on_light_mouse_exited() -> void:
	_light_hovered = false
	if _xiaoling != null and not _actor_tweens.has("小凌"):
		_xiaoling.velocity = Vector2.ZERO


func play_action(action_id: String, verify_mode: bool) -> void:
	match action_id:
		"light_trigger":
			_apply_light_trigger()
		"heart_light":
			_heart_glow_visible = true
			queue_redraw()
		"xiaoling_back_two":
			var tween := _start_actor_motion_to_x(_xiaoling, _xiaoling.position.x - size.x * 0.09, 150.0, verify_mode)
			await tween.finished
			_set_facing(_xiaoling_visual, true)
			set_darkness_level(0.20)
		"amai_firefly_gesture":
			if _forest_particles != null:
				_forest_particles.visible = true
		"amai_walk_waypoint":
			var tween := _start_actor_motion(_amai, 0.84, 145.0, verify_mode)
			await tween.finished
		"amai_stop_idle":
			_stop_actor("阿麦")
		"amai_run_entry":
			var tween := _start_actor_motion(_amai, 0.90, 355.0, verify_mode)
			await tween.finished
		"xiaoling_run_follow":
			var tween := _start_actor_motion(_xiaoling, 0.59, 300.0, verify_mode)
			await tween.finished
		"xiaoling_look_back", "xiaoling_look_left":
			_set_facing(_xiaoling_visual, false)
		"amai_turn_back", "amai_look_xiaoling":
			_set_facing(_amai_visual, false)
		"amai_point_right":
			_set_facing(_amai_visual, true)
		_:
			pass


func play_line_cue(cue: String, verify_mode: bool) -> void:
	match cue:
		"amai_walk_waypoint":
			_start_actor_motion(_amai, 0.84, 145.0, verify_mode)
		"amai_walk_few_steps":
			var target_x := minf(size.x * 0.90, _amai.position.x + size.x * 0.10)
			_start_actor_motion_to_x(_amai, target_x, 135.0, verify_mode)
		"both_walk_to_fork":
			_start_actor_motion(_amai, 0.84, 130.0, verify_mode)
			_start_actor_motion(_xiaoling, 0.68, 125.0, verify_mode)
		"amai_run_ahead":
			_start_actor_motion(_amai, 0.90, 355.0, verify_mode)
		_:
			pass


func _apply_light_trigger() -> void:
	_light_visible = false
	if _amai_light_art != null:
		_amai_light_art.visible = false
	if _entry_curtain != null:
		_entry_curtain.visible = false
	_light_interaction_active = false
	_light_hovered = false
	_heart_glow_visible = false
	_set_actor_ratio(_xiaoling, LIGHT_TRIGGER_RATIO)
	_set_actor_ratio(_amai, AMAI_FACE_RATIO)
	_xiaoling.visible = true
	_amai.visible = true
	_set_facing(_xiaoling_visual, true)
	_set_facing(_amai_visual, false)
	set_darkness_level(0.80)
	hide_control_prompt()
	queue_redraw()


func set_darkness_level(level: float) -> void:
	_darkness_level = clampf(level, 0.0, 1.0)
	if _world_dark_overlay != null:
		_world_dark_overlay.modulate.a = _darkness_level
	var actor_brightness := lerpf(1.0, 0.42, _darkness_level)
	var actor_modulate := Color(actor_brightness, actor_brightness, actor_brightness, 1.0)
	if _xiaoling != null:
		_xiaoling.modulate = actor_modulate
	if _amai != null:
		_amai.modulate = actor_modulate


func update_manual_movement(direction: float, delta: float, movement_id: String) -> void:
	if not visible or _xiaoling == null:
		return
	if absf(direction) < 0.01:
		_xiaoling.velocity = Vector2.ZERO
		return
	_cancel_actor_tween("小凌")
	var min_x := size.x * 0.12
	var max_ratio := 0.78 if movement_id == "forest_run_entry" else 0.72
	var max_x := size.x * max_ratio
	_xiaoling.velocity = Vector2(direction * MANUAL_WALK_SPEED, 0.0)
	_xiaoling.position.x = clampf(_xiaoling.position.x + _xiaoling.velocity.x * delta, min_x, max_x)
	_set_facing(_xiaoling_visual, direction > 0.0)
	if movement_id in ["follow_right", "forest_run_entry"]:
		var scroll_ceiling := 0.48 if movement_id == "follow_right" else 0.82
		var next_scroll := _world_scroll_ratio + direction * delta * 0.055
		_apply_world_scroll_ratio(clampf(next_scroll, 0.0, scroll_ceiling))


func finish_manual_movement(movement_id: String) -> void:
	if _xiaoling == null:
		return
	_set_actor_ratio(_xiaoling, 0.78 if movement_id == "forest_run_entry" else 0.72)
	_xiaoling.velocity = Vector2.ZERO
	hide_control_prompt()


func show_control_prompt(text: String) -> void:
	if _prompt_label == null or _prompt_panel == null:
		return
	_prompt_label.text = text
	_prompt_panel.visible = true


func hide_control_prompt() -> void:
	if _prompt_panel != null:
		_prompt_panel.visible = false


func restore_for_source(source: int, scene_name: String) -> void:
	_current_scene = scene_name
	visible = scene_name in STAGE_SCENES
	_cancel_all_actor_tweens()
	if not visible:
		return
	_scroll_long_scene_to(scene_name, true)
	_xiaoling.visible = true
	_amai.visible = true
	_light_visible = false
	_heart_glow_visible = false
	_light_interaction_active = false
	_light_hovered = false
	if _amai_light_art != null:
		_amai_light_art.visible = false
	if _entry_curtain != null:
		_entry_curtain.visible = false
	if _forest_particles != null:
		_forest_particles.visible = source >= 58
	set_darkness_level(0.0)
	if source <= 51:
		_reset_for_light_approach()
		if source == 51:
			begin_light_interaction()
	elif source <= 58:
		_apply_light_trigger()
		set_darkness_level(0.80 if source <= 56 else 0.20)
		_heart_glow_visible = source >= 53
	elif source < 89:
		_set_actor_ratio(_xiaoling, 0.57 if source < 84 else 0.72)
		_set_actor_ratio(_amai, 0.84 if source < 77 else 0.90)
		_set_facing(_xiaoling_visual, true)
		_set_facing(_amai_visual, true)
		set_darkness_level(0.12)
	elif source < 117:
		_set_actor_ratio(_xiaoling, 0.62)
		_set_actor_ratio(_amai, 0.78)
		_set_facing(_xiaoling_visual, true)
		_set_facing(_amai_visual, false)
	else:
		_set_actor_ratio(_xiaoling, 0.78 if source >= 120 else 0.62)
		_set_actor_ratio(_amai, 0.90)
		_set_facing(_xiaoling_visual, true)
		_set_facing(_amai_visual, true)
	queue_redraw()


func debug_advance_light(delta: float, hovered: bool) -> void:
	_light_hovered = hovered
	_advance_light_interaction(delta)


func _start_actor_motion(actor: CharacterBody2D, target_ratio: float, speed: float, verify_mode: bool) -> Tween:
	return _start_actor_motion_to_x(actor, size.x * target_ratio, speed, verify_mode)


func _start_actor_motion_to_x(actor: CharacterBody2D, target_x: float, speed: float, verify_mode: bool) -> Tween:
	var actor_id := "小凌" if actor == _xiaoling else "阿麦"
	_cancel_actor_tween(actor_id)
	target_x = clampf(target_x, ACTOR_MARGIN, size.x - ACTOR_MARGIN)
	var distance := target_x - actor.position.x
	var duration := 0.012 if verify_mode else maxf(absf(distance) / maxf(speed, 1.0), 0.08)
	actor.velocity = Vector2(signf(distance) * speed if absf(distance) > 0.5 else 0.0, 0.0)
	if absf(distance) > 0.5:
		_set_facing(_xiaoling_visual if actor == _xiaoling else _amai_visual, distance > 0.0)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(actor, "position:x", target_x, duration)
	_actor_tweens[actor_id] = tween
	tween.finished.connect(func() -> void:
		if is_instance_valid(actor):
			actor.velocity = Vector2.ZERO
		if _actor_tweens.get(actor_id) == tween:
			_actor_tweens.erase(actor_id)
	)
	return tween


func _cancel_actor_tween(actor_id: String) -> void:
	var tween = _actor_tweens.get(actor_id)
	if tween is Tween and tween.is_running():
		tween.kill()
	_actor_tweens.erase(actor_id)


func _cancel_all_actor_tweens() -> void:
	_cancel_actor_tween("小凌")
	_cancel_actor_tween("阿麦")
	_stop_actor("小凌")
	_stop_actor("阿麦")


func _stop_actor(actor_id: String) -> void:
	var actor := _xiaoling if actor_id == "小凌" else _amai
	if actor != null:
		actor.velocity = Vector2.ZERO


func _set_actor_ratio(actor: CharacterBody2D, ratio: float) -> void:
	if actor == null:
		return
	actor.position = Vector2(clampf(size.x * ratio, ACTOR_MARGIN, size.x - ACTOR_MARGIN), size.y * ACTOR_GROUND_RATIO)
	actor.velocity = Vector2.ZERO


func _set_facing(visual: AnimatedSprite2D, facing_right: bool) -> void:
	if visual != null:
		visual.flip_h = not facing_right


func _light_position() -> Vector2:
	var world_offset := _world_root.position if _world_root != null else Vector2.ZERO
	return world_offset + LIGHT_SOURCE_POSITION * _world_scale


func verify_contract() -> bool:
	if _xiaoling == null or _amai == null or _light_hover_area == null or _world_root == null:
		return false
	for texture in [ForestBackTexture, ForestFrontTexture, ForestEntryCurtainTexture, ForestAmaiLightTexture, ForestParticlesTexture]:
		if texture == null or texture.get_size() != LONG_SCENE_SOURCE_SIZE:
			return false
	if _prompt_label == null or _prompt_label.text != PROMPT_LIGHT:
		return false
	if _light_hover_area.name != "IndependentLightHoverArea":
		return false
	if not _visual_has_motions(_xiaoling_visual, {"idle": 8, "run_start": 9, "run": 9}):
		return false
	if not _visual_has_motions(_amai_visual, {"idle": 60, "run_start": 21, "run": 14}):
		return false
	return LIGHT_TRIGGER_RATIO < AMAI_FACE_RATIO and AMAI_FACE_RATIO < 0.90 and SCENE_SCROLL_RATIOS.size() == STAGE_SCENES.size()


func _visual_has_motions(visual: AnimatedSprite2D, expected: Dictionary) -> bool:
	if visual == null or visual.sprite_frames == null:
		return false
	for animation_name in expected:
		var motion := StringName(animation_name)
		if not visual.sprite_frames.has_animation(motion):
			return false
		if visual.sprite_frames.get_frame_count(motion) < int(expected[animation_name]):
			return false
	return true


func get_debug_snapshot() -> Dictionary:
	return {
		"scene": _current_scene,
		"visible": visible,
		"light_visible": _light_visible,
		"heart_glow_visible": _heart_glow_visible,
		"light_active": _light_interaction_active,
		"light_hovered": _light_hovered,
		"darkness": _darkness_level,
		"xiaoling_x": _xiaoling.position.x if _xiaoling != null else 0.0,
		"xiaoling_visible": _xiaoling.visible if _xiaoling != null else false,
		"xiaoling_animation": str(_xiaoling_visual.animation) if _xiaoling_visual != null else "",
		"amai_x": _amai.position.x if _amai != null else 0.0,
		"amai_visible": _amai.visible if _amai != null else false,
		"amai_animation": str(_amai_visual.animation) if _amai_visual != null else "",
		"stage_width": size.x,
		"long_scene_enabled": _world_root != null,
		"long_scene_source_size": LONG_SCENE_SOURCE_SIZE,
		"world_scroll_ratio": _world_scroll_ratio,
		"world_scroll_x": -_world_root.position.x if _world_root != null else 0.0,
		"world_z_index": _world_root.z_index if _world_root != null else -100,
		"world_width": LONG_SCENE_SOURCE_SIZE.x * _world_scale,
		"entry_curtain_visible": _entry_curtain.visible if _entry_curtain != null else false,
		"particles_visible": _forest_particles.visible if _forest_particles != null else false,
		"darkness_z_index": _world_dark_overlay.z_index if _world_dark_overlay != null else 0,
	}
