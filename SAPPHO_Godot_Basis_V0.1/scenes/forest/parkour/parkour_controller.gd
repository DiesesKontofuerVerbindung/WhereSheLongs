extends Node2D
class_name ParkourController

signal segment_01_completed
signal segment_02_completed(choice: StringName)
signal segment_03_completed(choice: StringName)
signal parkour_completed
signal player_respawned(checkpoint_id: StringName)

@export var design_size := Vector2(1920.0, 1080.0)
@export var kill_y := 1180.0
@export var player_path: NodePath = ^"Player"
@export var motor_path: NodePath = ^"ParkourMotor"
@export var route_path: NodePath = ^"ParkourRoute"
@export var platforms_path: NodePath = ^"Gameplay/Segment01_Platforms"
@export var debug_path: NodePath = ^"ParkourDebug"
@export var art_background_path: NodePath = ^"Background/Art"
@export var layout_background_path: NodePath = ^"Background/LayoutReference"
@export var camera_path: NodePath = ^"DesignCamera"
@export var eye_transition_path: NodePath = ^"EyeTransition"
@export var vine_gate_path: NodePath = ^"Gameplay/Segment02_Vines/VineGate"
@export var vine_gate_b_path: NodePath = ^"Gameplay/Segment02_Vines/VineB"
@export var vine_echo_path: NodePath = ^"VineEchoCoordinator"
@export var predator_plant_path: NodePath = ^"Gameplay/Segment03_PredatorPlant/PredatorPlant"
@export var predator_plant_b_path: NodePath = ^"Gameplay/Segment03_PredatorPlant/PredatorPlantB"
@export var predator_plant_c_path: NodePath = ^"Gameplay/Segment03_PredatorPlant/PredatorPlantC"
@export var amai_path: NodePath = ^"AmaiPlaceholder"

var current_platform: StringName = &""
var last_safe_platform: StringName = &""
var highest_progress := -1
var actual_route: Array[StringName] = []
var player_choices: Array[StringName] = []
var current_segment := 1
var fall_count := 0
var active := false

var _last_safe_spawn := Vector2.ZERO
var _layout_background_visible := false
var _transitioning := false
var _parkour_completed_emitted := false
var _vine_choice: StringName = &""
var _plant_choice: StringName = &""
var _platforms: Dictionary = {}
var _original_player_shape: Shape2D
var _slide_player_shape: Shape2D
var _original_collision_position := Vector2.ZERO
var _slide_collision_position := Vector2.ZERO

@onready var player: CharacterBody2D = get_node(player_path)
@onready var player_collision: CollisionShape2D = player.get_node("CollisionShape2D")
@onready var motor: ParkourMotor = get_node(motor_path)
@onready var route: ParkourRoute = get_node(route_path)
@onready var platforms_root: Node = get_node(platforms_path)
@onready var parkour_debug: Node = get_node_or_null(debug_path)
@onready var art_background: Sprite2D = get_node_or_null(art_background_path)
@onready var layout_background: Sprite2D = get_node_or_null(layout_background_path)
@onready var design_camera: Camera2D = get_node_or_null(camera_path)
@onready var eye_transition: ParkourEyeTransition = get_node_or_null(eye_transition_path)
@onready var vine_gate: ParkourVineGate = get_node_or_null(vine_gate_path)
@onready var vine_gate_b: ParkourVineGate = get_node_or_null(vine_gate_b_path)
@onready var vine_echo: Node = get_node_or_null(vine_echo_path)
@onready var predator_plant: ParkourPredatorPlant = get_node_or_null(predator_plant_path)
@onready var predator_plant_b: ParkourPredatorPlant = get_node_or_null(predator_plant_b_path)
@onready var predator_plant_c: ParkourPredatorPlant = get_node_or_null(predator_plant_c_path)
@onready var amai: AmaiParkourPlaceholder = get_node_or_null(amai_path)


func _ready() -> void:
    process_physics_priority = -100
    _configure_route()
    _configure_backgrounds()
    _setup_player_collider()
    _connect_segment_nodes()
    var player_camera := player.get_node_or_null("Camera2D") as Camera2D
    if player_camera != null:
        player_camera.enabled = false
    enter_parkour()


func _exit_tree() -> void:
    if is_instance_valid(player):
        exit_parkour()


