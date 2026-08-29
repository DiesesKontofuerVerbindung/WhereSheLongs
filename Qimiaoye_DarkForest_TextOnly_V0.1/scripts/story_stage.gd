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
const WaterfallBackTexture := preload("res://assets/backgrounds/forest_waterfall/waterfall_back.jpg")
const WaterfallFrontTexture := preload("res://assets/backgrounds/forest_waterfall/waterfall_front.png")
const WaterfallParticlesTexture := preload("res://assets/backgrounds/forest_waterfall/waterfall_particles.png")
const LakeBackTexture := preload("res://assets/backgrounds/lake/lake_back.jpg")
const LakeFrontTexture := preload("res://assets/backgrounds/lake/lake_front.png")
const LakeParticlesTexture := preload("res://assets/backgrounds/lake/lake_particles.png")

const STAGE_SCENES := ["环境背景图1", "环境背景图2", "环境背景图3", "环境背景图4"]
# 神秘湖是与森林-瀑布长场景互不相连的独立世界，单独滚动、单独布局。
const LAKE_SCENES := ["环境背景图6"]
const XIAOLING_START_RATIO := 0.16
const LIGHT_TRIGGER_RATIO := 0.66
const AMAI_FACE_RATIO := 0.78
# 人物使用真实脚底作原点，并踩在连续森林地表上；对白 UI 独立覆盖在舞台之上。
const ACTOR_GROUND_RATIO := 0.84
const ACTOR_MARGIN := 112.0
const XIAOLING_VISUAL_SCALE := 0.28
const AMAI_VISUAL_SCALE := 0.34
# 模糊按 DOCX 行号分三档：开头–124、125–162、163–结尾；阿麦进入 story 模式后
# 用 amai_story_blur 预渲染透明 PNG 序列替代 shader 实时模糊（见 set_story_art_stage）。
const GAUSSIAN_BLUR_STAGE_2_SOURCE := 125
const GAUSSIAN_BLUR_STAGE_3_SOURCE := 163
const XIAOLING_GAUSSIAN_BLUR_STRENGTH := 0.98
const XIAOLING_GAUSSIAN_BLUR_MIDDLE := 0.75
const XIAOLING_GAUSSIAN_BLUR_LATE := 0.0
const AMAI_GAUSSIAN_BLUR_STRENGTH := 0.0
const AMAI_GAUSSIAN_BLUR_MIDDLE := 0.75
const AMAI_GAUSSIAN_BLUR_LATE := 0.98
# 两套角色原图均以画布中心为 Sprite2D 原点；以下数值来自首帧非透明像素脚底。
const XIAOLING_FOOT_FROM_CENTER := 558.0
const AMAI_FOOT_FROM_CENTER := 545.0
# 阿麦 idle_001 源图：暖黄核心 y=606、脚底 y=1185，垂直距离为579px。
const AMAI_HEART_FROM_FEET := 579.0
const HEART_GLOW_COLOR := Color(1.0, 0.72, 0.20, 1.0)
# 世界根节点为 -20：后景最终为 -20，前景最终为 -16，人物必须夹在二者之间。
const ACTOR_LAYER_Z := -17
const LIGHT_WALK_SPEED := 190.0
const MANUAL_WALK_SPEED := 205.0
# 阿麦在光源熄灭后不再瞬间出现，而是从全透明淡入。
const AMAI_FADE_IN_SECONDS := 0.9
const PROMPT_LIGHT := "将鼠标持续停留在右侧光源"
const FOREST_SOURCE_SIZE := Vector2(9342.0, 1440.0)
const WATERFALL_SOURCE_SIZE := Vector2(2560.0, 1440.0)
const WATERFALL_SOURCE_X := FOREST_SOURCE_SIZE.x
const CONTINUOUS_WORLD_SOURCE_SIZE := Vector2(11902.0, 1440.0)
# 瀑布前的可站立地形沿画面向右上抬升；人物终点位于瀑布水体左侧。
const WATERFALL_SLOPE_START_RATIO := Vector2(0.22, 0.74)
const WATERFALL_SLOPE_END_RATIO := Vector2(0.56, 0.66)
const WATERFALL_XIAOLING_STOP_RATIO := 0.34
const WATERFALL_AMAI_STOP_RATIO := 0.50
const LIGHT_SOURCE_POSITION := Vector2(2534.0, 720.0)
const LAKE_SOURCE_SIZE := Vector2(6117.0, 1440.0)
# 湖岸比森林地表更靠近画面下沿；人物脚底踩在近岸滩地而不是水面。
const LAKE_GROUND_RATIO := 0.86
const LAKE_XIAOLING_START_RATIO := 0.22
const LAKE_AMAI_START_RATIO := 0.40
const LAKE_AMAI_SHORE_RATIO := 0.72
# 阿麦锚定到湖面世界坐标后会随卷动左移，卷动量必须留住他不出画：
# 1778px 可卷距离 × 0.225 ≈ 400px，阿麦从 0.72 落到约 0.41，仍在画面内。
const LAKE_SCROLL_CEILING := 0.225
# 接近距离主要交给镜头推进，小凌自己只走一小段，否则会越过站在岸边的阿麦。
const LAKE_XIAOLING_TRIGGER_MAX_RATIO := 0.30
const SCENE_SCROLL_RATIOS := {
	"环境背景图1": 0.0,
	"环境背景图2": 0.225,
	"环境背景图3": 0.472,
	"环境背景图4": 1.0,
}
const CONTINUOUS_TRAVEL_SECONDS := {
	"FIREFLY_GUIDE": 2.4,
	"WALK_CONTINUE": 3.2,
	"FOREST_RUN_EXIT": 2.8,
}
const CONTINUOUS_TRAVEL_SPEEDS := {
	"FIREFLY_GUIDE": Vector2(190.0, 175.0),
	"WALK_CONTINUE": Vector2(205.0, 190.0),
	"FOREST_RUN_EXIT": Vector2(315.0, 270.0),
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
var _lake_scale := 0.5
var _lake_scroll_ratio := 0.0
var _amai_fade_tween: Tween
var _manual_follow_drives_amai := false
## 阿麦不是 _lake_root 的子节点，湖面卷动时他会钉在屏幕上相对湖面滑行。
## 锚定后按 _lake_root 的位移同步他的屏幕坐标，等价于把他放进湖面世界。
var _lake_amai_anchored := false
var _lake_amai_anchor_x := 0.0
var _blur_stage := 0
var _last_continuous_transition := ""
var _last_continuous_transition_duration := 0.0
var _last_continuous_transition_ran_actors := false

var _world_root: Node2D
var _forest_back: Sprite2D
var _forest_front: Sprite2D
var _entry_curtain: Sprite2D
var _amai_light_art: Sprite2D
var _forest_particles: Sprite2D
var _waterfall_back: Sprite2D
var _waterfall_front: Sprite2D
var _waterfall_particles: Sprite2D
var _lake_root: Node2D
var _lake_back: Sprite2D
var _lake_front: Sprite2D
var _lake_particles: Sprite2D
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
	_world_root.name = "ForestToWaterfallContinuousWorld"
	_world_root.z_index = -20
	add_child(_world_root)

	_forest_back = _make_world_layer("ForestBack", ForestBackTexture, 0)
	_entry_curtain = _make_world_layer("ForestEntryCurtain", ForestEntryCurtainTexture, 1)
	_amai_light_art = _make_world_layer("ForestAmaiLight", ForestAmaiLightTexture, 2)
	_forest_front = _make_world_layer("ForestFront", ForestFrontTexture, 4)
	_forest_particles = _make_world_layer("ForestParticles", ForestParticlesTexture, 5)
	_forest_particles.visible = false

	_waterfall_back = _make_world_layer("WaterfallBack", WaterfallBackTexture, 0)
	_waterfall_front = _make_world_layer("WaterfallFront", WaterfallFrontTexture, 4)
	_waterfall_particles = _make_world_layer("WaterfallParticles", WaterfallParticlesTexture, 5)
	for waterfall_layer in [_waterfall_back, _waterfall_front, _waterfall_particles]:
		waterfall_layer.position.x = WATERFALL_SOURCE_X

	_build_lake_scene()

	_world_dark_overlay = ColorRect.new()
	_world_dark_overlay.name = "LongSceneDarknessOverlay"
	_world_dark_overlay.color = Color.BLACK
	_world_dark_overlay.modulate.a = 0.0
	_world_dark_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world_dark_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 只压暗森林和角色所在的舞台底层，旁白/对白 UI 保持清晰可读。
	_world_dark_overlay.z_index = -10
	add_child(_world_dark_overlay)


func _build_lake_scene() -> void:
	_lake_root = Node2D.new()
	_lake_root.name = "MysteriousLakeWorld"
	_lake_root.z_index = -20
	_lake_root.visible = false
	add_child(_lake_root)

	_lake_back = _make_layer(_lake_root, "LakeBack", LakeBackTexture, 0)
	_lake_front = _make_layer(_lake_root, "LakeFront", LakeFrontTexture, 4)
	_lake_particles = _make_layer(_lake_root, "LakeParticles", LakeParticlesTexture, 5)


func _make_world_layer(layer_name: String, texture: Texture2D, layer_z: int) -> Sprite2D:
	return _make_layer(_world_root, layer_name, texture, layer_z)


func _make_layer(parent: Node2D, layer_name: String, texture: Texture2D, layer_z: int) -> Sprite2D:
	var layer := Sprite2D.new()
	layer.name = layer_name
	layer.texture = texture
	layer.centered = false
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.z_index = layer_z
	parent.add_child(layer)
	return layer


func _build_characters() -> void:
	_xiaoling = CharacterBody2D.new()
	_xiaoling.name = "StoryXiaoling"
	_xiaoling.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_xiaoling.z_index = ACTOR_LAYER_Z
	add_child(_xiaoling)
	_xiaoling_visual = XiaolingVisualScene.instantiate() as AnimatedSprite2D
	_xiaoling_visual.name = "StoryXiaolingVisual"
	_xiaoling_visual.scale = Vector2.ONE * XIAOLING_VISUAL_SCALE
	_xiaoling_visual.position = Vector2(0.0, -XIAOLING_FOOT_FROM_CENTER * XIAOLING_VISUAL_SCALE)
	_xiaoling_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_xiaoling_visual.material = _make_blur_material(XIAOLING_GAUSSIAN_BLUR_STRENGTH)
	_xiaoling.add_child(_xiaoling_visual)

	_amai = CharacterBody2D.new()
	_amai.name = "StoryAmai"
	_amai.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_amai.z_index = ACTOR_LAYER_Z
	add_child(_amai)
	_amai_visual = AmaiVisualScene.instantiate() as AnimatedSprite2D
	_amai_visual.name = "StoryAmaiVisual"
	_amai_visual.scale = Vector2.ONE * AMAI_VISUAL_SCALE
	_amai_visual.position = Vector2(0.0, -AMAI_FOOT_FROM_CENTER * AMAI_VISUAL_SCALE)
	_amai_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# 阿麦必须持有自己的一份 ShaderMaterial，两人共用实例会让模糊互相串改。
	_amai_visual.material = _make_blur_material(AMAI_GAUSSIAN_BLUR_STRENGTH)
	_amai.add_child(_amai_visual)
	_amai.visible = false


func _make_blur_material(strength: float) -> ShaderMaterial:
	var blur_shader := Shader.new()
	blur_shader.code = """
shader_type canvas_item;

uniform float blur_strength : hint_range(0.0, 1.0) = 0.90;

void fragment() {
	vec2 offset = TEXTURE_PIXEL_SIZE * (blur_strength * 32.0);
	vec4 blurred = texture(TEXTURE, UV) * 0.25;
	blurred += texture(TEXTURE, UV + vec2(offset.x, 0.0)) * 0.125;
	blurred += texture(TEXTURE, UV - vec2(offset.x, 0.0)) * 0.125;
	blurred += texture(TEXTURE, UV + vec2(0.0, offset.y)) * 0.125;
	blurred += texture(TEXTURE, UV - vec2(0.0, offset.y)) * 0.125;
	blurred += texture(TEXTURE, UV + offset) * 0.0625;
	blurred += texture(TEXTURE, UV - offset) * 0.0625;
	blurred += texture(TEXTURE, UV + vec2(offset.x, -offset.y)) * 0.0625;
	blurred += texture(TEXTURE, UV + vec2(-offset.x, offset.y)) * 0.0625;
	COLOR = blurred * COLOR;
}
"""
	var blur_material := ShaderMaterial.new()
	blur_material.shader = blur_shader
	blur_material.set_shader_parameter("blur_strength", strength)
	return blur_material


## 模糊按 DOCX 行号分三档：开头–124、125–162、163–结尾。
func sync_blur_for_source(source: int) -> void:
	var stage := 0
	if source >= GAUSSIAN_BLUR_STAGE_3_SOURCE:
		stage = 2
	elif source >= GAUSSIAN_BLUR_STAGE_2_SOURCE:
		stage = 1
	set_blur_stage(stage)


func set_blur_stage(stage: int) -> void:
	var next_stage := clampi(stage, 0, 2)
	if next_stage == _blur_stage:
		return
	_blur_stage = next_stage
	if _amai_visual != null and _amai_visual.has_method("set_story_art_stage"):
		_amai_visual.call("set_story_art_stage", _blur_stage)
	_apply_blur_strength(_xiaoling_visual, expected_blur_strength(_xiaoling_visual))
	_apply_blur_strength(_amai_visual, expected_blur_strength(_amai_visual))


func expected_blur_strength(visual: AnimatedSprite2D) -> float:
	if visual == _amai_visual:
		return [AMAI_GAUSSIAN_BLUR_STRENGTH, AMAI_GAUSSIAN_BLUR_MIDDLE, AMAI_GAUSSIAN_BLUR_LATE][_blur_stage]
	return [XIAOLING_GAUSSIAN_BLUR_STRENGTH, XIAOLING_GAUSSIAN_BLUR_MIDDLE, XIAOLING_GAUSSIAN_BLUR_LATE][_blur_stage]


func _apply_blur_strength(visual: AnimatedSprite2D, strength: float) -> void:
	if visual == null:
		return
	var blur_material := visual.material as ShaderMaterial
	if blur_material != null:
		blur_material.set_shader_parameter("blur_strength", strength)


func current_blur_strength(visual: AnimatedSprite2D) -> float:
	if visual == null:
		return -1.0
	var blur_material := visual.material as ShaderMaterial
	if blur_material == null:
		return -1.0
	return float(blur_material.get_shader_parameter("blur_strength"))


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
	_world_scale = size.y / CONTINUOUS_WORLD_SOURCE_SIZE.y
	_world_root.scale = Vector2(_world_scale, _world_scale)
	_apply_world_scroll_ratio(_world_scroll_ratio)
	_layout_lake_scene()


func _layout_lake_scene() -> void:
	if _lake_root == null:
		return
	_lake_scale = size.y / LAKE_SOURCE_SIZE.y
	_lake_root.scale = Vector2(_lake_scale, _lake_scale)
	_apply_lake_scroll_ratio(_lake_scroll_ratio)


func _apply_lake_scroll_ratio(scroll_ratio: float) -> void:
	_lake_scroll_ratio = clampf(scroll_ratio, 0.0, 1.0)
	if _lake_root == null:
		return
	var scaled_width := LAKE_SOURCE_SIZE.x * _lake_scale
	var max_scroll := maxf(0.0, scaled_width - size.x)
	_lake_root.position = Vector2(-max_scroll * _lake_scroll_ratio, 0.0)
	if _lake_amai_anchored and _amai != null:
		_amai.position.x = _lake_amai_anchor_x + _lake_root.position.x


func _process(delta: float) -> void:
	_phase += delta
	if _heart_glow_visible:
		queue_redraw()
	_advance_light_interaction(delta)


func _draw() -> void:
	if not visible:
		return
	if _heart_glow_visible and _amai != null and _amai.visible:
		var heart_position := _amai_heart_position()
		var pulse := 1.0 + sin(_phase * 2.2) * 0.07
		for ring in range(7, 0, -1):
			var radius := (16.0 + float(ring) * 13.0) * pulse
			draw_circle(heart_position, radius, Color(HEART_GLOW_COLOR.r, HEART_GLOW_COLOR.g, HEART_GLOW_COLOR.b, 0.018 * float(8 - ring)))
		draw_circle(heart_position, 10.0 * pulse, Color(1.0, 0.88, 0.42, 0.94))


func set_scene(scene_name: String, instant_scroll := false) -> void:
	var changed := scene_name != _current_scene
	_current_scene = scene_name
	visible = uses_art_stage(scene_name)
	_sync_active_world(scene_name)
	if not visible:
		hide_control_prompt()
		return
	if uses_lake_stage(scene_name):
		if changed:
			_enter_lake_scene()
		queue_redraw()
		return
	_scroll_long_scene_to(scene_name, instant_scroll)
	if scene_name == "环境背景图1" and changed:
		_reset_for_light_approach()
	elif scene_name == "环境背景图4" and changed:
		_place_actors_before_waterfall()
		_xiaoling.visible = true
		_amai.visible = true
		_set_facing(_xiaoling_visual, true)
		_set_facing(_amai_visual, false)
		_stop_actor("小凌")
		_stop_actor("阿麦")
	queue_redraw()


func uses_continuous_forest(scene_name: String) -> bool:
	return scene_name in STAGE_SCENES


func uses_lake_stage(scene_name: String) -> bool:
	return scene_name in LAKE_SCENES


# 任何拥有实拍美术底图的舞台；主场景据此隐藏黑底占位场景名。
func uses_art_stage(scene_name: String) -> bool:
	return uses_continuous_forest(scene_name) or uses_lake_stage(scene_name)


func _sync_active_world(scene_name: String) -> void:
	var lake_active := uses_lake_stage(scene_name)
	if _world_root != null:
		_world_root.visible = not lake_active
	if _lake_root != null:
		_lake_root.visible = lake_active


func _current_ground_ratio() -> float:
	return LAKE_GROUND_RATIO if uses_lake_stage(_current_scene) else ACTOR_GROUND_RATIO


func _enter_lake_scene() -> void:
	_cancel_all_actor_tweens()
	_lake_amai_anchored = false
	_apply_lake_scroll_ratio(0.0)
	_light_visible = false
	_heart_glow_visible = false
	_light_interaction_active = false
	_light_hovered = false
	if _light_hover_area != null:
		_light_hover_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_darkness_level(0.0)
	_set_actor_ratio(_xiaoling, LAKE_XIAOLING_START_RATIO)
	_set_actor_ratio(_amai, LAKE_AMAI_START_RATIO)
	_xiaoling.visible = true
	_amai.visible = true
	_xiaoling.modulate = Color.WHITE
	_amai.modulate = Color.WHITE
	_set_facing(_xiaoling_visual, true)
	_set_facing(_amai_visual, true)


func travel_to_scene(scene_name: String, transition_id: String, verify_mode: bool) -> void:
	if not uses_continuous_forest(scene_name):
		set_scene(scene_name, verify_mode)
		return
	var target_ratio := clampf(float(SCENE_SCROLL_RATIOS.get(scene_name, _world_scroll_ratio)), 0.0, 1.0)
	var configured_duration := float(CONTINUOUS_TRAVEL_SECONDS.get(transition_id, 2.6))
	var duration := 0.012 if verify_mode else configured_duration
	var speeds: Vector2 = CONTINUOUS_TRAVEL_SPEEDS.get(transition_id, Vector2(210.0, 195.0))
	_cancel_all_actor_tweens()
	if _world_scroll_tween != null and _world_scroll_tween.is_running():
		_world_scroll_tween.kill()
	_current_scene = scene_name
	visible = true
	_xiaoling.visible = true
	_amai.visible = true
	_set_facing(_xiaoling_visual, true)
	_set_facing(_amai_visual, true)
	_xiaoling.velocity = Vector2(speeds.x, 0.0)
	_amai.velocity = Vector2(speeds.y, 0.0)
	_play_actor_motion_animation(_amai, speeds.y)
	_last_continuous_transition = transition_id
	_last_continuous_transition_duration = configured_duration
	_last_continuous_transition_ran_actors = true
	_world_scroll_tween = create_tween()
	_world_scroll_tween.set_trans(Tween.TRANS_SINE)
	_world_scroll_tween.set_ease(Tween.EASE_IN_OUT)
	_world_scroll_tween.tween_method(_apply_world_scroll_ratio, _world_scroll_ratio, target_ratio, duration)
	if scene_name == "环境背景图4":
		_world_scroll_tween.parallel().tween_property(
			_xiaoling,
			"position",
			_waterfall_actor_position(WATERFALL_XIAOLING_STOP_RATIO),
			duration
		)
		_world_scroll_tween.parallel().tween_property(
			_amai,
			"position",
			_waterfall_actor_position(WATERFALL_AMAI_STOP_RATIO),
			duration
		)
	await _world_scroll_tween.finished
	if scene_name == "环境背景图4":
		_place_actors_before_waterfall()
	else:
		_stop_actor("小凌")
		_stop_actor("阿麦")
	_face_actors_toward_each_other()
	queue_redraw()


func prepare_dialogue(speaker: String) -> void:
	if not visible or speaker not in ["小凌", "阿麦"]:
		return
	_face_actors_toward_each_other()


func _face_actors_toward_each_other() -> void:
	if _xiaoling == null or _amai == null or not _xiaoling.visible or not _amai.visible:
		return
	var xiaoling_is_left := _xiaoling.position.x <= _amai.position.x
	_set_facing(_xiaoling_visual, xiaoling_is_left)
	_set_facing(_amai_visual, not xiaoling_is_left)


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
	var scaled_width := CONTINUOUS_WORLD_SOURCE_SIZE.x * _world_scale
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
			await _fade_in_amai(verify_mode)
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
			# DOCX 120 只收住上一拍，不再把小凌拉回阿麦左侧；121 的手动向右追赶仍独立执行。
			_stop_actor("小凌")
			_face_actors_toward_each_other()
		"xiaoling_look_back", "xiaoling_look_left":
			_set_facing(_xiaoling_visual, false)
		"amai_turn_back", "amai_look_xiaoling":
			_set_facing(_amai_visual, false)
		"amai_point_right":
			_set_facing(_amai_visual, true)
		"lake_approach":
			var tween := _start_actor_motion(_amai, LAKE_AMAI_SHORE_RATIO, 150.0, verify_mode)
			await tween.finished
			# DOCX 167 走到湖岸后回身对着小凌（朝左），不再背对她面湖。
			_set_facing(_amai_visual, false)
			# 走到位之后他就不再自己移动了，从这一刻起交给湖面卷动带。
			_anchor_amai_to_lake()
		"amai_turn_lake":
			_set_facing(_amai_visual, false)
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
			# 两条独立 tween 的 finished 先后触发时，先完成者会提前转向，随后仍在运行的
			# 位移或紧接的连续场景切换又把朝向改回。只在两人都完成后统一面对面。
			var amai_tween := _start_actor_motion(_amai, 0.84, 130.0, verify_mode)
			var xiaoling_tween := _start_actor_motion(_xiaoling, 0.68, 125.0, verify_mode)
			var pending := {"count": 2}
			var finish_pair := func() -> void:
				pending["count"] = int(pending["count"]) - 1
				if int(pending["count"]) == 0:
					_face_actors_toward_each_other()
			amai_tween.finished.connect(finish_pair)
			xiaoling_tween.finished.connect(finish_pair)
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
	# 基线是完全不透明；开发者跳转直接停在这里，只有正常流程才继续走淡入。
	_amai_fade_tween_kill()
	_amai.modulate.a = 1.0
	_set_facing(_xiaoling_visual, true)
	_set_facing(_amai_visual, false)
	set_darkness_level(0.80)
	hide_control_prompt()
	queue_redraw()


# 阿麦不再凭空出现：保留当前暗度对应的色调，只把不透明度从 0 淡入。
func _fade_in_amai(verify_mode: bool) -> void:
	if _amai == null:
		return
	_amai_fade_tween_kill()
	var lit := _amai.modulate
	_amai.modulate = Color(lit.r, lit.g, lit.b, 0.0)
	var duration := 0.012 if verify_mode else AMAI_FADE_IN_SECONDS
	_amai_fade_tween = create_tween()
	_amai_fade_tween.set_trans(Tween.TRANS_SINE)
	_amai_fade_tween.set_ease(Tween.EASE_OUT)
	_amai_fade_tween.tween_property(_amai, "modulate:a", lit.a, duration)
	await _amai_fade_tween.finished


func _amai_fade_tween_kill() -> void:
	if _amai_fade_tween != null and _amai_fade_tween.is_running():
		_amai_fade_tween.kill()


func set_darkness_level(level: float) -> void:
	_darkness_level = clampf(level, 0.0, 1.0)
	if _world_dark_overlay != null:
		_world_dark_overlay.modulate.a = _darkness_level
	var actor_brightness := lerpf(1.0, 0.42, _darkness_level)
	var actor_modulate := Color(actor_brightness, actor_brightness, actor_brightness, 1.0)
	if _xiaoling != null:
		_xiaoling.modulate = actor_modulate
	if _amai != null:
		# 调暗只改色调，不能把正在进行的淡入不透明度冲掉。
		_amai.modulate = Color(actor_modulate.r, actor_modulate.g, actor_modulate.b, _amai.modulate.a)


func update_manual_movement(direction: float, delta: float, movement_id: String) -> void:
	if not visible or _xiaoling == null:
		return
	if absf(direction) < 0.01:
		_xiaoling.velocity = Vector2.ZERO
		_release_manual_follow_amai()
		return
	_cancel_actor_tween("小凌")
	var min_x := size.x * 0.12
	var max_ratio := 0.78 if movement_id == "forest_run_entry" else 0.72
	if movement_id == "lake_trigger":
		max_ratio = LAKE_XIAOLING_TRIGGER_MAX_RATIO
	var max_x := size.x * max_ratio
	_xiaoling.velocity = Vector2(direction * MANUAL_WALK_SPEED, 0.0)
	_xiaoling.position.x = clampf(_xiaoling.position.x + _xiaoling.velocity.x * delta, min_x, max_x)
	_set_facing(_xiaoling_visual, direction > 0.0)
	if movement_id == "lake_trigger":
		_apply_lake_scroll_ratio(clampf(_lake_scroll_ratio + direction * delta * 0.055, 0.0, LAKE_SCROLL_CEILING))
		return
	if movement_id in ["follow_right", "forest_run_entry"]:
		var scroll_ceiling := 0.48 if movement_id == "follow_right" else 0.82
		var next_scroll := _world_scroll_ratio + direction * delta * 0.055
		_apply_world_scroll_ratio(clampf(next_scroll, 0.0, scroll_ceiling))
		# 阿麦在前方带路，屏幕位置不变但世界在卷动，相对地面其实一直在前进。
		# 不同步驱动 velocity 的话他会保持 idle 贴图贴着地面平移，看起来像漂移。
		_drive_manual_follow_amai(direction)


func _drive_manual_follow_amai(direction: float) -> void:
	# 有脚本 tween 在控制阿麦时不抢方向盘。
	if _amai == null or not _amai.visible or _actor_tweens.has("阿麦"):
		return
	_amai.velocity = Vector2(direction * MANUAL_WALK_SPEED, 0.0)
	_play_actor_motion_animation(_amai, direction)
	_manual_follow_drives_amai = true


func _anchor_amai_to_lake() -> void:
	if _amai == null or _lake_root == null:
		return
	_lake_amai_anchor_x = _amai.position.x - _lake_root.position.x
	_lake_amai_anchored = true


func _release_manual_follow_amai() -> void:
	if not _manual_follow_drives_amai:
		return
	_manual_follow_drives_amai = false
	if _amai != null and not _actor_tweens.has("阿麦"):
		_stop_actor("阿麦")


func finish_manual_movement(movement_id: String) -> void:
	if _xiaoling == null:
		return
	_release_manual_follow_amai()
	var stop_ratio := 0.72
	if movement_id == "forest_run_entry":
		stop_ratio = 0.78
	elif movement_id == "lake_trigger":
		stop_ratio = LAKE_XIAOLING_TRIGGER_MAX_RATIO
	_set_actor_ratio(_xiaoling, stop_ratio)
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
	visible = uses_art_stage(scene_name)
	_sync_active_world(scene_name)
	_cancel_all_actor_tweens()
	# 模糊是角色材质状态，与舞台是否可见无关，必须在提前 return 之前同步。
	sync_blur_for_source(source)
	if not visible:
		return
	if uses_lake_stage(scene_name):
		_enter_lake_scene()
		if source >= 167:
			_set_actor_ratio(_amai, LAKE_AMAI_SHORE_RATIO)
			_anchor_amai_to_lake()
			# 与 lake_approach 一致：167 走到岸边就已经转向小凌。
			_set_facing(_amai_visual, false)
		queue_redraw()
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
	if scene_name == "环境背景图4":
		_place_actors_before_waterfall()
		_face_actors_toward_each_other()
	elif source <= 51:
		_reset_for_light_approach()
		if source == 51:
			begin_light_interaction()
	elif source <= 58:
		_apply_light_trigger()
		set_darkness_level(0.80 if source <= 56 else 0.20)
		_heart_glow_visible = source >= 53
	elif source < 89:
		if source >= 88:
			# DOCX 88 两人走到岔路口后面对面。
			_set_actor_ratio(_xiaoling, 0.68)
			_set_actor_ratio(_amai, 0.84)
			_face_actors_toward_each_other()
		else:
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
	elif source == 120:
		# 直接回溯到 DOCX 120 时复原上一拍站位；正常流程不在此行移动小凌。
		_set_actor_ratio(_xiaoling, 0.68)
		_set_actor_ratio(_amai, 0.90)
		_face_actors_toward_each_other()
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
		_play_actor_motion_animation(actor, distance)
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
	if actor == _amai and _amai_visual != null and _amai_visual.has_method("play_scripted_idle"):
		_amai_visual.call("play_scripted_idle")


func _play_actor_motion_animation(actor: CharacterBody2D, horizontal_direction: float) -> void:
	if actor != _amai or _amai_visual == null or is_zero_approx(horizontal_direction):
		return
	if _amai_visual.has_method("play_scripted_run"):
		_amai_visual.call("play_scripted_run", horizontal_direction)


func _set_actor_ratio(actor: CharacterBody2D, ratio: float) -> void:
	if actor == null:
		return
	actor.position = Vector2(clampf(size.x * ratio, ACTOR_MARGIN, size.x - ACTOR_MARGIN), size.y * _current_ground_ratio())
	_stop_actor("小凌" if actor == _xiaoling else "阿麦")


func _waterfall_ground_y_for_ratio(x_ratio: float) -> float:
	var slope_progress := clampf(
		inverse_lerp(WATERFALL_SLOPE_START_RATIO.x, WATERFALL_SLOPE_END_RATIO.x, x_ratio),
		0.0,
		1.0
	)
	return size.y * lerpf(WATERFALL_SLOPE_START_RATIO.y, WATERFALL_SLOPE_END_RATIO.y, slope_progress)


func _waterfall_actor_position(x_ratio: float) -> Vector2:
	return Vector2(
		clampf(size.x * x_ratio, ACTOR_MARGIN, size.x - ACTOR_MARGIN),
		_waterfall_ground_y_for_ratio(x_ratio)
	)


func _place_actors_before_waterfall() -> void:
	if _xiaoling != null:
		_xiaoling.position = _waterfall_actor_position(WATERFALL_XIAOLING_STOP_RATIO)
		_stop_actor("小凌")
	if _amai != null:
		_amai.position = _waterfall_actor_position(WATERFALL_AMAI_STOP_RATIO)
		_stop_actor("阿麦")


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
		if texture == null or texture.get_size() != FOREST_SOURCE_SIZE:
			return false
	for texture in [WaterfallBackTexture, WaterfallFrontTexture, WaterfallParticlesTexture]:
		if texture == null or texture.get_size() != WATERFALL_SOURCE_SIZE:
			return false
	for waterfall_layer in [_waterfall_back, _waterfall_front, _waterfall_particles]:
		if waterfall_layer == null or not is_equal_approx(waterfall_layer.position.x, WATERFALL_SOURCE_X):
			return false
	if _lake_root == null or _lake_back == null or _lake_front == null or _lake_particles == null:
		return false
	for texture in [LakeBackTexture, LakeFrontTexture, LakeParticlesTexture]:
		if texture == null or texture.get_size() != LAKE_SOURCE_SIZE:
			return false
	var lake_back_final_z := _lake_root.z_index + _lake_back.z_index
	var lake_front_final_z := _lake_root.z_index + _lake_front.z_index
	if not lake_back_final_z < _xiaoling.z_index or not _xiaoling.z_index < lake_front_final_z:
		return false
	if _world_root.visible == _lake_root.visible:
		return false
	if _prompt_label == null or _prompt_label.text != PROMPT_LIGHT:
		return false
	if _light_hover_area.name != "IndependentLightHoverArea":
		return false
	if not _visual_has_motions(_xiaoling_visual, {"idle": 8, "run_start": 9, "run": 9}):
		return false
	# 阿麦在 story 模式(stage>0)会切到 amai_story_blur 预渲染序列(idle 151/run_start 19/run 25)，
	# 普通模式用基础动画(idle 60/run_start 21/run 14)；契约按当前激活的序列验证。
	if _amai_visual.has_method("get_story_art_stage") and int(_amai_visual.call("get_story_art_stage")) > 0:
		if not _visual_has_motions(_amai_visual, {"idle": 151, "run_start": 19, "run": 25}):
			return false
	else:
		if not _visual_has_motions(_amai_visual, {"idle": 60, "run_start": 21, "run": 14}):
			return false
	if not _amai_visual.has_method("play_scripted_run") or not _amai_visual.has_method("play_scripted_idle"):
		return false
	if not _amai_visual.has_method("verify_story_art_assets") or not bool(_amai_visual.call("verify_story_art_assets")):
		return false
	var back_final_z := _world_root.z_index + _forest_back.z_index
	var front_final_z := _world_root.z_index + _forest_front.z_index
	if not back_final_z < _xiaoling.z_index or not _xiaoling.z_index < front_final_z:
		return false
	var waterfall_back_final_z := _world_root.z_index + _waterfall_back.z_index
	var waterfall_front_final_z := _world_root.z_index + _waterfall_front.z_index
	if not waterfall_back_final_z < _xiaoling.z_index or not _xiaoling.z_index < waterfall_front_final_z:
		return false
	if _amai.z_index != _xiaoling.z_index:
		return false
	if not is_equal_approx(_xiaoling_visual.scale.x, XIAOLING_VISUAL_SCALE) or not is_equal_approx(_amai_visual.scale.x, AMAI_VISUAL_SCALE):
		return false
	# 模糊按 125 / 163 分三档，断言比对当前阶段值，不写死单一强度。
	# current_blur_strength 在没有 ShaderMaterial 时返回 -1.0，等价于同时检查材质存在。
	for blur_visual in [_xiaoling_visual, _amai_visual]:
		if not is_equal_approx(current_blur_strength(blur_visual), expected_blur_strength(blur_visual)):
			return false
	# 两人必须各自持有独立实例，否则改一个另一个跟着变。
	if _xiaoling_visual.material == _amai_visual.material:
		return false
	if absf(_actor_feet_y(_xiaoling, _xiaoling_visual, XIAOLING_FOOT_FROM_CENTER) - _xiaoling.position.y) > 0.5:
		return false
	if absf(_actor_feet_y(_amai, _amai_visual, AMAI_FOOT_FROM_CENTER) - _amai.position.y) > 0.5:
		return false
	if not WATERFALL_SLOPE_START_RATIO.x < WATERFALL_XIAOLING_STOP_RATIO:
		return false
	if not WATERFALL_XIAOLING_STOP_RATIO < WATERFALL_AMAI_STOP_RATIO:
		return false
	if not WATERFALL_AMAI_STOP_RATIO < WATERFALL_SLOPE_END_RATIO.x:
		return false
	if not WATERFALL_SLOPE_START_RATIO.y > WATERFALL_SLOPE_END_RATIO.y:
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


func _actor_feet_y(actor: CharacterBody2D, visual: AnimatedSprite2D, foot_from_center: float) -> float:
	if actor == null or visual == null:
		return 0.0
	return actor.position.y + visual.position.y + foot_from_center * visual.scale.y


func _amai_heart_position() -> Vector2:
	if _amai == null:
		return Vector2.ZERO
	return _amai.position + Vector2(0.0, -AMAI_HEART_FROM_FEET * AMAI_VISUAL_SCALE)


func get_debug_snapshot() -> Dictionary:
	return {
		"scene": _current_scene,
		"visible": visible,
		"light_visible": _light_visible,
		"heart_glow_visible": _heart_glow_visible,
		"heart_glow_x": _amai_heart_position().x,
		"heart_glow_y": _amai_heart_position().y,
		"amai_heart_from_feet_source": AMAI_HEART_FROM_FEET,
		"heart_glow_warm_yellow": HEART_GLOW_COLOR.r > HEART_GLOW_COLOR.b and HEART_GLOW_COLOR.g > HEART_GLOW_COLOR.b,
		"light_active": _light_interaction_active,
		"light_hovered": _light_hovered,
		"darkness": _darkness_level,
		"xiaoling_x": _xiaoling.position.x if _xiaoling != null else 0.0,
		"xiaoling_visible": _xiaoling.visible if _xiaoling != null else false,
		"xiaoling_animation": str(_xiaoling_visual.animation) if _xiaoling_visual != null else "",
		"xiaoling_facing_right": not _xiaoling_visual.flip_h if _xiaoling_visual != null else false,
		"xiaoling_z_index": _xiaoling.z_index if _xiaoling != null else 0,
		"xiaoling_visual_scale": _xiaoling_visual.scale.x if _xiaoling_visual != null else 0.0,
		"xiaoling_gaussian_blur_strength": current_blur_strength(_xiaoling_visual),
		"amai_gaussian_blur_strength": current_blur_strength(_amai_visual),
		"gaussian_blur_stage": _blur_stage,
		"gaussian_blur_stage_2_source": GAUSSIAN_BLUR_STAGE_2_SOURCE,
		"gaussian_blur_stage_3_source": GAUSSIAN_BLUR_STAGE_3_SOURCE,
		"amai_story_art_stage": int(_amai_visual.call("get_story_art_stage")) if _amai_visual != null and _amai_visual.has_method("get_story_art_stage") else -1,
		"xiaoling_feet_y": _actor_feet_y(_xiaoling, _xiaoling_visual, XIAOLING_FOOT_FROM_CENTER),
		"amai_x": _amai.position.x if _amai != null else 0.0,
		"amai_visible": _amai.visible if _amai != null else false,
		"amai_animation": str(_amai_visual.animation) if _amai_visual != null else "",
		"amai_facing_right": not _amai_visual.flip_h if _amai_visual != null else false,
		"amai_z_index": _amai.z_index if _amai != null else 0,
		"amai_visual_scale": _amai_visual.scale.x if _amai_visual != null else 0.0,
		"amai_feet_y": _actor_feet_y(_amai, _amai_visual, AMAI_FOOT_FROM_CENTER),
		"actor_ground_ratio": ACTOR_GROUND_RATIO,
		"actor_ground_y": size.y * ACTOR_GROUND_RATIO,
		"stage_width": size.x,
		"long_scene_enabled": _world_root != null,
		"forest_source_size": FOREST_SOURCE_SIZE,
		"waterfall_source_size": WATERFALL_SOURCE_SIZE,
		"long_scene_source_size": CONTINUOUS_WORLD_SOURCE_SIZE,
		"world_scroll_ratio": _world_scroll_ratio,
		"world_scroll_x": -_world_root.position.x if _world_root != null else 0.0,
		"continuous_travel_seconds": CONTINUOUS_TRAVEL_SECONDS,
		"last_continuous_transition": _last_continuous_transition,
		"last_continuous_transition_duration": _last_continuous_transition_duration,
		"last_continuous_transition_ran_actors": _last_continuous_transition_ran_actors,
		"world_z_index": _world_root.z_index if _world_root != null else -100,
		"forest_back_z_index": (_world_root.z_index + _forest_back.z_index) if _world_root != null and _forest_back != null else -100,
		"forest_front_z_index": (_world_root.z_index + _forest_front.z_index) if _world_root != null and _forest_front != null else -100,
		"waterfall_back_z_index": (_world_root.z_index + _waterfall_back.z_index) if _world_root != null and _waterfall_back != null else -100,
		"waterfall_front_z_index": (_world_root.z_index + _waterfall_front.z_index) if _world_root != null and _waterfall_front != null else -100,
		"waterfall_particles_z_index": (_world_root.z_index + _waterfall_particles.z_index) if _world_root != null and _waterfall_particles != null else -100,
		"waterfall_anchor_source_x": _waterfall_back.position.x if _waterfall_back != null else -1.0,
		"waterfall_active": _current_scene == "环境背景图4",
		"waterfall_assets_loaded": _waterfall_back != null and _waterfall_front != null and _waterfall_particles != null,
		"waterfall_slope_start_ratio": WATERFALL_SLOPE_START_RATIO,
		"waterfall_slope_end_ratio": WATERFALL_SLOPE_END_RATIO,
		"waterfall_xiaoling_stop_ratio": WATERFALL_XIAOLING_STOP_RATIO,
		"waterfall_amai_stop_ratio": WATERFALL_AMAI_STOP_RATIO,
		"waterfall_slope_up_right": WATERFALL_SLOPE_START_RATIO.y > WATERFALL_SLOPE_END_RATIO.y,
		"waterfall_slope_gentle": WATERFALL_SLOPE_START_RATIO.y - WATERFALL_SLOPE_END_RATIO.y >= 0.04 and WATERFALL_SLOPE_START_RATIO.y - WATERFALL_SLOPE_END_RATIO.y <= 0.10,
		"waterfall_stop_before_fall": WATERFALL_AMAI_STOP_RATIO < WATERFALL_SLOPE_END_RATIO.x,
		"amai_alpha": _amai.modulate.a if _amai != null else 0.0,
		"amai_velocity_x": _amai.velocity.x if _amai != null else 0.0,
		"amai_fade_in_seconds": AMAI_FADE_IN_SECONDS,
		"lake_stage_ready": _lake_root != null and _lake_back != null and _lake_front != null and _lake_particles != null,
		"lake_source_width": LAKE_SOURCE_SIZE.x,
		"lake_source_height": LAKE_SOURCE_SIZE.y,
		"lake_layers": "back_front_particles",
		"lake_active": _lake_root.visible if _lake_root != null else false,
		"lake_world_exclusive": (_world_root != null and _lake_root != null and _world_root.visible != _lake_root.visible),
		"lake_actor_between_layers": (
			_lake_root != null
			and _xiaoling != null
			and _lake_root.z_index + _lake_back.z_index < _xiaoling.z_index
			and _xiaoling.z_index < _lake_root.z_index + _lake_front.z_index
		),
		"lake_scroll_ratio": _lake_scroll_ratio,
		"lake_ground_ratio": LAKE_GROUND_RATIO,
		"lake_amai_anchored": _lake_amai_anchored,
		"lake_amai_x": _amai.position.x if _amai != null else 0.0,
		"lake_scroll_ceiling": LAKE_SCROLL_CEILING,
		"lake_root_offset_x": _lake_root.position.x if _lake_root != null else 0.0,
		"world_width": CONTINUOUS_WORLD_SOURCE_SIZE.x * _world_scale,
		"entry_curtain_visible": _entry_curtain.visible if _entry_curtain != null else false,
		"particles_visible": _forest_particles.visible if _forest_particles != null else false,
		"darkness_z_index": _world_dark_overlay.z_index if _world_dark_overlay != null else 0,
	}
