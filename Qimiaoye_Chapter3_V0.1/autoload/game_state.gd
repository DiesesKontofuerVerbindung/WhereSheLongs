extends Node

## 章节三全局状态：已解锁结局与开发验证标记。

signal changed

const SAVE_PATH := "user://chapter3_endings.json"

var unlocked_endings: Array[String] = []
var last_ending: String = ""
var best_ending: String = ""


func _ready() -> void:
    try_load()


func reset() -> void:
    unlocked_endings.clear()
    last_ending = ""
    best_ending = ""
    save_game()
    changed.emit()


func unlock_ending(ending_id: String) -> void:
    last_ending = ending_id
    if not ending_id in unlocked_endings:
        unlocked_endings.append(ending_id)
    best_ending = _best_ending_id()
    changed.emit()
    save_game()


func is_unlocked(ending_id: String) -> bool:
    return ending_id in unlocked_endings


func ending_count() -> int:
    return unlocked_endings.size()


func _best_ending_id() -> String:
    # 按官方推荐顺序判定最佳已解锁结局：C > A > B
    for candidate in ["C", "A", "B"]:
        if candidate in unlocked_endings:
            return candidate
    return ""


func to_dict() -> Dictionary:
    return {
        "unlocked_endings": unlocked_endings,
        "last_ending": last_ending,
        "best_ending": best_ending,
    }


func from_dict(data: Dictionary) -> void:
    var raw: Variant = data.get("unlocked_endings", [])
    if raw is Array:
        unlocked_endings.assign(raw as Array)
    else:
        unlocked_endings.clear()
    last_ending = str(data.get("last_ending", ""))
    best_ending = str(data.get("best_ending", ""))


func save_game() -> void:
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_error("章节三存档失败: %s" % FileAccess.get_open_error())
        return
    file.store_string(JSON.stringify(to_dict(), "\t"))


func try_load() -> bool:
    if not FileAccess.file_exists(SAVE_PATH):
        return false
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        return false
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        return false
    from_dict(parsed)
    return true
