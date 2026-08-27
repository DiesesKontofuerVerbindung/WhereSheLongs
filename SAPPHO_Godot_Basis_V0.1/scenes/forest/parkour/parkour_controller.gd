extends Node2D
class_name ParkourController

signal parkour_main_route_completed
signal parkour_advanced_route_completed
signal player_respawned(platform_id: StringName)

@export var design_size := Vector2(1920.0, 1080.0)
@export var kill_y := 1180.0
@export var player_path: NodePath = ^"Player"
@export var motor_path: NodePath = ^"ParkourMotor"
@export var route_path: NodePath = ^"ParkourRoute"
@export var platforms_path: NodePath = ^"Gameplay/Platforms"
@export var debug_path: NodePath = ^"ParkourDebug"
@export var art_background_path: NodePath = ^"Background/Art"
@export var layout_background_path: NodePath = ^"Background/LayoutReference"

var current_platform: StringName = &""
var last_safe_platform: StringName = &""
var highest_progress := -1
var actual_route: Array[StringName] = []
var fall_count := 0
var active := false

var _last_safe_spawn := Vector2.ZERO
var _main_completion_emitted := false
var _advanced_completion_emitted := false
var _layout_background_visible := false
var _platforms: Dictionary = {}

@onready var player: CharacterBody2D = get_node(player_path)
@onready var motor: ParkourMotor = get_node(motor_path)
@onready var route: ParkourRoute = get_node(route_path)
@onready var platforms_root: Node = get_node(platforms_path)
@onready var parkour_debug: Node = get_node_or_null(debug_path)
@onready var art_background: Sprite2D = get_node_or_null(art_background_path)
@onready var layout_background: Sprite2D = get_node_or_null(layout_background_path)


func _ready() -> void:
    process_physics_priority = -100
    _configure_route()
    _configure_backgrounds()
    var player_camera := player.get_node_or_null("Camera2D") as Camera2D
    if player_camera != null:
        player_camera.enabled = false
    enter_parkour()


func _exit_tree() -> void:
    if is_instance_valid(player):
        exit_parkour()


func _physics_process(delta: float) -> void:
    if not active:
        return
    if player.global_position.y > kill_y:
        respawn(true)
        return

    motor.velocity = player.velocity
    var desired_velocity := motor.step(
        delta,
        Input.get_axis("move_left", "move_right"),
        Input.is_action_just_pressed("jump"),
        Input.is_action_pressed("jump"),
        Input.is_action_just_released("jump"),
        player.is_on_floor()
    )
    player.set_external_velocity(desired_velocity)


func _unhandled_input(event: InputEvent) -> void:
    if not active or not event is InputEventKey or not event.pressed or event.echo:
        return
    match event.keycode:
        KEY_F1:
            if parkour_debug != null:
                parkour_debug.toggle_debug()
        KEY_F2:
            respawn(false)
        KEY_F3:
            teleport_next_platform()
        KEY_F4:
            if parkour_debug != null:
                parkour_debug.toggle_collision()
        KEY_F5:
            if parkour_debug != null:
                parkour_debug.toggle_labels()
        KEY_F6:
            toggle_reference_background()


func enter_parkour() -> void:
    player.use_external_control()
    player.set_interaction_enabled(false)
    active = true
    var order := route.get_order()
    if order.is_empty():
        return
    last_safe_platform = order[0]
    _last_safe_spawn = get_platform(last_safe_platform).get_respawn_position()
    _place_player(_last_safe_spawn)


func exit_parkour() -> void:
    active = false
    player.stop_external_movement()
    player.use_normal_control()
    player.set_interaction_enabled(true)


func respawn(count_as_fall: bool = true) -> void:
    if count_as_fall:
        fall_count += 1
    _place_player(_last_safe_spawn)
    player_respawned.emit(last_safe_platform)


func teleport_next_platform() -> void:
    var order := route.get_order()
    var current_index := route.get_progress_index(current_platform)
    var next_index := clampi(current_index + 1, 0, order.size() - 1)
    debug_teleport_to_platform(order[next_index])


