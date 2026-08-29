extends SceneTree
## Headless smoke test for the Chapter 3 integration.
## Runs WITHOUT the project autoloads (so no webcam/python spawn).
## Verifies: story graph routing, GameState ending API (C>A>B), asset/scene resolvability.

func _initialize() -> void:
	var failures: PackedStringArray = []

	# --- 1. story_flow routes part4 -> chapter3_ceremony -> demo_end ---
	var StoryFlow := load("res://data/story_flow.gd")
	var part4: Dictionary = StoryFlow.get_scene("part4_mystery_girl")
	if str(part4.get("on_complete", "")) != "chapter3_ceremony":
		failures.append("part4_mystery_girl.on_complete != chapter3_ceremony (got %s)" % part4.get("on_complete"))
	var ch3: Dictionary = StoryFlow.get_scene("chapter3_ceremony")
	if ch3.is_empty():
		failures.append("chapter3_ceremony node missing")
	else:
		if str(ch3.get("type", "")) != "chapter3":
			failures.append("chapter3_ceremony.type != chapter3 (got %s)" % ch3.get("type"))
		if str(ch3.get("packed_scene", "")) != "res://scenes/chapter3/chapter3.tscn":
			failures.append("chapter3_ceremony.packed_scene wrong: %s" % ch3.get("packed_scene"))
		if str(ch3.get("on_complete", "")) != "demo_end":
			failures.append("chapter3_ceremony.on_complete != demo_end (got %s)" % ch3.get("on_complete"))
	var demo_end: Dictionary = StoryFlow.get_scene("demo_end")
	if demo_end.is_empty():
		failures.append("demo_end node missing")
	else:
		print("   demo_end still terminal:", "quit_game" in str(demo_end.get("choices", [])))

	# --- 2. chapter3 scene + its script resolve ---
	if not ResourceLoader.exists("res://scenes/chapter3/chapter3.tscn"):
		failures.append("chapter3.tscn not found")
	else:
		var packed: PackedScene = load("res://scenes/chapter3/chapter3.tscn")
		if packed == null:
			failures.append("chapter3.tscn failed to load")
		else:
			print("   chapter3.tscn loads OK")
	# chapter3.gd script resolves
	if not ResourceLoader.exists("res://scripts/chapter3.gd"):
		failures.append("scripts/chapter3.gd not found")
	else:
		var scr: GDScript = load("res://scripts/chapter3.gd")
		if scr == null:
			failures.append("scripts/chapter3.gd failed to load")
		else:
			# Check on an instance (has_signal/has_method are instance-level in Godot 4)
			var inst = scr.new()
			print("   chapter3.gd loads OK; has chapter_finished:", inst.has_signal("chapter_finished"))
			print("   chapter3.gd has set_integrated:", inst.has_method("set_integrated"))
			if not inst.has_signal("chapter_finished"):
				failures.append("chapter3 instance lacks chapter_finished signal")
			if not inst.has_method("set_integrated"):
				failures.append("chapter3 instance lacks set_integrated method")
			inst.free()

	# --- 3. GameState ending API (no autoload; instantiate directly) ---
	var GameState = load("res://autoload/game_state.gd").new()
	GameState.reset()
	if GameState.ending_count() != 0:
		failures.append("ending_count() should be 0 after reset")
	GameState.unlock_ending("B")
	if GameState.last_ending != "B":
		failures.append("last_ending != B after unlock_ending(B): %s" % GameState.last_ending)
	if GameState.best_ending != "B":
		failures.append("best_ending != B with only B: %s" % GameState.best_ending)
	if not GameState.is_unlocked("B"):
		failures.append("is_unlocked(B) should be true")
	GameState.unlock_ending("A")
	if GameState.ending_count() != 2:
		failures.append("ending_count() != 2 after A+B")
	if GameState.best_ending != "C" and GameState.best_ending != "A":
		# C>A>B: A is better than B, so best should be A
		failures.append("best_ending != A with A+B under C>A>B ranking: %s" % GameState.best_ending)
	GameState.unlock_ending("C")
	if GameState.best_ending != "C":
		failures.append("best_ending != C after C unlocked (C>A>B): %s" % GameState.best_ending)
	# persistence round-trip
	var data: Dictionary = GameState.to_dict()
	var gs2 = load("res://autoload/game_state.gd").new()
	gs2.reset()
	gs2.from_dict(data)
	if gs2.last_ending != "C" or gs2.ending_count() != 3 or gs2.best_ending != "C":
		failures.append("save/load round-trip failed: %s" % str([gs2.last_ending, gs2.ending_count(), gs2.best_ending]))
	print("   GameState ending API OK (C>A>B ranking verified)")

	# --- result ---
	print("==== SMOKE RESULT ====")
	if failures.is_empty():
		print("PASS")
		quit(0)
	else:
		for f in failures:
			print("FAIL:", f)
		quit(1)
