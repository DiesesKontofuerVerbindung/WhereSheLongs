extends RefCounted

const DIALOGUE_DIR := "res://data/dialogue/"


static func load_dialogue(dialogue_id: String) -> Dictionary:
	var path := DIALOGUE_DIR + dialogue_id + ".json"
	if not FileAccess.file_exists(path):
		push_error("Dialogue file missing: %s" % path)
		return {"id": dialogue_id, "lines": [], "choices": []}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid dialogue JSON: %s" % path)
		return {"id": dialogue_id, "lines": [], "choices": []}
	return parsed


static func resolve_lines(scene_def: Dictionary) -> Array:
	var dialogue_id := str(scene_def.get("dialogue_id", ""))
	if not dialogue_id.is_empty():
		var data := load_dialogue(dialogue_id)
		return _filter_lines(data.get("lines", []))
	var by_flag: Dictionary = scene_def.get("lines_by_flag", {})
	for flag_name in by_flag.keys():
		if GameState.has_flag(str(flag_name)):
			return _filter_lines(by_flag[flag_name])
	return _filter_lines(scene_def.get("lines", []))


static func resolve_choices(scene_def: Dictionary) -> Array:
	var dialogue_id := str(scene_def.get("dialogue_id", ""))
	if dialogue_id.is_empty():
		return scene_def.get("choices", [])
	var data := load_dialogue(dialogue_id)
	return data.get("choices", [])


static func _filter_lines(lines: Array) -> Array:
	var result: Array = []
	for raw in lines:
		var line: Dictionary = raw
		var condition := str(line.get("condition", ""))
		if not condition.is_empty() and not GameState.has_flag(condition):
			continue
		var var_condition := str(line.get("var_condition", ""))
		if not var_condition.is_empty():
			var parts := var_condition.split(":")
			if parts.size() >= 2:
				var key := str(parts[0])
				var needed := str(parts[1])
				if str(GameState.get_var(key, "")) != needed:
					continue
		result.append(line)
	return result
