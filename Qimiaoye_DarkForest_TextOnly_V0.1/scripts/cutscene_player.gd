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
## 背景填充层的模糊半径与压暗系数。压暗是必要的，
## 不压的话背景和正片一样亮，眼睛会分不清哪块才是画面。
const FILL_BLUR_RADIUS := 0.018
const FILL_DIM := 0.42

## 帧数与帧率跟源视频一一对应，一帧不漏：
## 瀑布下 24fps/4.75s，其余三段 30fps/5.04s。
## 上一版为了压体积做过"源帧率减半 + PNG-8 量化 256 色"，画质就是那么丢的。
## 现在是 WebP q95 真彩色有损，567 帧共 82 MB，普通 git 装得下，不必上 LFS。
## loop=false 的段播完停在最后一帧，等场景切走再淡出。
## 溺水是"小凌在水中不断下沉"，单向动作，首尾接不上，硬循环会看见明显的跳；
## 而且下沉倒放会变成上浮，乒乓也不能用。停在沉到底的那一帧才对，
## 节奏交给玩家读完那几行再按继续。
const CUTSCENES := {
	"waterfall_below": {"frames": 114, "fps": 24.0, "loop": true},
	"lake_talk": {"frames": 151, "fps": 30.0, "loop": true},
	"drowning": {"frames": 151, "fps": 30.0, "loop": false},
	"touch_chest": {"frames": 151, "fps": 30.0, "loop": true},
}

var _frame_view: TextureRect
var _frame_fill: TextureRect
var _backdrop: ColorRect
var _playing_id := ""
var _loop_id := ""
var _loop_starts := {}
var _holding_last_frame := false
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

	# 四段 CG 里两段是 4:3（1120x840、1112x834），两段是 16:9。
	# cropdetect 确认素材本身没有可裁的黑边，4:3 就是画满整幅的 4:3，
	# 所以黑边只能填不能裁：拿画面自身放大模糊后铺满画框当底，
	# 原图按比例居中叠上去。不丢内容、不变形、也没有死黑块。
	_frame_fill = TextureRect.new()
	_frame_fill.name = "CutsceneFrameFill"
	_frame_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_fill.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frame_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_fill.material = _make_fill_blur_material()
	_frame_fill.modulate = Color(FILL_DIM, FILL_DIM, FILL_DIM, 1.0)
	add_child(_frame_fill)

	_frame_view = TextureRect.new()
	_frame_view.name = "CutsceneFrame"
	_frame_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame_view)


## 背景层的模糊。半径按 UV 取，与实际渲染分辨率无关，
## 窗口拉大拉小、以后换分辨率设置都不用重调参数。
func _make_fill_blur_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;

uniform float blur_radius : hint_range(0.0, 0.08) = 0.018;

void fragment() {
	vec4 accum = vec4(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			vec2 offset = vec2(float(x), float(y)) * blur_radius / 3.0;
			float weight = 1.0 - length(vec2(float(x), float(y))) / 5.0;
			weight = max(weight, 0.02);
			accum += texture(TEXTURE, UV + offset) * weight;
			total += weight;
		}
	}
	COLOR = accum / total;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("blur_radius", FILL_BLUR_RADIUS)
	return material


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


## 启动一段循环背景。**不 await 播放本身**——CG 是场景底图，
## 对白要在它上面照常推进，等它播完再走剧情就本末倒置了：
## 人物剧情图1 管 DOCX 138–161 共 23 行，环境背景图7 管 199–309 共 110 行，
## 一段 5 秒的视频播一次就消失，后面上百行照样是空背景。
##
## 循环不做交叉淡化也不做乒乓：美术确认湖边/瀑布是特意做的首尾衔接，
## 直接 loop 就是无缝的，任何额外处理反而破坏他们的巧思。
func play_looping(cutscene_id: String, verify_mode := false) -> void:
	if _loop_id == cutscene_id:
		return
	_last_missing_frames = check_frames(cutscene_id)
	if not _last_missing_frames.is_empty():
		# 缺帧不是崩溃理由：剧情必须能继续走完，缺什么留给日志和 verify 去报。
		push_warning("CG %s 缺 %d 帧，跳过播放" % [cutscene_id, _last_missing_frames.size()])
		return
	_loop_id = cutscene_id
	_holding_last_frame = false
	_loop_starts[cutscene_id] = int(_loop_starts.get(cutscene_id, 0)) + 1
	if verify_mode:
		# verify 只确认资源齐全与启停配对，不能真的挂着一个无限循环。
		_playing_id = cutscene_id
		_played_frames = int(CUTSCENES[cutscene_id]["frames"])
		return
	_playing_id = cutscene_id
	_frame_cache.clear()
	_set_frame_texture(_acquire_frame(cutscene_id, 1))
	visible = true
	await _tween_self_alpha(1.0, FADE_SECONDS)
	var should_loop := bool(CUTSCENES[cutscene_id].get("loop", true))
	while _loop_id == cutscene_id:
		await _play_one_pass(cutscene_id)
		if not should_loop:
			# 停在最后一帧挂着，等 stop_looping() 淡出，别回到第一帧重来。
			_holding_last_frame = true
			return


