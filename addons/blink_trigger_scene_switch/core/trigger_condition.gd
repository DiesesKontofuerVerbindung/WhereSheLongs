class_name BlinkTriggerCondition
extends RefCounted

## Games own the real condition. Call BlinkSystem.unlock() when it becomes true.
func evaluate(_context: Dictionary = {}) -> bool:
	return false
