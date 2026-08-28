extends Control

signal chosen(next_id)

@onready var _title: Label = $Center/Panel/Margin/VBox/Title
@onready var _subtitle: Label = $Center/Panel/Margin/VBox/Subtitle
@onready var _body: Label = $Center/Panel/Margin/VBox/Body
@onready var _buttons: VBoxContainer = $Center/Panel/Margin/VBox/Buttons
@onready var _best: Label = $Center/Panel/Margin/VBox/Best


func setup(scene_def: Dictionary) -> void:
	_title.text = str(scene_def.get("title", ""))
	_subtitle.text = str(scene_def.get("subtitle", ""))
	_subtitle.visible = not _subtitle.text.is_empty()
	if bool(scene_def.get("show_result", false)):
		var stones := int(GameState.last_result.get("stones", GameState.last_result.get("score", 0)))
		var perfects := int(GameState.last_result.get("perfects", 0))
		var score := int(GameState.last_result.get("score", 0))
		_body.text = "跳过 %d 块石头 · 得分 %d\n完美落地 %d 次" % [stones, score, perfects]
	else:
		_body.text = str(scene_def.get("body", ""))
	_best.text = "最高分  %d" % GameState.best_score
	for child in _buttons.get_children():
		child.queue_free()
	var specs: Array = scene_def.get("buttons", [])
	for spec in specs:
		var btn := Button.new()
		btn.text = str(spec.get("text", "OK"))
		btn.custom_minimum_size = Vector2(0, 44)
		var next_id := str(spec.get("next", ""))
		btn.pressed.connect(func() -> void: chosen.emit(next_id))
		_buttons.add_child(btn)
