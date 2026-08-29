extends Node2D

signal finished(result)

enum State { IDLE, CHARGING, JUMPING, FALLING, OVER }

const LightChildScene := preload("res://levels/light_child.tscn")
const RiverTex := preload("res://assets/backgrounds/river.jpg")
const RiverWaveShader := preload("res://assets/water_fallback.gdshader")
const StoneTextures := [
	preload("res://assets/stones/stone_a.png"),
	preload("res://assets/stones/stone_b.png"),
	preload("res://assets/stones/stone_c.png"),
]
const BlackKeyShader := preload("res://assets/black_key.gdshader")
const UiPanelSkinScript := preload("res://scripts/ui_panel_skin.gd")

const CHARGE_TIME := 0.85
const MIN_JUMP := 52.0
const MAX_JUMP := 340.0
const STONE_SCALE_MUL := 1.45
const Z_RIVER := -100
const Z_STONE := 0
const Z_REFLECTION := 40
const Z_FX := 55
const Z_TOP := 100
const FALL_GAMEOVER_TIME := 0.55
const HARD_MODE_JUMPS := 8

var _river_rotated := false
var _hard_mode := false

@onready var _hud: CanvasLayer = $HUD
@onready var _stones_root: Node2D = $Stones
@onready var _reflections: Node2D = $Reflections
@onready var _top_layer: Node2D = $TopLayer
@onready var _camera: Camera2D = $Camera2D
@onready var _score: Label = $HUD/Score
@onready var _hint: Label = $HUD/Hint
@onready var _best: Label = $HUD/Best
@onready var _charge_bar: ProgressBar = $HUD/ChargeBar
@onready var _back: Button = $HUD/Back

var _state: State = State.IDLE
var _held: bool = false
var _charge: float = 0.0
var _stones: Array[Dictionary] = []
var _current: int = 0
var _score_value: int = 0
var _perfects: int = 0
var _rng := RandomNumberGenerator.new()
var _player_pos := Vector2.ZERO
var _jump_from := Vector2.ZERO
var _jump_to := Vector2.ZERO
var _jump_t: float = 0.0
var _jump_dur: float = 0.4
var _arc: float = 80.0
var _height: float = 0.0
var _shake: float = 0.0
var _fall_t: float = 0.0
var _hint_life: float = 8.0
var _splash: CPUParticles2D
var _player: LightChild
var _reflection: LightChild
var _guide: LightChild
var _landed: int = 0
var _guide_from := Vector2.ZERO
var _guide_to := Vector2.ZERO
var _guide_hop: float = 1.0
var _guide_fade: float = 1.0
var _guide_leaving: bool = false
var _guide_hop_height: float = 0.0
var _video_sprite: Sprite2D


func setup(_scene_def: Dictionary) -> void:
	pass


func _ready() -> void:
	_rng.randomize()
	_apply_panel_skin()
	_back.pressed.connect(_on_back)
	_stones_root.z_index = Z_STONE
	_stones_root.z_as_relative = false
	_reflections.z_index = Z_REFLECTION
	_reflections.z_as_relative = false
	_top_layer.z_index = Z_TOP
	_top_layer.z_as_relative = false
	_setup_river_bg()
	_splash = _make_splash()
	add_child(_splash)
	_stones.append(_make_stone(Vector2.ZERO, 78.0))
	for _i in 8:
		_append_stone()
	_player_pos = _stones[0]["pos"]
	_camera.position = _player_pos
	_spawn_characters()
	_player.fit_to_stone(_stones[0]["radius"])
	_reflection.fit_to_stone(_stones[0]["radius"])
	var first_next := _next_stone()
	if not first_next.is_empty():
		_guide.fit_to_stone(first_next["radius"])
	_place_guide(true)
	_best.text = "最高 %d" % GameState.best_score
	_update_hud()
	if not GameState.guide_present:
		_guide.fade = 0.0
		_guide.visible = false
		_hint.text = "按住鼠标 / 空格蓄力，松手起跳"
	else:
		_hint.text = "跳到前方小光人那块石头上 · 按住蓄力，松手起跳"


