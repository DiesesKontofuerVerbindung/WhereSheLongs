extends CanvasLayer

const ForestController = preload("res://scenes/forest/forest_sequence_controller.gd")

@export var controller_path: NodePath = ^"../../ForestSequenceController"
@export var player_path: NodePath = ^"../../Player"

@onready var controller = get_node(controller_path)
@onready var player: CharacterBody2D = get_node(player_path)
@onready var panel: PanelContainer = $Panel
@onready var state_label: Label = $Panel/Margin/VBox/State
@onready var position_label: Label = $Panel/Margin/VBox/Position
@onready var movement_label: Label = $Panel/Margin/VBox/Movement
@onready var trigger_label: Label = $Panel/Margin/VBox/Trigger
@onready var dialogue_label: Label = $Panel/Margin/VBox/Dialogue


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    panel.hide()
    $Panel/Margin/VBox/Restart.pressed.connect(controller.restart_sequence)
    $Panel/Margin/VBox/NextState.pressed.connect(controller.advance)
    $Panel/Margin/VBox/Parkour.pressed.connect(_jump.bind(ForestController.ForestState.PARKOUR))
    $Panel/Margin/VBox/Waterfall.pressed.connect(_jump.bind(ForestController.ForestState.WATERFALL_INTRO))
    $Panel/Margin/VBox/Lake.pressed.connect(_jump.bind(ForestController.ForestState.LAKE_INTRO))
    $Panel/Margin/VBox/Drowning.pressed.connect(_jump.bind(ForestController.ForestState.DROWNING))
    $Panel/Margin/VBox/LakeDialogue.pressed.connect(_jump.bind(ForestController.ForestState.LAKE_DIALOGUE))
    $Panel/Margin/VBox/WorldCollapse.pressed.connect(_jump.bind(ForestController.ForestState.WORLD_COLLAPSE))


func _process(_delta: float) -> void:
    if panel.visible:
        _refresh_status()


func _unhandled_key_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
        toggle_panel()
        get_viewport().set_input_as_handled()


func toggle_panel() -> void:
    panel.visible = not panel.visible
    if panel.visible:
        _refresh_status()


func jump_to_state(state: int) -> void:
    _jump(state)


func _jump(state: int) -> void:
    controller.debug_jump(state)
    _refresh_status()


func _refresh_status() -> void:
    state_label.text = "Current ForestState: %s" % controller.get_state_name()
    position_label.text = "Player Position: (%.1f, %.1f)" % [player.global_position.x, player.global_position.y]
    movement_label.text = "Movement Enabled: %s" % controller.is_player_movement_enabled()
    trigger_label.text = "Current Trigger: %s" % controller.current_trigger
    dialogue_label.text = "Dialogue State: %s" % ("OPEN" if Dialogue.is_open() else "CLOSED")
