extends Node

## Trigger -> Condition -> Action event runner.
## Maps and minigames fire triggers; this node evaluates and executes actions.

const DialogueLoader := preload("res://data/dialogue_loader.gd")


func _ready() -> void:
	EventBus.trigger_fired.connect(_on_trigger)


func _on_trigger(trigger_id: String, payload: Dictionary) -> void:
	var def: Dictionary = _get_trigger_def(trigger_id)
	if def.is_empty():
		return
	if not _check_conditions(def.get("conditions", [])):
		return
	for action in def.get("actions", []):
		await _run_action(action, payload)


func _get_trigger_def(trigger_id: String) -> Dictionary:
	# Extend with data/event_triggers.json when needed.
	var catalog := {
		"player_enter_forest_light": {
			"conditions": [],
			"actions": [{"type": "flag", "key": "saw_forest_light", "value": true}],
		},
	}
	return catalog.get(trigger_id, {})


func _check_conditions(conditions: Array) -> bool:
	for raw in conditions:
		var cond: Dictionary = raw
		var kind := str(cond.get("type", "flag"))
		match kind:
			"flag":
				if not GameState.has_flag(str(cond.get("key", ""))):
					return false
			"var":
				if GameState.get_var(str(cond.get("key", "")), "") != cond.get("value", ""):
					return false
	return true


func _run_action(action: Dictionary, _payload: Dictionary) -> void:
	match str(action.get("type", "")):
		"flag":
			GameState.set_flag(str(action.get("key", "")), action.get("value", true))
		"var":
			GameState.set_var(str(action.get("key", "")), action.get("value", 0), str(action.get("op", "set")))
		"cg":
			await CGManager.show_cg(str(action.get("cg_id", "")))
		"dialogue":
			var data := DialogueLoader.load_dialogue(str(action.get("dialogue_id", "")))
			EventBus.map_event.emit("inline_dialogue", data)
		"goto":
			SceneManager.go_to(str(action.get("scene_id", "")))
		_:
			push_warning("Unknown event action: %s" % action.get("type", ""))
