extends Control

const DialogueScene := preload("res://systems/dialogue_system.tscn")
const CGPlayerScene := preload("res://systems/cg_player.gd")
const TransitionScript := preload("res://systems/transition_overlay.gd")
const GameOverScript := preload("res://systems/game_over_ui.gd")
const PauseMenuScript := preload("res://systems/pause_menu.gd")
const VersionDB := preload("res://data/version.gd")

@onready var _content: Control = $Content
@onready var _version: Label = $Version
@onready var _menu: VBoxContainer = $Menu
@onready var _new_game: Button = $Menu/NewGame
@onready var _continue: Button = $Menu/Continue
@onready var _title_label: Label = $Title

var _dialogue: Control
var _transition: CanvasLayer
var _game_over: Control
var _cg_player: Control
var _pause_menu: CanvasLayer
var _active_level: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_version.text = "奇妙夜 Demo v%s" % VersionDB.STRING
	_title_label.text = "奇妙夜"
	_new_game.pressed.connect(_on_new_game)
	_continue.pressed.connect(_on_continue)
	SceneManager.present_dialogue.connect(_on_present_dialogue)
	SceneManager.present_level.connect(_on_present_level)
	SceneManager.present_cg.connect(_on_present_cg)
	SceneManager.present_chapter3.connect(_on_present_chapter3)
	SceneManager.present_title.connect(_on_present_title)
	SceneManager.present_game_over.connect(_on_present_game_over)
	_transition = TransitionScript.new()
	add_child(_transition)
	SceneManager.bind_transition(_transition)
	_game_over = GameOverScript.new()
	add_child(_game_over)
	_cg_player = CGPlayerScene.new()
	_cg_player.visible = false
	_cg_player.z_index = 100
	_cg_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cg_player)
	CGManager.bind_player(_cg_player)
	_pause_menu = PauseMenuScript.new()
	_pause_menu.save_pressed.connect(_on_pause_save)
	_pause_menu.restart_pressed.connect(_on_pause_restart)
	_pause_menu.exit_pressed.connect(_on_pause_exit)
	add_child(_pause_menu)
	_show_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_menu"):
		return
	if _menu.visible:
		return
	_pause_menu.toggle_menu()
	get_viewport().set_input_as_handled()


func _show_menu() -> void:
	_pause_menu.close_menu()
	_title_label.visible = true
	_menu.visible = true
	_refresh_continue_button()


func _hide_menu() -> void:
	_menu.visible = false
	_title_label.visible = false


func _refresh_continue_button() -> void:
	_continue.disabled = not _has_save()


func _has_save() -> bool:
	return FileAccess.file_exists(GameState.SAVE_PATH) or FileAccess.file_exists(GameState.AUTO_SAVE_PATH)


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()
	_dialogue = null
	_active_level = null


func _on_present_title() -> void:
	_clear_content()
	_show_menu()


func _on_present_dialogue(scene_def: Dictionary) -> void:
	_hide_menu()
	_clear_content()
	_dialogue = DialogueScene.instantiate()
	_content.add_child(_dialogue)
	_dialogue.play(scene_def)


func _on_present_level(scene_def: Dictionary) -> void:
	_hide_menu()
	_clear_content()
	var path := str(scene_def.get("packed_scene", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Level scene missing: %s" % path)
		return
	var packed: PackedScene = load(path)
	var level: Node = packed.instantiate()
	if level is Node2D:
		var viewport_container := SubViewportContainer.new()
		viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
		viewport_container.stretch = true
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 540)
		viewport.handle_input_locally = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport_container.add_child(viewport)
		_content.add_child(viewport_container)
		viewport.add_child(level)
	else:
		_content.add_child(level)
	_active_level = level
	if level.has_method("setup"):
		level.call("setup", scene_def)
	if level.has_signal("finished"):
		level.finished.connect(_on_level_finished, CONNECT_ONE_SHOT)


func _on_present_cg(scene_def: Dictionary) -> void:
	_hide_menu()
	_clear_content()
	var cg_id := str(scene_def.get("cg_id", ""))
	if not cg_id.is_empty():
		_cg_player.visible = true
		await CGManager.show_cg(cg_id)
		_cg_player.visible = false
	var dialogue_id := str(scene_def.get("dialogue_id", ""))
	if dialogue_id.is_empty():
		SceneManager.complete_current_scene()
		return
	var def := scene_def.duplicate(true)
	def["type"] = "dialogue"
	def["lines"] = preload("res://data/dialogue_loader.gd").resolve_lines({"dialogue_id": dialogue_id})
	def["choices"] = preload("res://data/dialogue_loader.gd").resolve_choices({"dialogue_id": dialogue_id})
	_on_present_dialogue(def)


func _on_present_chapter3(scene_def: Dictionary) -> void:
	_hide_menu()
	_clear_content()
	var path := str(scene_def.get("packed_scene", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("Chapter3 scene missing: %s" % path)
		return
	var packed: PackedScene = load(path)
	var chapter: Node = packed.instantiate()
	_content.add_child(chapter)
	_active_level = chapter
	# Integrated mode: keep control in the main game after the chapter ends.
	if chapter.has_method("set_integrated"):
		chapter.call("set_integrated", true)
	if chapter.has_signal("chapter_finished"):
		chapter.chapter_finished.connect(_on_level_finished, CONNECT_ONE_SHOT)


func _on_level_finished(result: Dictionary) -> void:
	SceneManager.complete_current_scene(result)


func _on_present_game_over(payload: Dictionary) -> void:
	if _game_over.has_method("show_game_over"):
		_game_over.show_game_over(payload)


func _on_new_game() -> void:
	_pause_menu.close_menu()
	SceneManager.start_new_game()


func _on_continue() -> void:
	_pause_menu.close_menu()
	if GameState.try_load(GameState.SAVE_PATH) or GameState.try_load(GameState.AUTO_SAVE_PATH):
		SceneManager.go_to(GameState.current_scene_id)
	else:
		_refresh_continue_button()


func _on_pause_save() -> void:
	GameState.save_game()
	_pause_menu.show_status("已保存")


func _on_pause_restart() -> void:
	_pause_menu.close_menu()
	_clear_content()
	SceneManager.start_new_game()


func _on_pause_exit() -> void:
	get_tree().quit()
