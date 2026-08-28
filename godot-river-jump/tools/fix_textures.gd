extends SceneTree

const OUT_PLAYER := "res://assets/characters/player_shadow.png"
const OUT_GUIDE := "res://assets/characters/guide.png"


func _init() -> void:
	_save_player_png()
	_save_guide_png()
	print("textures regenerated")
	quit()


func _save_player_png() -> void:
	var img := Image.create(160, 320, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_fill_circle(img, Vector2(80, 70), 34, Color(0.05, 0.05, 0.06, 1.0))
	_fill_capsule(img, Vector2(80, 145), 42, 88, Color(0.05, 0.05, 0.06, 1.0))
	_fill_circle(img, Vector2(52, 130), 14, Color(0.05, 0.05, 0.06, 1.0))
	_fill_circle(img, Vector2(108, 130), 14, Color(0.05, 0.05, 0.06, 1.0))
	_fill_polygon(img, PackedVector2Array([
		Vector2(44, 118), Vector2(116, 118), Vector2(132, 220), Vector2(80, 250), Vector2(28, 220),
	]), Color(0.04, 0.04, 0.05, 1.0))
	img.save_png(OUT_PLAYER)


func _save_guide_png() -> void:
	var img := Image.create(180, 260, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_fill_glow(img, Vector2(90, 150), 70, Color(1.0, 0.92, 0.55, 0.35))
	_fill_diamond(img, Vector2(90, 150), 34, Color(1.0, 0.96, 0.78, 1.0))
	_fill_soft_blob(img, Vector2(90, 78), 26, Color(0.92, 0.9, 0.82, 0.55))
	img.save_png(OUT_GUIDE)


func _fill_circle(img: Image, center: Vector2, radius: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if Vector2(x, y).distance_to(center) <= radius:
				img.set_pixel(x, y, col)


func _fill_capsule(img: Image, center: Vector2, radius: float, height: float, col: Color) -> void:
	var top := center.y - height * 0.5
	var bottom := center.y + height * 0.5
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x, y)
			if p.y >= top and p.y <= bottom and absf(p.x - center.x) <= radius:
				img.set_pixel(x, y, col)
			elif p.distance_to(Vector2(center.x, top)) <= radius or p.distance_to(Vector2(center.x, bottom)) <= radius:
				img.set_pixel(x, y, col)


func _fill_polygon(img: Image, points: PackedVector2Array, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if _point_in_poly(Vector2(x, y), points):
				img.set_pixel(x, y, col)


func _fill_glow(img: Image, center: Vector2, radius: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x, y).distance_to(center) / radius
			if d <= 1.0:
				var c := col
				c.a *= 1.0 - d
				img.set_pixel(x, y, c)


func _fill_diamond(img: Image, center: Vector2, size: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size * 0.75, 0),
		center + Vector2(0, size),
		center + Vector2(-size * 0.75, 0),
	])
	_fill_polygon(img, pts, col)


func _fill_soft_blob(img: Image, center: Vector2, radius: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x, y).distance_to(center) / radius
			if d <= 1.0:
				var c := col
				c.a *= 1.0 - d * 0.65
				img.set_pixel(x, y, c)


func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in poly.size():
		var a := poly[i]
		var b := poly[j]
		if ((a.y > p.y) != (b.y > p.y)) and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y + 0.0001) + a.x):
			inside = not inside
		j = i
	return inside
