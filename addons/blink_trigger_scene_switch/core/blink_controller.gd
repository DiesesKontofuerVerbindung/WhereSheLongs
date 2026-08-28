class_name BlinkController
extends RefCounted

enum State { LOCKED, UNLOCKED, TRIGGERED }

signal state_changed(state: State)
signal blink_ignored(reason: String)
signal consumed(main_scene: String, child_scene: String)

var state: State = State.LOCKED
var enabled: bool = true
var blink_count: int = 0
var mapping := BlinkSceneMapping.new()


func configure(main_scene: String, child_scene: String) -> void:
	mapping.main_scene = main_scene
	mapping.child_scene = child_scene


func unlock() -> bool:
	if state == State.TRIGGERED:
		blink_ignored.emit("already_consumed")
		return false
	state = State.UNLOCKED
	state_changed.emit(state)
	return true


func handle_blink() -> bool:
	blink_count += 1
	if not enabled:
		blink_ignored.emit("disabled")
		return false
	if state == State.LOCKED:
		blink_ignored.emit("locked")
		return false
	if state == State.TRIGGERED:
		blink_ignored.emit("already_consumed")
		return false
	state = State.TRIGGERED
	state_changed.emit(state)
	consumed.emit(mapping.main_scene, mapping.child_scene)
	return true


func is_unlocked() -> bool:
	return state == State.UNLOCKED


func is_consumed() -> bool:
	return state == State.TRIGGERED


func get_blink_count() -> int:
	return blink_count


func reset() -> void:
	state = State.LOCKED
	blink_count = 0
	state_changed.emit(state)


func enable() -> void:
	enabled = true


func disable() -> void:
	enabled = false


func state_name() -> String:
	match state:
		State.LOCKED:
			return "LOCKED"
		State.UNLOCKED:
			return "UNLOCKED"
		State.TRIGGERED:
			return "TRIGGERED"
		_:
			return "UNKNOWN"
