extends BaseExplorationMap


func _build_environment() -> void:
	set_camera_bounds(Rect2(0, 0, 960, 540))
	_add_fill_background(Color("#101b18"), Color("#173a35"))
	_player.global_position = Vector2(200, 400)
	for i in range(5):
		var flower := Polygon2D.new()
		flower.polygon = PackedVector2Array([Vector2(-10, 8), Vector2(0, -12), Vector2(10, 8)])
		flower.color = Color("d67bb5")
		flower.position = Vector2(340 + i * 55, 300 + (i % 2) * 18)
		add_child(flower)
	for i in range(5):
		var stone := Polygon2D.new()
		stone.polygon = PackedVector2Array([Vector2(-14, 5), Vector2(-6, -8), Vector2(14, -5), Vector2(8, 8)])
		stone.color = Color("4f9fc4")
		stone.position = Vector2(620 + i * 55, 330 + (i % 2) * 16)
		add_child(stone)
	await get_tree().process_frame
	_start_path_dialogue()


func _start_path_dialogue() -> void:
	_player.set_can_move(false)
	_show_inline_dialogue([
		{"speaker": "旁白", "text": "左边是一条铺满花瓣的静谧小路。"},
		{"speaker": "旁白", "text": "右边则传来潺潺的水声，黑漆漆的，看不清里面有什么。"},
		{"speaker": "阿麦", "text": "你想走哪边？"},
		{"speaker": "小凌", "text": "不是你带路吗？"},
		{"speaker": "阿麦", "text": "这里没有规定谁带路。"},
		{"speaker": "小凌", "text": "……"},
		{"speaker": "小凌", "text": "（动作：看向左边）"},
		{"speaker": "小凌", "text": "那就左边吧。"},
		{"speaker": "阿麦", "text": "……。"},
		{"speaker": "小凌", "text": "怎么了？"},
		{"speaker": "阿麦", "text": "你真的想走左边？"},
		{"speaker": "小凌", "text": "嗯。"},
		{"speaker": "阿麦", "text": "还是因为它看起来比较安全？"},
		{"speaker": "小凌", "text": "……。"},
		{"speaker": "阿麦", "text": "（动作：指了指右边）"},
		{"speaker": "阿麦", "text": "那边有瀑布。"},
		{"speaker": "小凌", "text": "所以？"},
		{"speaker": "阿麦", "text": "我们可以下去。"},
		{"speaker": "小凌", "text": "下水？"},
		{"speaker": "阿麦", "text": "嗯。"},
		{"speaker": "小凌", "text": "不行。"},
		{"speaker": "阿麦", "text": "为什么？"},
		{"speaker": "小凌", "text": "会弄湿衣服。"},
		{"speaker": "阿麦", "text": "（动作：低头看了一眼她的衣服）：那又怎样？"},
		{"speaker": "小凌", "text": "……"},
		{"speaker": "旁白", "text": "阿麦忽然笑起来。"},
		{"speaker": "旁白", "text": "他没有再问。"},
		{"speaker": "旁白", "text": "只是朝着右边的路跑了起来"},
		{"speaker": "小凌", "text": "喂！"},
		{"speaker": "旁白", "text": "（动作：跑着跟了上去）"},
	], func(): _complete({"result": "success"}))