func _apply_panel_skin() -> void:
	var module_panel := Panel.new()
	module_panel.name = "LakeJumpPanelSkin"
	UiPanelSkinScript.apply_fixed_rect(module_panel, UiPanelSkinScript.PANEL_RECT)
	module_panel.add_theme_stylebox_override("panel", UiPanelSkinScript.panel_style())
	module_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(module_panel)
	_hud.move_child(module_panel, 0)

	UiPanelSkinScript.apply_fixed_rect(_charge_bar, UiPanelSkinScript.INPUT_RECT)
	UiPanelSkinScript.apply_fixed_rect(_back, UiPanelSkinScript.BUTTON_RECT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		_back.add_theme_stylebox_override(state, UiPanelSkinScript.button_style())
	_back.add_theme_font_size_override("font_size", 16)
	_hint.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hint.position = Vector2(334.0, 201.0)
	_hint.size = Vector2(616.0, 32.0)


func _setup_river_bg() -> void:
	_river_rotated = true
	_video_sprite = Sprite2D.new()
	_video_sprite.texture = RiverTex
	_video_sprite.centered = true
	_video_sprite.z_index = Z_RIVER
	_video_sprite.z_as_relative = false
	_video_sprite.rotation = -PI * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = RiverWaveShader
	mat.set_shader_parameter("flow_speed", 0.22)
	mat.set_shader_parameter("wave_strength", 0.009)
	_video_sprite.material = mat
	add_child(_video_sprite)
	_fit_river_sprite()


func _fit_river_sprite() -> void:
	var view := get_viewport().get_visible_rect().size
	var tex_size := Vector2(1280, 720)
	if _video_sprite.texture != null:
		tex_size = _video_sprite.texture.get_size()
	var display_size := Vector2(tex_size.y, tex_size.x) if _river_rotated else tex_size
	var s := maxf(view.x / display_size.x, view.y / display_size.y)
	_video_sprite.scale = Vector2(s, s)


func _unhandled_input(event: InputEvent) -> void:
	if _state == State.OVER:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_held = event.pressed
	elif event is InputEventScreenTouch:
		_held = event.pressed
	elif event is InputEventKey and event.physical_keycode in [KEY_SPACE, KEY_ENTER]:
		if not event.echo:
			_held = event.pressed


func _process(delta: float) -> void:
	_camera.position = _camera.position.lerp(_player_pos + Vector2(0, -40), 1.0 - exp(-delta * 5.5))
	_shake = move_toward(_shake, 0.0, delta * 28.0)
	_camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	if _video_sprite:
		_video_sprite.global_position = _camera.global_position
	_hint_life -= delta
	_hint.modulate.a = clampf(_hint_life / 1.6, 0.0, 1.0)
	_update_guide(delta)
	_update_stone_highlights()

	match _state:
		State.IDLE:
			_charge = 0.0
			_height = 0.0
			_charge_bar.visible = false
			if _want_charge():
				_state = State.CHARGING
				_charge = 0.0
		State.CHARGING:
			_charge = minf(_charge + delta / CHARGE_TIME, 1.0)
			_charge_bar.visible = true
			_charge_bar.value = _charge
			if not _want_charge():
				_start_jump()
		State.JUMPING:
			_jump_t += delta / _jump_dur
			var t := clampf(_jump_t, 0.0, 1.0)
			var eased := t * t * (3.0 - 2.0 * t)
			_player_pos = _jump_from.lerp(_jump_to, eased)
			_height = 4.0 * t * (1.0 - t) * _arc
			_charge = 0.0
			_charge_bar.visible = false
			if t >= 1.0:
				_finish_jump()
		State.FALLING:
			_fall_t += delta
			_height = -_fall_t * 180.0
			if _fall_t > FALL_GAMEOVER_TIME:
				_end_run("fail")
		State.OVER:
			pass

	_update_player_body()
	_update_reflection()
	queue_redraw()


func _want_charge() -> bool:
	return _held or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_ENTER)


func _aim_dir() -> Vector2:
	var nxt := _next_stone()
	if nxt.is_empty():
		return Vector2.UP
	var dir: Vector2 = nxt["pos"] - _player_pos
	if dir.length() < 1.0:
		return Vector2.UP
	return dir.normalized()


func _next_stone() -> Dictionary:
	var i := _current + 1
	if i >= 0 and i < _stones.size():
		return _stones[i]
	return {}


func _predicted_land() -> Vector2:
	return _player_pos + _aim_dir() * lerpf(MIN_JUMP, MAX_JUMP, _charge)


func _start_jump() -> void:
	_jump_from = _player_pos
	_jump_to = _predicted_land()
	var dist := _jump_from.distance_to(_jump_to)
	_arc = clampf(dist * 0.42, 48.0, 150.0)
	_jump_dur = clampf(0.28 + dist / 720.0, 0.28, 0.55)
	_jump_t = 0.0
	_charge = 0.0
	_state = State.JUMPING


func _finish_jump() -> void:
	_player_pos = _jump_to
	_height = 0.0
	var idx := _stone_at(_jump_to)
	if idx >= 0:
		_land_ok(idx)
	else:
		_start_fall()


