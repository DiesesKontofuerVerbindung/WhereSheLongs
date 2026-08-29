extends Node

const CGCatalog := preload("res://data/cg_catalog.gd")

signal cg_started(cg_id: String)
signal cg_ended(cg_id: String)

var _player: Control
var _active := false


func _ready() -> void:
	EventBus.cg_requested.connect(_on_cg_requested)


func bind_player(player: Control) -> void:
	_player = player


func show_cg(cg_id: String, payload: Dictionary = {}) -> void:
	if _player == null:
		push_error("CGManager: no player bound")
		EventBus.cg_finished.emit(cg_id)
		return
	if _active:
		await cg_ended
	_active = true
	_player.show()
	_player.mouse_filter = Control.MOUSE_FILTER_STOP
	cg_started.emit(cg_id)
	await _player.play(cg_id, payload)
	_player.visible = false
	_active = false
	cg_ended.emit(cg_id)
	EventBus.cg_finished.emit(cg_id)


func _on_cg_requested(cg_id: String, payload: Dictionary) -> void:
	show_cg(cg_id, payload)
