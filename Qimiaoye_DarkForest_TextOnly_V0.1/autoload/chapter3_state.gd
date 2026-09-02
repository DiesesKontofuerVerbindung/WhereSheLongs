extends Node

## 章节三全局状态：已解锁结局与开发验证标记。

signal changed

const SAVE_PATH := "user://chapter3_endings.json"
const SECTION := "chapter3_endings"

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


## 存档统一走 SaveStore：原子写、防抖、损坏恢复都在那一层。
## 这里只负责把自己的数据塞进对应的段，不再单独开一个文件——
## 之前 river_jump.json / chapter3_endings.json / save.json 三份并存，
## 结局写在旧文件里、进度写在新文件里，读出来必然对不上。
func save_game() -> void:
    SaveStore.set_section(SECTION, to_dict())


func try_load() -> bool:
    var section := SaveStore.get_section(SECTION)
    if section.is_empty():
        return false
    from_dict(section)
    return true