func _land_ok(idx: int) -> void:
	var stone: Dictionary = _stones[idx]
	var dist: float = _player_pos.distance_to(stone["pos"])
	_player_pos = stone["pos"]
	_current = idx
	_shake = 5.0
	if idx > 0:
		_landed += 1
		_score_value += 1
		var perfect := dist <= 14.0
		if perfect:
			_perfects += 1
			_score_value += 1
			_float_text("完美!", stone["pos"] + Vector2(0, -50), Color(1.0, 0.86, 0.35))
		else:
			_float_text("+1", stone["pos"] + Vector2(0, -44), Color(0.92, 0.97, 0.9))
		if _landed >= HARD_MODE_JUMPS and not _hard_mode:
			_hard_mode = true
			_float_text("难度提升!", stone["pos"] + Vector2(0, -72), Color(1.0, 0.55, 0.45))
			_hint.text = "难度提升：石头更小、间距更远"
			_hint_life = 4.0
	_ensure_stones()
	_player.fit_to_stone(stone["radius"])
	_reflection.fit_to_stone(stone["radius"])
	_place_guide(false)
	_update_hud()
	_state = State.IDLE
	_hint_life = minf(_hint_life, 1.5)


func _start_fall() -> void:
	_shake = 14.0
	_fall_t = 0.0
	_splash.global_position = _player_pos
	_splash.restart()
	_state = State.FALLING
	_float_text("落水", _player_pos + Vector2(0, -24), Color(0.7, 0.9, 1.0))


func _end_run(kind: String) -> void:
	if _state == State.OVER:
		return
	_state = State.OVER
	var payload := {
		"result": kind,
		"score": _score_value,
		"stones": _landed,
		"perfects": _perfects,
	}
	if kind == "abort":
		payload["next"] = "title"
	elif kind == "fail":
		payload["next"] = "gameover"
	finished.emit(payload)


func _on_back() -> void:
	_end_run("abort")


func _stone_at(pos: Vector2) -> int:
	var best := -1
	var best_d := 1e9
	for i in _stones.size():
		var stone: Dictionary = _stones[i]
		var d: float = pos.distance_to(stone["pos"])
		var limit: float = float(stone["radius"]) - (18.0 if _hard_mode else 10.0)
		if d <= limit and d < best_d:
			best_d = d
			best = i
	return best


func _make_stone(pos: Vector2, radius: float) -> Dictionary:
	var variant := _rng.randi_range(0, StoneTextures.size() - 1)
	var sprite := Sprite2D.new()
	sprite.texture = StoneTextures[variant]
	sprite.centered = true
	var mat := ShaderMaterial.new()
	mat.shader = BlackKeyShader
	sprite.material = mat
	var tex_size := sprite.texture.get_size()
	var target := radius * 2.25 * STONE_SCALE_MUL
	var sc := target / maxf(tex_size.x, tex_size.y)
	sprite.scale = Vector2(sc, sc)
	sprite.position = pos
	sprite.z_index = Z_STONE
	sprite.z_as_relative = false
	_stones_root.add_child(sprite)
	return {"pos": pos, "radius": radius, "variant": variant, "sprite": sprite}


func _append_stone() -> void:
	var last: Dictionary = _stones[_stones.size() - 1]
	var gap := _rng.randf_range(250.0, 380.0) if _hard_mode else _rng.randf_range(170.0, 290.0)
	var angle := _rng.randf_range(-0.68, 0.68) if _hard_mode else _rng.randf_range(-0.48, 0.48)
	var dir := Vector2(sin(angle), -cos(angle))
	var pos: Vector2 = last["pos"] + dir * gap
	pos.x = clampf(pos.x, -140.0, 140.0)
	var radius := _rng.randf_range(32.0, 50.0) if _hard_mode else _rng.randf_range(52.0, 82.0)
	if _rng.randf() < (0.5 if _hard_mode else 0.2):
		radius = _rng.randf_range(28.0, 36.0) if _hard_mode else _rng.randf_range(40.0, 48.0)
	_stones.append(_make_stone(pos, radius))


func _ensure_stones() -> void:
	while _stones.size() < _current + 8:
		_append_stone()


func _spawn_characters() -> void:
	_reflection = LightChildScene.instantiate()
	_reflection.role = LightChild.Role.REFLECTION
	_reflection.bob_enabled = false
	_reflections.add_child(_reflection)

	_player = LightChildScene.instantiate()
	_player.role = LightChild.Role.PLAYER
	_player.z_index = 2
	_top_layer.add_child(_player)

	_guide = LightChildScene.instantiate()
	_guide.role = LightChild.Role.GUIDE
	_guide.z_index = 1
	_top_layer.add_child(_guide)
	_guide.visible = GameState.guide_present
	_guide_fade = 1.0 if GameState.guide_present else 0.0
	_guide.fade = _guide_fade


