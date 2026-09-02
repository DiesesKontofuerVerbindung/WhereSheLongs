extends RefCounted

## 场景回溯面板的**显示名**覆盖表。键是 "<章节id>:<DOCX行号>"。
##
## 这张表只管好不好听，不管对不对位——节点本身是从事件表筛出来的，
## 这里缺一条只会退回事件自带的名字（多半是美术资产名，能看但不好听），
## 写错一条也只是名字难看，不会让跳转落到错的地方。
## 所以随便改，不用怕。

const OVERRIDES := {
	# 婚礼前夜
	# 这四条原本回落到事件 id，面板里会直接显示英文——module / endpoint 事件
	# 没有 name 字段，_raw_name 只能拿 id 顶上。
	"wedding:21": "独自念誓词",
	"wedding:32": "手机上的消息",
	"wedding:107": "客厅里的东西",
	"wedding:145": "婚礼前夜结束",

	# 森林正片
	"forest:29": "走进黑暗森林",
	"forest:122": "跑酷",
	"forest:141": "瀑布前",
	"forest:157": "把杂念挥开",
	"forest:193": "跳进湖里",
	"forest:238": "装进星星的瓶子",
	"forest:309": "那些留在身后的东西",
	"forest:352": "摊开的手",
	"forest:353": "看清掌心",
	"forest:359": "两只手松开",
	"forest:366": "世界关上了门",

	# 典礼上的选择
	# 原名是「结局A-带头纱的婚礼现场」这类美术资产名：既带拉丁字母，
	# 又把结局直接写在了还没解锁的格子旁边，等于剧透。换成只描述画面、
	# 不点破结果的说法。文案是草稿，随时改。
	"chapter3:1100": "戴上头纱",
	"chapter3:1107": "那张结婚照",
	"chapter3:1123": "在地毯上跑起来",
	"chapter3:1131": "阳光下奔跑",
	"chapter3:1164": "一直跑下去",
	"chapter3:1168": "她走了，他看着",
}


static func lookup(chapter_id: String, source: int) -> String:
	return str(OVERRIDES.get("%s:%d" % [chapter_id, source], ""))
