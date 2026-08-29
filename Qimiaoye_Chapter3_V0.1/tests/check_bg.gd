extends SceneTree


func _init() -> void:
    var paths := [
        "res://assets/backgrounds/场景转换后的妈妈.png",
        "res://assets/backgrounds/正式婚礼现场.png",
        "res://assets/backgrounds/静谧走廊.png",
        "res://assets/backgrounds/小凌思羽窗边谈话.png",
        "res://assets/backgrounds/小凌思羽窗边谈话-1.png",
        "res://assets/backgrounds/小凌思羽窗边谈话-2.png",
        "res://assets/backgrounds/结局A带头纱的婚礼现场.jpg",
        "res://assets/backgrounds/结局A不带头纱结婚照.jpg",
        "res://assets/backgrounds/结局B 光腿在地毯上奔跑.png",
        "res://assets/backgrounds/结局BC阳光下奔跑.png",
        "res://assets/backgrounds/结局B 光腿在地毯上奔跑-1.png",
        "res://assets/backgrounds/结局C女主离开，思羽看着她.png",
        "res://assets/videos/opening_video.ogv",
    ]
    for p in paths:
        var exists := ResourceLoader.exists(p)
        var tex = load(p) if exists else null
        var detail := ""
        if tex is Texture2D:
            detail = " %dx%d" % [(tex as Texture2D).get_width(), (tex as Texture2D).get_height()]
        elif tex != null:
            detail = " %s" % (tex as Object).get_class()
        print("BG_CHECK exists=%s loaded=%s%s  %s" % [str(exists), str(tex != null), detail, p])
    quit(0)
