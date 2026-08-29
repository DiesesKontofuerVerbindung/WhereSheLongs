extends Node

const WeddingPrologueScript := preload("res://scripts/wedding_prologue.gd")
const Chapter3Script := preload("res://scripts/chapter3.gd")
const Chapter3DataScript := preload("res://scripts/chapter3_data.gd")
const Chapter3StageScript := preload("res://scenes/chapter3/chapter3_stage.gd")
const GameStateScript := preload("res://autoload/game_state.gd")


func _ready() -> void:
	var failures := PackedStringArray()
	var wedding_probe = WeddingPrologueScript.new()
	var chapter3_probe = Chapter3Script.new()
	var wedding_constants := (wedding_probe.get_script() as GDScript).get_script_constant_map()
	var chapter3_constants := (chapter3_probe.get_script() as GDScript).get_script_constant_map()
	wedding_probe.free()
	chapter3_probe.free()
	if str(wedding_constants.get("CHAPTER3_SCENE", "")) != "res://scenes/chapter3/chapter3.tscn":
		failures.append("婚礼前夜没有接到正式婚礼")
	if str(chapter3_constants.get("MYSTIC_NIGHT_SCENE", "")) != "res://scenes/mystic_night/mystic_night.tscn":
		failures.append("正式婚礼没有接到奇妙夜")

	if not ResourceLoader.exists("res://scenes/chapter3/chapter3.tscn", "PackedScene"):
		failures.append("正式婚礼场景不存在")
	else:
		var packed := load("res://scenes/chapter3/chapter3.tscn") as PackedScene
		var instance := packed.instantiate() if packed != null else null
		if instance == null:
			failures.append("正式婚礼场景无法实例化")
		else:
			if not instance.has_signal("chapter_finished"):
				failures.append("正式婚礼缺少完成信号")
			if not instance.has_method("set_integrated"):
				failures.append("正式婚礼缺少集成模式接口")
			instance.free()

	var events := Chapter3DataScript.build_events()
	if events.is_empty():
		failures.append("正式婚礼事件表为空")
	for asset_path in [
		Chapter3StageScript.BG_OPENING_POSTER,
		Chapter3StageScript.BG_MOM_TRANSITION,
		Chapter3StageScript.BG_FORMAL_WEDDING,
		Chapter3StageScript.BG_CORRIDOR,
		Chapter3StageScript.BG_WINDOW_TALK,
		Chapter3StageScript.BG_ENDING_A_VEIL,
		Chapter3StageScript.BG_ENDING_A_NO_VEIL,
		Chapter3StageScript.BG_ENDING_B_RUN_CARPET,
		Chapter3StageScript.BG_ENDING_BC_SUN_RUN,
		Chapter3StageScript.BG_ENDING_C_LEAVE,
		Chapter3StageScript.VIDEO_OPENING,
		Chapter3StageScript.CHR_SIYU,
		Chapter3StageScript.CHR_XIAOLING_BRIDE,
		Chapter3StageScript.CHR_MOM,
	]:
		if not ResourceLoader.exists(asset_path):
			failures.append("正式婚礼资源不存在：%s" % asset_path)

	var state = GameStateScript.new()
	state.reset()
	state.unlock_ending("B", false)
	state.unlock_ending("A", false)
	state.unlock_ending("C", false)
	if state.ending_count() != 3 or state.last_ending != "C" or state.best_ending != "C":
		failures.append("结局记录或 C>A>B 排序异常")
	var saved := state.to_dict()
	var restored = GameStateScript.new()
	restored.from_dict(saved)
	if restored.ending_count() != 3 or restored.last_ending != "C" or restored.best_ending != "C":
		failures.append("结局存档往返异常")
	state.free()
	restored.free()

	if not failures.is_empty():
		for failure in failures:
			print("CHAPTER3_INTEGRATION_FAIL %s" % failure)
		get_tree().quit(1)
		return
	print("CHAPTER3_INTEGRATION_PASS route=wedding_prologue_chapter3_mystic_night events=%d endings=C_A_B assets=true" % events.size())
	get_tree().quit(0)
