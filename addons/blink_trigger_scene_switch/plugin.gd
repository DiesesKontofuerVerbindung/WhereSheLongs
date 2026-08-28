@tool
extends EditorPlugin

const AUTOLOAD_NAME := "BlinkSystem"
const AUTOLOAD_PATH := "res://addons/blink_trigger_scene_switch/blink_system.gd"


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
