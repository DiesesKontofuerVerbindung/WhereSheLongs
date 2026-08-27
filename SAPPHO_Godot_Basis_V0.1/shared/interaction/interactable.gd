extends Area2D
class_name SharedInteractable

@export var speaker_name: String = ""
@export_multiline var interaction_text: String = ""
@export_multiline var look_text: String = ""


func _ready() -> void:
    collision_layer = 2
    collision_mask = 0
    monitoring = false
    monitorable = true


func interact(_actor: Node) -> void:
    if not interaction_text.is_empty():
        Dialogue.show_line(speaker_name, interaction_text)


func look(_actor: Node) -> void:
    if not look_text.is_empty():
        Dialogue.show_line(speaker_name, look_text)