func _place_guide(immediate: bool) -> void:
	if _guide == null or not GameState.guide_present or _guide_leaving:
		return
	var nxt := _next_stone()
	if nxt.is_empty():
		return
	_guide.fit_to_stone(nxt["radius"])
	_guide_to = nxt["pos"] + Vector2(0, _guide.stand_offset())
	_guide.visible = true
	_guide.fade = 1.0
	_guide_fade = 1.0
	if immediate:
		_guide.position = _guide_to
		_guide_from = _guide_to
		_guide_hop = 1.0
		_guide_hop_height = 0.0
	else:
		_guide_from = _guide.position
		_guide_hop = 0.0


func _update_guide(delta: float) -> void:
	if _guide == null:
		return
	if _guide_leaving:
		_guide_fade = move_toward(_guide_fade, 0.0, delta * 1.2)
		_guide.fade = _guide_fade
		_guide.position.y -= delta * 40.0
		if _guide_fade <= 0.0:
			_guide.visible = false
			_guide_leaving = false
		return
	if not GameState.guide_present:
		_guide.visible = false
		return
	_guide.visible = true
	if _guide_hop < 1.0:
		_guide_hop = minf(_guide_hop + delta / 0.4, 1.0)
		var t := _guide_hop
		var eased := t * t * (3.0 - 2.0 * t)
		var p: Vector2 = _guide_from.lerp(_guide_to, eased)
		_guide_hop_height = 4.0 * t * (1.0 - t) * 70.0
		_guide.position = p + Vector2(0, -_guide_hop_height)
	else:
		_guide.position = _guide_to
		_guide_hop_height = 0.0


func _update_player_body() -> void:
	if _player == null:
		return
	var jumping := _state == State.JUMPING
	var falling := _state == State.FALLING
	var stand_y := _player.stand_offset()
	_player.position = _player_pos + Vector2(0, stand_y - _height)
	_player.charge = _charge if _state == State.CHARGING else 0.0
	_player.blur = 0.5 if jumping else (1.0 if falling else 0.0)
	_player.bob_enabled = _state == State.IDLE
	_player.fade = 0.35 if falling else 1.0
	_player.visible = _state != State.OVER


func _update_reflection() -> void:
	if _reflection == null:
		return
	var jumping := _state == State.JUMPING or _state == State.FALLING
	var stand_y := _reflection.stand_offset()
	var offset := Vector2(0, 36)
	if not jumping and _current >= 0 and _current < _stones.size():
		offset = _aim_dir() * (float(_stones[_current]["radius"]) * 0.06) + Vector2(0, 38)
	_reflection.position = _player_pos + offset + Vector2(0, stand_y + _height * 0.05)
	_reflection.charge = _charge
	_reflection.blur = 1.0 if jumping else 0.0
	_reflection.fade = 0.35 if _state == State.FALLING else 0.88
	_reflection.bob_enabled = _state == State.IDLE
	_reflection.visible = _state != State.OVER


func _update_stone_highlights() -> void:
	for i in _stones.size():
		var stone: Dictionary = _stones[i]
		var sprite: Sprite2D = stone["sprite"]
		var highlight := i == _current + 1 and GameState.guide_present and not _guide_leaving
		sprite.modulate = Color(1.15, 1.08, 0.82) if highlight else Color.WHITE


func _update_hud() -> void:
	_score.text = str(_score_value)


func _float_text(text: String, pos: Vector2, color: Color) -> void:
	var bit := Floater.new()
	bit.text = text
	bit.color = color
	bit.position = pos
	bit.z_index = Z_TOP + 5
	bit.z_as_relative = false
	add_child(bit)


func _make_splash() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.94
	p.amount = 28
	p.lifetime = 0.55
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 180.0
	p.gravity = Vector2(0, 420)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.75, 0.92, 0.95)
	p.z_index = Z_FX
	p.z_as_relative = false
	return p


func _draw() -> void:
	if _state == State.CHARGING:
		_draw_aim()


func _draw_aim() -> void:
	var land := _predicted_land()
	var ok := _stone_at(land) >= 0
	var col := Color(0.45, 0.92, 0.55, 0.9) if ok else Color(0.95, 0.42, 0.38, 0.9)
	var from := _player_pos
	for i in 10:
		var a := i / 10.0
		var b := (i + 0.45) / 10.0
		draw_line(from.lerp(land, a), from.lerp(land, b), col, 3.0, true)
	draw_set_transform(land, 0.0, Vector2(1.0, 0.72))
	draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 28, col, 2.4, true)
	draw_circle(Vector2.ZERO, 5.0, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Floater extends Node2D:
	var text: String = ""
	var color: Color = Color.WHITE
	var life: float = 0.85

	func _process(delta: float) -> void:
		position.y -= 76.0 * delta
		life -= delta
		queue_redraw()
		if life <= 0.0:
			queue_free()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var size := 22
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		draw_string(font, Vector2(-w * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, clampf(life * 2.2, 0.0, 1.0)))
