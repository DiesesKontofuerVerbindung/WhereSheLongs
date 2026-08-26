extends Control

@onready var hint: Label = $Hint


func _ready() -> void:
	BlinkSystem.configure("res://scenes/room_a.tscn", "res://scenes/room_a_empty.tscn")
	hint.text = "正常状态。Blink System: LOCKED。先完成游戏条件。"


func _on_unlock_pressed() -> void:
	if BlinkSystem.unlock():
		hint.text = "条件已满足。Blink System: UNLOCKED。请眨眼（调试也可按 F8）。"
