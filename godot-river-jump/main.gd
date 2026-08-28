extends Node

const VersionDB := preload("res://data/version.gd")
const MenuScene := preload("res://systems/menu_screen.tscn")

@onready var _world: Node2D = $World
@onready var _ui: Control = $UI/Content
@onready var _version: Label = $UI/Version

var _level: Node


func _ready() -> void:
	_version.text = "v%s  %s" % [VersionDB.STRING, VersionDB.CODENAME]
	SceneManager.present_menu.connect(_on_present_menu)
	SceneManager.present_level.connect(_on_present_level)
	SceneManager.continue_or_start()


func _clear() -> void:
	for child in _world.get_children():
		child.queue_free()
	for child in _ui.get_children():
		child.queue_free()
	_level = null


func _on_present_menu(scene_def: Dictionary) -> void:
	_clear()
	var menu: Control = MenuScene.instantiate()
	_ui.add_child(menu)
	menu.setup(scene_def)
	menu.chosen.connect(_on_menu_chosen)


func _on_present_level(scene_def: Dictionary) -> void:
	_clear()
	var path := str(scene_def.get("packed_scene", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Level scene missing: %s" % path)
		return
	var packed: PackedScene = load(path)
	_level = packed.instantiate()
	_world.add_child(_level)
	if _level.has_method("setup"):
		_level.call("setup", scene_def)
	if _level.has_signal("finished"):
		_level.finished.connect(_on_level_finished, CONNECT_ONE_SHOT)


func _on_level_finished(result: Dictionary) -> void:
	SceneManager.complete_current_scene(result)


func _on_menu_chosen(next_id: String) -> void:
	SceneManager.go_to(next_id)
