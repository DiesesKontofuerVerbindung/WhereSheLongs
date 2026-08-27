extends Node
class_name ParkourRoute

const DESIGN_SIZE := Vector2(1920.0, 1080.0)
const FOREST_ORDER: Array[StringName] = [&"J1", &"J2", &"J3", &"J3_5", &"J4", &"J5"]
const MECHANICS_ORDER: Array[StringName] = [&"A", &"B", &"C", &"D"]

# Position is the fixed route anchor. Collision offset/size is the tunable gameplay layer.
const FOREST_DATA := {
    &"J1": {
        "normalized_position": Vector2(0.20, 0.84),
        "collision_offset": Vector2(0.0, 0.0),
        "collision_size": Vector2(260.0, 34.0),
        "landing_sensor_size": Vector2(230.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"J2": {
        "normalized_position": Vector2(0.34, 0.69),
        "collision_offset": Vector2(0.0, 9.0),
        "collision_size": Vector2(210.0, 28.0),
        "landing_sensor_size": Vector2(185.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"J3": {
        "normalized_position": Vector2(0.54, 0.82),
        "collision_offset": Vector2(0.0, -5.0),
        "collision_size": Vector2(330.0, 40.0),
        "landing_sensor_size": Vector2(300.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"J3_5": {
        "normalized_position": Vector2(0.61, 0.63),
        "collision_offset": Vector2(0.0, -26.0),
        "collision_size": Vector2(150.0, 28.0),
        "landing_sensor_size": Vector2(140.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"J4": {
        "normalized_position": Vector2(0.76, 0.54),
        "collision_offset": Vector2(0.0, 14.0),
        "collision_size": Vector2(300.0, 34.0),
        "landing_sensor_size": Vector2(270.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"J5": {
        "normalized_position": Vector2(0.67, 0.28),
        "collision_offset": Vector2(0.0, 16.0),
        "collision_size": Vector2(230.0, 34.0),
        "landing_sensor_size": Vector2(205.0, 14.0),
        "checkpoint_enabled": true,
    },
}

const MECHANICS_DATA := {
    &"A": {
        "normalized_position": Vector2(0.12, 0.82),
        "collision_offset": Vector2.ZERO,
        "collision_size": Vector2(280.0, 34.0),
        "landing_sensor_size": Vector2(250.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"B": {
        "normalized_position": Vector2(0.32, 0.72),
        "collision_offset": Vector2.ZERO,
        "collision_size": Vector2(230.0, 34.0),
        "landing_sensor_size": Vector2(205.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"C": {
        "normalized_position": Vector2(0.52, 0.82),
        "collision_offset": Vector2.ZERO,
        "collision_size": Vector2(270.0, 34.0),
        "landing_sensor_size": Vector2(245.0, 14.0),
        "checkpoint_enabled": true,
    },
    &"D": {
        "normalized_position": Vector2(0.72, 0.70),
        "collision_offset": Vector2.ZERO,
        "collision_size": Vector2(260.0, 34.0),
        "landing_sensor_size": Vector2(235.0, 14.0),
        "checkpoint_enabled": true,
    },
}

@export_enum("Forest", "Mechanics") var profile := 0


func get_order() -> Array[StringName]:
    return FOREST_ORDER.duplicate() if profile == 0 else MECHANICS_ORDER.duplicate()


func get_platform_data(platform_id: StringName) -> Dictionary:
    var source: Dictionary = FOREST_DATA if profile == 0 else MECHANICS_DATA
    return source.get(platform_id, {}).duplicate(true)


func get_world_position(platform_id: StringName) -> Vector2:
    var data := get_platform_data(platform_id)
    return data.get("normalized_position", Vector2.ZERO) * DESIGN_SIZE


func get_progress_index(platform_id: StringName) -> int:
    return get_order().find(platform_id)
