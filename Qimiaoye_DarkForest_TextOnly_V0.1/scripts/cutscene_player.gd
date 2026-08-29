extends Control
class_name CutscenePlayer

## 序列帧 CG 播放器。
##
## 本机总内存 7.8 GB，小凌一套 SpriteFrames 已经占掉约 800 MB，
## 所以这里不做 SpriteFrames / 全量预载：单段 76 帧 1280x720 解压后约 266 MB，
## 与角色贴图叠加会直接把内存打穿。改为滑动窗口按需 load()，
## 播过的帧立即从缓存擦除，整段播完再清空。

const FRAME_ROOT := "res://assets/cutscenes"
const FADE_SECONDS := 0.35
## 预读多少帧。太小会在硬盘慢时卡顿，太大就失去了流式加载的意义。
const PREFETCH_AHEAD := 6

## 帧数与帧率跟源视频一一对应，一帧不漏：
## 瀑布下 24fps/4.75s，其余三段 30fps/5.04s。
## 上一版为了压体积做过"源帧率减半 + PNG-8 量化 256 色"，画质就是那么丢的。
## 现在是 WebP q95 真彩色有损，567 帧共 82 MB，普通 git 装得下，不必上 LFS。
const CUTSCENES := {
	"waterfall_below": {"frames": 114, "fps": 24.0},
	"lake_talk": {"frames": 151, "fps": 30.0},
	"drowning": {"frames": 151, "fps": 30.0},
	"touch_chest": {"frames": 151, "fps": 30.0},
}

var _frame_view: TextureRect
var _backdrop: ColorRect
var _playing_id := ""
var _played_frames := 0
var _last_missing_frames := PackedStringArray()
var _frame_cache := {}


func _ready() -> void:
	name = "CutscenePlayer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0

	_backdrop = ColorRect.new()
	_backdrop.name = "CutsceneBackdrop"
	_backdrop.color = Color.BLACK
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)

	_frame_view = TextureRect.new()
	_frame_view.name = "CutsceneFrame"
	_frame_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_view)


func has_cutscene(cutscene_id: String) -> bool:
	return CUTSCENES.has(cutscene_id)


func frame_path(cutscene_id: String, frame_index: int) -> String:
	return "%s/%s/%s_%03d.webp" % [FRAME_ROOT, cutscene_id, cutscene_id, frame_index]


## 校验整段序列帧是否齐全，返回缺失帧路径。verify 流程用它替代真正播放。
func check_frames(cutscene_id: String) -> PackedStringArray:
	var missing := PackedStringArray()
	if not CUTSCENES.has(cutscene_id):
		missing.append("未登记的 CG：%s" % cutscene_id)
		return missing
	var frame_count := int(CUTSCENES[cutscene_id]["frames"])
	for index in range(1, frame_count + 1):
		var path := frame_path(cutscene_id, index)
		if not ResourceLoader.exists(path):
			missing.append(path)
	return missing


func play(cutscene_id: String, verify_mode := false) -> void:
	_last_missing_frames = check_frames(cutscene_id)
	if not _last_missing_frames.is_empty():
		# 缺帧不是崩溃理由：剧情必须能继续走完，缺什么留给日志和 verify 去报。
		push_warning("CG %s 缺 %d 帧，跳过播放" % [cutscene_id, _last_missing_frames.size()])
		return
	if verify_mode:
		# verify 只确认资源齐全，不能真的占用 5 秒和几百 MB。
		_playing_id = cutscene_id
		_played_frames = int(CUTSCENES[cutscene_id]["frames"])
		_playing_id = ""
		return

	var frame_count := int(CUTSCENES[cutscene_id]["frames"])
	var fps := float(CUTSCENES[cutscene_id]["fps"])
	_playing_id = cutscene_id
	_played_frames = 0
	_frame_cache.clear()

	_frame_view.texture = _acquire_frame(cutscene_id, 1)
	visible = true
	await _tween_self_alpha(1.0, FADE_SECONDS)

	var frame_seconds := 1.0 / maxf(fps, 1.0)
	var elapsed := 0.0
	var shown_index := 0
	while shown_index < frame_count:
		var wanted := clampi(int(elapsed / frame_seconds) + 1, 1, frame_count)
		if wanted != shown_index:
			# 掉帧时按时间轴跳帧，宁可丢画面也不让 CG 整体拖长。
			for skipped in range(shown_index, wanted):
				_frame_cache.erase(skipped)
			_frame_view.texture = _acquire_frame(cutscene_id, wanted)
			shown_index = wanted
			_played_frames = wanted
			_prefetch(cutscene_id, wanted, frame_count)
		if shown_index >= frame_count:
			break
		elapsed += await _next_frame_delta()

	await _tween_self_alpha(0.0, FADE_SECONDS)
	visible = false
	_frame_view.texture = null
	_frame_cache.clear()
	_playing_id = ""


func _acquire_frame(cutscene_id: String, frame_index: int) -> Texture2D:
	if _frame_cache.has(frame_index):
		return _frame_cache[frame_index]
	var texture := load(frame_path(cutscene_id, frame_index)) as Texture2D
	if texture != null:
		_frame_cache[frame_index] = texture
	return texture


func _prefetch(cutscene_id: String, from_index: int, frame_count: int) -> void:
	var last := mini(from_index + PREFETCH_AHEAD, frame_count)
	for index in range(from_index + 1, last + 1):
		_acquire_frame(cutscene_id, index)


func _next_frame_delta() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _tween_self_alpha(target_alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", target_alpha, duration)
	await tween.finished


func get_debug_snapshot() -> Dictionary:
	return {
		"cutscene_playing": _playing_id,
		"cutscene_played_frames": _played_frames,
		"cutscene_cached_frames": _frame_cache.size(),
		"cutscene_missing_frames": _last_missing_frames.size(),
		"cutscene_visible": visible,
		"cutscene_alpha": modulate.a,
	}
