extends CanvasLayer

signal dialogue_closed
signal choice_selected(index: int, value: String)

@onready var panel: PanelContainer = $Panel
@onready var speaker_label: Label = $Panel/VBox/Speaker
@onready var text_label: Label = $Panel/VBox/Text
@onready var choice_box: VBoxContainer = $Panel/VBox/Choices
@onready var hint_label: Label = $Panel/VBox/Hint

var _open := false
var _choice_values: Array[String] = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    panel.hide()


func is_open() -> bool:
    return _open


func show_line(speaker: String, text: String) -> void:
    _clear_choices()
    speaker_label.text = speaker
    speaker_label.visible = not speaker.is_empty()
    text_label.text = text
    hint_label.text = "E  ·  continue"
    hint_label.show()
    panel.show()
    _open = true


func show_choices(speaker: String, text: String, choices: Array[String]) -> void:
    _clear_choices()
    speaker_label.text = speaker
    speaker_label.visible = not speaker.is_empty()
    text_label.text = text
    hint_label.hide()

    _choice_values = choices.duplicate()
    for index in range(_choice_values.size()):
        var button := Button.new()
        button.text = _choice_values[index]
        button.pressed.connect(_select_choice.bind(index))
        choice_box.add_child(button)

    panel.show()
    _open = true


func close() -> void:
    if not _open:
        return
    _open = false
    panel.hide()
    _clear_choices()
    dialogue_closed.emit()


func _unhandled_input(event: InputEvent) -> void:
    if not _open:
        return
    if _choice_values.is_empty() and event.is_action_pressed("interact"):
        close()
        get_viewport().set_input_as_handled()


func _select_choice(index: int) -> void:
    if index < 0 or index >= _choice_values.size():
        return
    var value := _choice_values[index]
    choice_selected.emit(index, value)
    close()


func _clear_choices() -> void:
    for child in choice_box.get_children():
        child.queue_free()
    _choice_values.clear()
