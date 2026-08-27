extends Control

@onready var hint: Label = $Hint


func _ready() -> void:
	if ClosedEyeSystem == null:
		hint.text = "闭眼插件未能加载，请重启游戏。"
		return
	ClosedEyeSystem.configure("res://scenes/closed_hold_a.tscn", "res://scenes/closed_hold_b.tscn")
	hint.text = "程序已自动打开摄像头。闭上双眼保持 1.5 秒即可切场景。"
