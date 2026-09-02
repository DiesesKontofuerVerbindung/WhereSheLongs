extends RefCounted

## 场景回溯面板的**显示名**覆盖表。键是 "<章节id>:<DOCX行号>"。
##
## 这张表只管好不好听，不管对不对位——节点本身是从事件表筛出来的，
## 这里缺一条只会退回事件自带的名字（多半是美术资产名，能看但不好听），
## 写错一条也只是名字难看，不会让跳转落到错的地方。
## 所以随便改，不用怕。

const OVERRIDES := {
	# 森林正片
	"forest:29": "走进黑暗森林",
	"forest:122": "藤蔓与回声",
	"forest:141": "瀑布前",
	"forest:157": "把杂念挥开",
	"forest:193": "跳进湖里",
	"forest:238": "装进星星的瓶子",
	"forest:309": "那些留在身后的东西",
	"forest:352": "摊开的手",
	"forest:353": "看清掌心",
	"forest:359": "两只手松开",
	"forest:366": "世界关上了门",
}


static func lookup(chapter_id: String, source: int) -> String:
	return str(OVERRIDES.get("%s:%d" % [chapter_id, source], ""))
