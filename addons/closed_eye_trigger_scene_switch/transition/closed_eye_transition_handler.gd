class_name ClosedEyeTransitionHandler
extends Node

signal transition_started(scene_id: String)
signal transition_finished(scene_id: String)


func switch_to(_scene_id: String) -> void:
	push_error("ClosedEyeTransitionHandler.switch_to must be implemented")
