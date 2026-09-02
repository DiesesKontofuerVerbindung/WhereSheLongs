extends Node

## 存档文件层。只负责「把一个 Dictionary 安全地落到磁盘再安全地读回来」，
## 不认识章节、节点、结局这些业务概念——那是 ChapterProgress 的事。
##
## 三条硬要求：
##   原子写   先写 .tmp 再 rename 覆盖。断电或崩溃最多丢最后一次改动，
##            绝不会留下半个 JSON 让下次启动读到损坏档。
##   防抖     打点很频繁，不能每次都落盘。标脏后延迟统一写。
##   不崩     文件缺失 / JSON 损坏 / 磁盘只读，一律降级继续，游戏不能因为存档挂掉。

const SAVE_PATH := "user://save.json"
const TEMP_PATH := "user://save.json.tmp"
## river_jump 是另一个原型留下的文件名，首次启动迁一次结局数据就改名归档。
const LEGACY_PATH := "user://river_jump.json"
const LEGACY_ARCHIVED_PATH := "user://river_jump.json.migrated"
const SCHEMA := 1
const FLUSH_DELAY_SECONDS := 1.5

var _data: Dictionary = {}
var _dirty := false
var _flush_timer: SceneTreeTimer
var _write_failed_reported := false
var _loaded := false


func _ready() -> void:
	# 存档在暂停时也要能落盘（ESC 菜单里点退出）。
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		flush()


## 读盘。任何异常都不抛出，只是退化成空档。
func load_from_disk() -> void:
	_loaded = true
	_data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		_migrate_legacy()
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("存档无法读取，按新档处理：%s" % FileAccess.get_open_error())
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		# 损坏档不能静默清空——留证据，再当新档开。
		_quarantine_corrupt(text)
		return
	var loaded: Dictionary = parsed
	# schema 比我们新时只读认识的字段，未知字段原样保留，写回时不丢。
	_data = loaded
	if not _data.has("schema"):
		_data["schema"] = SCHEMA


func _default_data() -> Dictionary:
	return {"schema": SCHEMA, "sections": {}}


func _quarantine_corrupt(text: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var backup := "user://save.corrupt.%s.json" % stamp
	var out := FileAccess.open(backup, FileAccess.WRITE)
	if out != null:
		out.store_string(text)
		out.close()
	push_warning("存档解析失败，已备份到 %s，按新档继续。" % backup)
	_data = _default_data()


## 旧原型的存档里只有结局数据值得留，迁一次就把旧文件改名，避免反复迁移。
func _migrate_legacy() -> void:
	if not FileAccess.file_exists(LEGACY_PATH):
		return
	var file := FileAccess.open(LEGACY_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		var legacy: Dictionary = parsed
		# 原样塞进去：键名必须和 GameState.from_dict 认的一致，
		# 换成别的名字迁过来就读不出来了。
		set_section("endings", legacy)
		flush()
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(LEGACY_PATH),
		ProjectSettings.globalize_path(LEGACY_ARCHIVED_PATH)
	)


func get_section(name: String) -> Dictionary:
	if not _loaded:
		load_from_disk()
	var sections: Variant = _data.get("sections", {})
	if not sections is Dictionary:
		return {}
	var section: Variant = (sections as Dictionary).get(name, {})
	return (section as Dictionary).duplicate(true) if section is Dictionary else {}


## 只标脏，不立刻写。频繁打点时靠 FLUSH_DELAY_SECONDS 合并成一次落盘。
func set_section(name: String, value: Dictionary) -> void:
	if not _loaded:
		load_from_disk()
	if not _data.get("sections") is Dictionary:
		_data["sections"] = {}
	(_data["sections"] as Dictionary)[name] = value.duplicate(true)
	_dirty = true
	_schedule_flush()


func _schedule_flush() -> void:
	if _flush_timer != null:
		return
	if not is_inside_tree():
		return
	# process_always=true：暂停时也要能落盘。
	_flush_timer = get_tree().create_timer(FLUSH_DELAY_SECONDS, true)
	_flush_timer.timeout.connect(_on_flush_timeout)


func _on_flush_timeout() -> void:
	_flush_timer = null
	flush()


func flush() -> void:
	if not _dirty:
		return
	_data["schema"] = SCHEMA
	_data["game_version"] = ProjectSettings.get_setting("application/config/version", "")
	_data["saved_at"] = Time.get_datetime_string_from_system(true)

	# 原子写：整份内容先落到 .tmp，关闭之后再 rename 覆盖正式档。
	var tmp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if tmp == null:
		if not _write_failed_reported:
			_write_failed_reported = true
			push_warning("进度无法保存（磁盘只读或无权限）：%s" % FileAccess.get_open_error())
		return
	tmp.store_string(JSON.stringify(_data, "\t"))
	tmp.close()
	var rename_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TEMP_PATH),
		ProjectSettings.globalize_path(SAVE_PATH)
	)
	if rename_error != OK:
		if not _write_failed_reported:
			_write_failed_reported = true
			push_warning("存档改名失败：%d" % rename_error)
		return
	_dirty = false
	_write_failed_reported = false


func clear_all() -> void:
	_data = _default_data()
	_dirty = true
	flush()


func has_write_error() -> bool:
	return _write_failed_reported