func _physics_process(delta: float) -> void:
    if not active or _transitioning:
        return
    if player.global_position.y > kill_y:
        respawn(true)
        return
    if current_segment == 2 and vine_echo != null and vine_echo.is_active():
        return

    motor.velocity = player.velocity
    var desired_velocity := motor.step(
        delta,
        Input.get_axis("move_left", "move_right"),
        Input.is_action_just_pressed("jump"),
        Input.is_action_pressed("jump"),
        Input.is_action_just_released("jump"),
        player.is_on_floor(),
        Input.is_action_pressed("move_down")
    )
    _set_slide_state(motor.is_sliding)
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
            debug_progress_next()
        KEY_F4:
            if parkour_debug != null:
                parkour_debug.toggle_collision()
        KEY_F5:
            if parkour_debug != null:
                parkour_debug.toggle_labels()
        KEY_F6:
            toggle_reference_background()


func enter_parkour() -> void:
    if vine_echo != null:
        vine_echo.stop_run(false)
    _set_amai_echo_mode(false)
    player.use_external_control()
    player.set_interaction_enabled(false)
    active = true
    current_segment = 1
    if design_camera != null:
        design_camera.position = route.get_segment_center(1)
    var order := route.get_order()
    if order.is_empty():
        return
    last_safe_platform = order[0]
    var start_platform := get_platform(last_safe_platform)
    if start_platform != null:
        _last_safe_spawn = start_platform.get_respawn_position()
    else:
        _last_safe_spawn = route.get_segment_spawn(1)
    _place_player(_last_safe_spawn)
    if amai != null:
        amai.reset_to_segment(1)


func exit_parkour() -> void:
    active = false
    if vine_echo != null:
        vine_echo.stop_run(false)
    _set_amai_echo_mode(false)
    _set_slide_state(false)
    player.stop_external_movement()
    player.use_normal_control()
    player.set_interaction_enabled(true)


func respawn(count_as_fall: bool = true) -> void:
    if count_as_fall:
        fall_count += 1
    _set_slide_state(false)
    _place_player(_last_safe_spawn)
    if current_segment == 2 and vine_echo != null:
        vine_echo.begin_run()
    if amai != null:
        amai.reset_to_segment(current_segment)
    player_respawned.emit(last_safe_platform)


func debug_progress_next() -> void:
    if route.profile != 0:
        teleport_next_platform()
        return
    if current_segment == 1 and current_platform != &"J4":
        teleport_next_platform()
    elif current_segment == 1:
        transition_to_segment(2)
    elif current_segment == 2:
        transition_to_segment(3)
    elif current_segment == 3:
        complete_parkour()


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


func debug_jump_to_segment(segment_index: int) -> void:
    if segment_index == current_segment:
        return
    await transition_to_segment(segment_index)


func debug_set_slide(enabled: bool) -> void:
    if current_segment == 2 and vine_echo != null and vine_echo.is_active():
        vine_echo.debug_set_player_slide(enabled)
        return
    motor.is_sliding = enabled
    _set_slide_state(enabled)


func debug_complete_parkour() -> void:
    await complete_parkour()


func transition_to_segment(next_segment: int) -> void:
    if route.profile != 0 or _transitioning or next_segment < 2 or next_segment > 3:
        return
    _transitioning = true
    var previous_segment := current_segment
    if previous_segment == 2 and vine_echo != null:
        vine_echo.stop_run(false)
        _set_amai_echo_mode(false)
    var carried_speed := maxf(absf(player.velocity.x), 180.0)
    _set_slide_state(false)
    player.stop_external_movement()
    motor.velocity = Vector2.ZERO
    var caption := "藤蔓区 · PLACEHOLDER" if next_segment == 2 else "会动的植物 · PLACEHOLDER"
    if eye_transition != null:
        await eye_transition.close_eyes(caption)

    current_segment = next_segment
    if design_camera != null:
        design_camera.position = route.get_segment_center(next_segment)
    var checkpoint_id: StringName = &"S2_START" if next_segment == 2 else &"S3_START"
    _set_checkpoint(checkpoint_id, route.get_segment_spawn(next_segment))
    _place_player(_last_safe_spawn)
    motor.velocity = Vector2(carried_speed, 0.0)
    player.set_external_velocity(motor.velocity)
    if amai != null:
        amai.reset_to_segment(next_segment)
    if next_segment == 2:
        _set_amai_echo_mode(true)
        if vine_echo != null:
            vine_echo.begin_run()

    if previous_segment == 1:
        segment_01_completed.emit()
    elif previous_segment == 2:
        segment_02_completed.emit(_vine_choice)
    if eye_transition != null:
        await eye_transition.open_eyes()
    _transitioning = false


func complete_parkour() -> void:
    if route.profile != 0 or _transitioning or _parkour_completed_emitted:
        return
    _transitioning = true
    _set_slide_state(false)
    player.stop_external_movement()
    motor.velocity = Vector2.ZERO
    if eye_transition != null:
        await eye_transition.close_eyes("跑酷完成\nWATERFALL INTRO · PLACEHOLDER")
    current_segment = 4
    if design_camera != null:
        design_camera.position = Vector2(6720.0, 540.0)
    _place_player(Vector2(6150.0, 850.0))
    _parkour_completed_emitted = true
    segment_03_completed.emit(_plant_choice)
    parkour_completed.emit()
    if eye_transition != null:
        await eye_transition.open_eyes()
    _transitioning = false
    active = false
    player.lock_control()


