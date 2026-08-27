extends Node2D


func _ready() -> void:
    Dialogue.show_line(
        "Basis V0.1",
        "WASD / arrows: move    E: interact / continue    F: look    Space: reserved jump action. "
        + "Forest and Wedding are parallel scenes using the same shared Player."
    )
