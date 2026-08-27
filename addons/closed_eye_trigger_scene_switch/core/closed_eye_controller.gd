class_name ClosedEyeController
extends RefCounted

enum State { IDLE, ARMED, TRIGGERED }

signal state_changed(state: State)
signal hold_ignored(reason: String)
signal consumed(main_scene: String, child_scene: String)

const MappingScript := preload("res://addons/closed_eye_trigger_scene_switch/core/closed_eye_scene_mapping.gd")

var state: State = State.IDLE
var enabled: bool = true
var hold_count: int = 0
var mapping = MappingScript.new()


func configure(main_scene: String, child_scene: String) -> void:
	mapping.main_scene = main_scene
	mapping.child_scene = child_scene
	if state == State.IDLE and not child_scene.is_empty():
		arm()


func arm() -> bool:
	if state == State.TRIGGERED:
		hold_ignored.emit("already_consumed")
		return false
	state = State.ARMED
	state_changed.emit(state)
	return true


func handle_closed_hold() -> bool:
	hold_count += 1
	if not enabled:
		hold_ignored.emit("disabled")
		return false
	if state == State.IDLE:
		hold_ignored.emit("idle")
		return false
	if state == State.TRIGGERED:
		hold_ignored.emit("already_consumed")
		return false
	if mapping.child_scene.is_empty():
		hold_ignored.emit("no_child_scene")
		return false
	state = State.TRIGGERED
	state_changed.emit(state)
	consumed.emit(mapping.main_scene, mapping.child_scene)
	return true


func is_armed() -> bool:
	return state == State.ARMED


func is_consumed() -> bool:
	return state == State.TRIGGERED


func reset() -> void:
	state = State.IDLE
	hold_count = 0
	state_changed.emit(state)


func enable() -> void:
	enabled = true


func disable() -> void:
	enabled = false


func state_name() -> String:
	match state:
		State.IDLE:
			return "IDLE"
		State.ARMED:
			return "ARMED"
		State.TRIGGERED:
			return "TRIGGERED"
		_:
			return "UNKNOWN"