func reset_run_for_test() -> void:
    current_platform = &""
    last_safe_platform = &""
    highest_progress = -1
    actual_route.clear()
    player_choices.clear()
    current_segment = 1
    fall_count = 0
    _transitioning = false
    _parkour_completed_emitted = false
    _vine_choice = &""
    _plant_choice = &""
    if vine_echo != null:
        vine_echo.stop_run(false)
    _set_amai_echo_mode(false)
    motor.reset_counters()
    if vine_gate != null:
        vine_gate.reset_choice()
    if vine_gate_b != null:
        vine_gate_b.reset_choice()
    if predator_plant != null:
        predator_plant.reset_choice()
    if predator_plant_b != null:
        predator_plant_b.reset_choice()
    if predator_plant_c != null:
        predator_plant_c.reset_choice()
    for platform in _platforms.values():
        platform.reset_landing_guard()
    if design_camera != null:
        design_camera.position = route.get_segment_center(1)
    player.use_external_control()
    player.set_interaction_enabled(false)
    active = true
    var start_id := route.get_order()[0]
    var start_platform := get_platform(start_id)
    last_safe_platform = start_id
    _last_safe_spawn = start_platform.get_respawn_position()
    _place_player(_last_safe_spawn)
    start_platform.debug_register_landing(player)
    if amai != null:
        amai.reset_to_segment(1)


func toggle_reference_background() -> void:
    if art_background == null or layout_background == null:
        return
    _layout_background_visible = not _layout_background_visible
    art_background.visible = not _layout_background_visible
    layout_background.visible = _layout_background_visible


func get_platform(platform_id: StringName) -> ParkourPlatform:
    return _platforms.get(platform_id) as ParkourPlatform