func debug_teleport_to_platform(platform_id: StringName) -> void:
    var platform := get_platform(platform_id)
    if platform == null:
        return
    platform.reset_landing_guard()
    _place_player(platform.get_respawn_position())
    platform.debug_register_landing(player)


func reset_run_for_test() -> void:
    current_platform = &""
    last_safe_platform = &""
    highest_progress = -1
    actual_route.clear()
    fall_count = 0
    _main_completion_emitted = false
    _advanced_completion_emitted = false
    motor.reset_counters()
    for platform in _platforms.values():
        platform.reset_landing_guard()
    var start_id := route.get_order()[0]
    var start_platform := get_platform(start_id)
    last_safe_platform = start_id
    _last_safe_spawn = start_platform.get_respawn_position()
    _place_player(_last_safe_spawn)
    start_platform.debug_register_landing(player)


func toggle_reference_background() -> void:
    if art_background == null or layout_background == null:
        return
    _layout_background_visible = not _layout_background_visible
    art_background.visible = not _layout_background_visible
    layout_background.visible = _layout_background_visible


func get_platform(platform_id: StringName) -> ParkourPlatform:
    return _platforms.get(platform_id) as ParkourPlatform


func get_debug_text() -> String:
    return "Position: (%.1f, %.1f)\nVelocity: (%.1f, %.1f)\nGrounded: %s\nCurrent Platform: %s\nLast Safe Platform: %s\nCoyote Timer: %.3f\nJump Buffer Timer: %.3f\nJump Count: %d\nFall Count: %d\nHighest Progress: %d\nActual Route: %s" % [
        player.global_position.x,
        player.global_position.y,
        player.velocity.x,
        player.velocity.y,
        str(player.is_on_floor()),
        str(current_platform),
        str(last_safe_platform),
        motor.coyote_timer,
        motor.jump_buffer_timer,
        motor.jump_count,
        fall_count,
        highest_progress,
        " → ".join(actual_route),
    ]


func _configure_route() -> void:
    for child in platforms_root.get_children():
        if not child is ParkourPlatform:
            continue
        var platform := child as ParkourPlatform
        var data := route.get_platform_data(platform.platform_id)
        if data.is_empty():
            push_error("Parkour route has no data for platform %s" % platform.platform_id)
            continue
        platform.configure(data, design_size)
        platform.platform_landed.connect(_on_platform_landed)
        _platforms[platform.platform_id] = platform


func _configure_backgrounds() -> void:
    for candidate in [art_background, layout_background]:
        var sprite := candidate as Sprite2D
        if sprite == null or sprite.texture == null:
            continue
        var texture_size: Vector2 = sprite.texture.get_size()
        var uniform_scale := minf(design_size.x / texture_size.x, design_size.y / texture_size.y)
        sprite.position = design_size * 0.5
        sprite.scale = Vector2.ONE * uniform_scale
    if art_background != null:
        art_background.visible = true
    if layout_background != null:
        layout_background.visible = false


func _on_platform_landed(platform_id: StringName) -> void:
    var platform := get_platform(platform_id)
    if platform == null:
        return
    current_platform = platform_id
    if actual_route.is_empty() or actual_route[-1] != platform_id:
        actual_route.append(platform_id)
    highest_progress = maxi(highest_progress, route.get_progress_index(platform_id))
    if platform.checkpoint_enabled:
        last_safe_platform = platform_id
        _last_safe_spawn = platform.get_respawn_position()

    if route.profile == 0 and platform_id == &"J4" and not _main_completion_emitted:
        _main_completion_emitted = true
        parkour_main_route_completed.emit()
    if route.profile == 0 and platform_id == &"J5" and not _advanced_completion_emitted:
        _advanced_completion_emitted = true
        parkour_advanced_route_completed.emit()


func _place_player(target_position: Vector2) -> void:
    player.global_position = target_position
    player.velocity = Vector2.ZERO
    player.stop_external_movement()
    motor.reset_motion()
    player.set_external_velocity(Vector2.ZERO)
