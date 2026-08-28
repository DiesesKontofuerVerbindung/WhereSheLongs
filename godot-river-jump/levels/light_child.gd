class_name LightChild
extends Node2D

enum Role { PLAYER, REFLECTION, GUIDE }

const TEX_PLAYER := preload("res://assets/characters/player.png")
const TEX_REFLECTION := preload("res://assets/characters/reflection.png")
const TEX_GUIDE := preload("res://assets/characters/guide.png")
const GUIDE_SIZE_MUL := 2.0
const GreenKeyShader := preload("res://assets/green_key.gdshader")
const GuideGlowShader := preload("res://assets/guide_glow.gdshader")

@export var role: Role = Role.PLAYER

var blur: float = 0.0
var fade: float = 1.0
var charge: float = 0.0
var bob_enabled: bool = true

var _sprite: Sprite2D
var _glow_outer: Sprite2D
var _glow_mid: Sprite2D
var _ghosts: Array[Sprite2D] = []
var _bob_t: float = 0.0
var _target_height: float = 100.0
var _stone_radius: float = 70.0


func _ready() -> void:
	z_as_relative = true
	var tex := _pick_texture()
	if tex == null:
		push_error("LightChild missing texture for role %s" % role)
		return
	if role == Role.GUIDE:
		_glow_outer = _make_guide_glow(tex, 1.42, 0.75)
		_glow_mid = _make_guide_glow(tex, 1.18, 1.0)
		add_child(_glow_outer)
		add_child(_glow_mid)
	_sprite = _make_body_sprite(tex)
	add_child(_sprite)
	if role != Role.GUIDE:
		for _i in 3:
			var g := _make_body_sprite(tex)
			g.visible = false
			add_child(g)
			_ghosts.append(g)
	_fit_scale()


func _pick_texture() -> Texture2D:
	match role:
		Role.GUIDE:
			return TEX_GUIDE
		Role.REFLECTION:
			return TEX_REFLECTION
		_:
			return TEX_PLAYER


func _make_body_sprite(tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if role == Role.GUIDE:
		var mat := ShaderMaterial.new()
		mat.shader = GreenKeyShader
		s.material = mat
	return s


func _make_guide_glow(tex: Texture2D, scale_mul: float, strength: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = true
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.scale = Vector2(scale_mul, scale_mul)
	var mat := ShaderMaterial.new()
	mat.shader = GuideGlowShader
	mat.set_shader_parameter("glow_strength", strength)
	s.material = mat
	return s


func fit_to_stone(radius: float) -> void:
	_stone_radius = radius
	_target_height = clampf(radius * 0.95, 78.0, 112.0)
	_fit_scale()


func stand_offset() -> float:
	var h := _target_height
	if role == Role.GUIDE:
		h = _target_height * GUIDE_SIZE_MUL
	return -h * 0.48 + _stone_radius * 0.12


func _fit_scale() -> void:
	if _sprite == null or _sprite.texture == null:
		return
	var h := float(_sprite.texture.get_height())
	var target := _target_height
	if role == Role.GUIDE:
		target = _target_height * GUIDE_SIZE_MUL
	elif role == Role.REFLECTION:
		target = _target_height * 0.8
	var s := target / maxf(h, 1.0)
	scale = Vector2(s, s)


func _process(delta: float) -> void:
	_bob_t += delta
	modulate = Color(1, 1, 1, fade)
	visible = fade > 0.01

	if role == Role.GUIDE:
		var pulse := 0.82 + 0.18 * sin(_bob_t * 3.4)
		var bob := sin(_bob_t * 2.2) * 2.0
		_sprite.position.y = bob
		if _glow_outer:
			_glow_outer.position.y = bob
			_glow_outer.modulate = Color(1.0, 0.9, 0.5, 0.42 * pulse * fade)
		if _glow_mid:
			_glow_mid.position.y = bob
			_glow_mid.modulate = Color(1.0, 0.96, 0.72, 0.62 * pulse * fade)
		return

	var bob := sin(_bob_t * 2.2) * 2.0 if bob_enabled else 0.0
	var squash_y := lerpf(1.0, 0.68, charge)
	var squash_x := lerpf(1.0, 1.22, charge)
	var smear := blur * 14.0
	var ox := sin(_bob_t * 22.0) * smear
	var oy := bob
	var body := Vector2(squash_x, squash_y)
	if role == Role.REFLECTION:
		body.y = -absf(body.y)

	_sprite.position = Vector2(ox, oy)
	_sprite.scale = body
	_sprite.modulate = Color(1, 1, 1, fade * (1.0 - blur * 0.25))

	var ghost_n := _ghosts.size() if blur > 0.08 else 0
	for i in _ghosts.size():
		var g := _ghosts[i]
		if i < ghost_n:
			g.visible = true
			var a := TAU * float(i) / float(_ghosts.size())
			g.position = Vector2(ox, oy) + Vector2(cos(a), sin(a)) * blur * 12.0
			g.scale = body
			g.modulate = Color(1, 1, 1, 0.22 * fade)
		else:
			g.visible = false