func get_debug_text() -> String:
    var plant_state := predator_plant.get_state_name() if predator_plant != null else "N/A"
    var plant_b_state := predator_plant_b.get_state_name() if predator_plant_b != null else "N/A"
    var plant_c_state := predator_plant_c.get_state_name() if predator_plant_c != null else "N/A"
    var amai_state := amai.get_debug_state_text() if amai != null else "N/A"
    return "Segment: %d\nPosition: (%.1f, %.1f)\nVelocity: (%.1f, %.1f)\nGrounded: %s\nSliding: %s\nCurrent Platform: %s\nLast Checkpoint: %s\nCoyote Timer: %.3f\nJump Buffer Timer: %.3f\nJump Count: %d\nFall Count: %d\nPlant A/B/C: %s / %s / %s\nAmai: %s\nChoices: %s\nActual Route: %s" % [
        current_segment,
        player.global_position.x,
        player.global_position.y,
        player.velocity.x,
        player.velocity.y,
        str(player.is_on_floor()),
        str(motor.is_sliding),
        str(current_platform),
        str(last_safe_platform),
        motor.coyote_timer,
        motor.jump_buffer_timer,
        motor.jump_count,
        fall_count,
        plant_state,
        plant_b_state,
        plant_c_state,
        amai_state,
        " → ".join(player_choices),
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


func _setup_player_collider() -> void:
    _original_collision_position = player_collision.position
    _original_player_shape = player_collision.shape.duplicate()
    _slide_player_shape = player_collision.shape.duplicate()
    if _slide_player_shape is CapsuleShape2D:
        var original_capsule := _original_player_shape as CapsuleShape2D
        var slide_capsule := _slide_player_shape as CapsuleShape2D
        slide_capsule.height = maxf(slide_capsule.radius * 2.0, original_capsule.height - 10.0)
        _slide_collision_position = _original_collision_position + Vector2(0.0, (original_capsule.height - slide_capsule.height) * 0.5)
    elif _slide_player_shape is RectangleShape2D:
        var original_rectangle := _original_player_shape as RectangleShape2D
        var slide_rectangle := _slide_player_shape as RectangleShape2D
        slide_rectangle.size.y = original_rectangle.size.y * 0.6
        _slide_collision_position = _original_collision_position + Vector2(0.0, (original_rectangle.size.y - slide_rectangle.size.y) * 0.5)


func _connect_segment_nodes() -> void:
    var segment_01_exit := get_node_or_null("Gameplay/SectionTransitions/Segment01Exit") as Area2D
    var segment_02_exit := get_node_or_null("Gameplay/SectionTransitions/Segment02Exit") as Area2D
    var segment_03_finish := get_node_or_null("Gameplay/SectionTransitions/Segment03Finish") as Area2D
    var s2_checkpoint := get_node_or_null("Gameplay/Checkpoints/S2AfterVine") as Area2D
    var s3_checkpoint := get_node_or_null("Gameplay/Checkpoints/S3AfterPlant") as Area2D
    if segment_01_exit != null:
        segment_01_exit.body_entered.connect(_on_segment_01_exit_entered)
    if segment_02_exit != null:
        segment_02_exit.body_entered.connect(_on_segment_02_exit_entered)
    if segment_03_finish != null:
        segment_03_finish.body_entered.connect(_on_segment_03_finish_entered)
    if s2_checkpoint != null:
        s2_checkpoint.body_entered.connect(_on_s2_checkpoint_entered)
    if s3_checkpoint != null:
        s3_checkpoint.body_entered.connect(_on_s3_checkpoint_entered)
    if vine_gate != null:
        vine_gate.choice_made.connect(_on_vine_choice)
    if vine_gate_b != null:
        vine_gate_b.choice_made.connect(_on_vine_choice)
    if vine_echo != null:
        vine_echo.gate_action_locked.connect(_on_vine_echo_action_locked)
    if predator_plant != null:
        predator_plant.choice_made.connect(_on_plant_choice)
        predator_plant.hazard_triggered.connect(_on_plant_hazard)
    if predator_plant_b != null:
        predator_plant_b.choice_made.connect(_on_plant_choice)
        predator_plant_b.hazard_triggered.connect(_on_plant_hazard)
    if predator_plant_c != null:
        predator_plant_c.choice_made.connect(_on_plant_choice)
        predator_plant_c.hazard_triggered.connect(_on_plant_hazard)


func _on_platform_landed(platform_id: StringName) -> void:
    var platform := get_platform(platform_id)
    if platform == null:
        return
    current_platform = platform_id
    if actual_route.is_empty() or actual_route[-1] != platform_id:
        actual_route.append(platform_id)
    highest_progress = maxi(highest_progress, route.get_progress_index(platform_id))
    if platform.checkpoint_enabled:
        _set_checkpoint(platform_id, platform.get_respawn_position())


func _on_segment_01_exit_entered(body: Node2D) -> void:
    if body == player and current_segment == 1:
        transition_to_segment.call_deferred(2)


func _on_segment_02_exit_entered(body: Node2D) -> void:
    if body == player and current_segment == 2:
        transition_to_segment.call_deferred(3)


func _on_segment_03_finish_entered(body: Node2D) -> void:
    if body == player and current_segment == 3:
        complete_parkour.call_deferred()


func _on_s2_checkpoint_entered(body: Node2D) -> void:
    if body == player and current_segment == 2:
        _set_checkpoint(&"S2_AFTER_VINE", Vector2(3800.0, 584.0))


func _on_s3_checkpoint_entered(body: Node2D) -> void:
    if body == player and current_segment == 3:
        _set_checkpoint(&"S3_AFTER_PLANT", Vector2(5080.0, 770.0))


func _on_vine_choice(choice: StringName) -> void:
    _vine_choice = choice
    player_choices.append(choice)
    if amai != null:
        amai.record_choice(choice)


func _on_vine_echo_action_locked(_gate_index: int, player_action: int, _amai_echo_action: int) -> void:
    if vine_echo == null:
        return
    _vine_choice = StringName(vine_echo.action_name(player_action))
    player_choices.append(_vine_choice)


func _on_plant_choice(choice: StringName) -> void:
    _plant_choice = choice
    player_choices.append(choice)
    if amai != null:
        amai.record_choice(choice)


func _on_plant_hazard() -> void:
    if current_segment == 3:
        respawn(true)


func _set_checkpoint(checkpoint_id: StringName, spawn_position: Vector2) -> void:
    last_safe_platform = checkpoint_id
    _last_safe_spawn = spawn_position


func _set_slide_state(enabled: bool) -> void:
    if _original_player_shape == null or _slide_player_shape == null:
        return
    player_collision.shape = _slide_player_shape if enabled else _original_player_shape
    player_collision.position = _slide_collision_position if enabled else _original_collision_position
    player.set_meta("parkour_sliding", enabled)
    if not enabled:
        motor.is_sliding = false


func _set_amai_echo_mode(enabled: bool) -> void:
    if amai == null:
        return
    amai.visible = not enabled
    amai.set_physics_process(not enabled)


func _place_player(target_position: Vector2) -> void:
    player.global_position = target_position
    player.velocity = Vector2.ZERO
    player.stop_external_movement()
    motor.reset_motion()
    player.set_external_velocity(Vector2.ZERO)