## 停止当前循环并淡出。场景切走时调用。
func stop_looping(verify_mode := false) -> void:
	if _loop_id.is_empty():
		return
	_loop_id = ""
	_holding_last_frame = false
	if verify_mode:
		_playing_id = ""
		visible = false
		return
	await _tween_self_alpha(0.0, FADE_SECONDS)
	visible = false
	_set_frame_texture(null)
	_frame_cache.clear()
	_playing_id = ""


func _play_one_pass(cutscene_id: String) -> void:
	var frame_count := int(CUTSCENES[cutscene_id]["frames"])
	var fps := float(CUTSCENES[cutscene_id]["fps"])
	var frame_seconds := 1.0 / maxf(fps, 1.0)
	var elapsed := 0.0
	var shown_index := 0
	while shown_index < frame_count:
		# 循环期间场景切走了就立刻收手，别把最后一轮播完再退出。
		if _loop_id != cutscene_id:
			return
		var wanted := clampi(int(elapsed / frame_seconds) + 1, 1, frame_count)
		if wanted != shown_index:
			# 掉帧时按时间轴跳帧，宁可丢画面也不让循环整体拖慢。
			for skipped in range(shown_index, wanted):
				_frame_cache.erase(skipped)
			_set_frame_texture(_acquire_frame(cutscene_id, wanted))
			shown_index = wanted
			_played_frames = wanted
			_prefetch(cutscene_id, wanted, frame_count)
		if shown_index >= frame_count:
			break
		elapsed += await _next_frame_delta()
	_frame_cache.clear()


## 等当前这段播完一整轮。只对 loop=false 的段有意义——loop=true 永远不会停，
## 等它就是死循环。用于 DOCX 196–199 这种两个转场之间没有对白事件的地方：
## 不等的话溺水刚起循环就被 DROWNING_EXIT 停掉，玩家什么都看不到。
func wait_until_pass_done(verify_mode := false) -> void:
	if verify_mode or _loop_id.is_empty():
		return
	if bool(CUTSCENES[_loop_id].get("loop", true)):
		push_warning("wait_until_pass_done 用在循环段 %s 上会一直等下去，已跳过" % _loop_id)
		return
	while not _loop_id.is_empty() and not _holding_last_frame:
		await get_tree().process_frame


func is_looping(cutscene_id := "") -> bool:
	return _loop_id == cutscene_id if not cutscene_id.is_empty() else not _loop_id.is_empty()


func get_loop_start_count(cutscene_id: String) -> int:
	return int(_loop_starts.get(cutscene_id, 0))


## 正片与背景填充层永远用同一张纹理，背景层只是同一帧的放大模糊版。
func _set_frame_texture(texture: Texture2D) -> void:
	_frame_view.texture = texture
	_frame_fill.texture = texture


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
		"cutscene_loop_id": _loop_id,
		"cutscene_holding_last_frame": _holding_last_frame,
		"cutscene_played_frames": _played_frames,
		"cutscene_cached_frames": _frame_cache.size(),
		"cutscene_missing_frames": _last_missing_frames.size(),
		"cutscene_visible": visible,
		"cutscene_alpha": modulate.a,
		"cutscene_fill_active": _frame_fill != null and _frame_fill.material != null,
		"cutscene_fill_stretch_covered": _frame_fill != null and _frame_fill.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
		"cutscene_view_stretch_centered": _frame_view != null and _frame_view.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
	}
