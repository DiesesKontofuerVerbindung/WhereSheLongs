extends Node

signal flag_changed(key: StringName, value: Variant)
signal flag_erased(key: StringName)
signal flags_cleared

var _flags: Dictionary = {}


func set_flag(key: StringName, value: Variant) -> void:
    _flags[key] = value
    flag_changed.emit(key, value)


func get_flag(key: StringName, default_value: Variant = false) -> Variant:
    return _flags.get(key, default_value)


func has_flag(key: StringName) -> bool:
    return _flags.has(key)


func erase_flag(key: StringName) -> void:
    if _flags.erase(key):
        flag_erased.emit(key)


func clear_flags() -> void:
    _flags.clear()
    flags_cleared.emit()
