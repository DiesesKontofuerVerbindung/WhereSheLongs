extends CharacterBody2D

const PlaceholderAssets := preload("res://systems/placeholder_assets.gd")

signal interact_pressed

@export var move_speed := 140.0
@export var can_move := true

var _sprite: Sprite2D
var _light: PointLight2D


func _ready() -> void:
	_build_visual()
	collision_layer = 1
	collision_mask = 1


func _physics_process(_delta: float) -> void:
	if not can_move:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	velocity = dir.normalized() * move_speed if dir != Vector2.ZERO else Vector2.ZERO
	move_and_slide()
	if Input.is_action_just_pressed("interact"):
		interact_pressed.emit()


func set_can_move(value: bool) -> void:
	can_move = value
	if not value:
		velocity = Vector2.ZERO


func set_light_enabled(enabled: bool) -> void:
	if _light:
		_light.visible = enabled


func _build_visual() -> void:
	var col := Color(0.85, 0.75, 0.9)
	_sprite = Sprite2D.new()
	_sprite.texture = PlaceholderAssets.make_character_sprite(col, "xiaoling")
	_sprite.position = Vector2(0, -16)
	add_child(_sprite)
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	collision.shape = shape
	add_child(collision)
	_light = PointLight2D.new()
	_light.energy = 0.8
	_light.texture_scale = 2.0
	_light.color = Color(0.9, 0.85, 0.7)
	_light.visible = false
	add_child(_light)
