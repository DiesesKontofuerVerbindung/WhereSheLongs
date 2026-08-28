extends SceneTree

const OUT_GUIDE := "res://assets/characters/guide.png"


func _init() -> void:
	_save_guide_png()
	print("guide texture regenerated")
	quit()


func _save_guide_png() -> void:
	var img := Image.create(200, 280, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_fill_glow(img, Vector2(100, 170), 85, Color(1.0, 0.88, 0.35, 0.55))
	_fill_glow(img, Vector2(100, 170), 55, Color(1.0, 0.95, 0.65, 0.75))
	_fill_diamond(img, Vector2(100, 170), 42, Color(1.0, 0.98, 0.82, 1.0))
	_fill_circle(img, Vector2(100, 95), 32, Color(0.95, 0.92, 0.82, 0.75))
	_fill_circle(img, Vector2(100, 70), 22, Color(1.0, 0.96, 0.88, 0.9))
	img.save_png(OUT_GUIDE)


func _fill_glow(img: Image, center: Vector2, radius: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := Vector2(x, y).distance_to(center) / radius
			if d <= 1.0:
				var c := col
				c.a *= 1.0 - d
				var existing := img.get_pixel(x, y)
				img.set_pixel(x, y, existing.lerp(c, c.a))


func _fill_diamond(img: Image, center: Vector2, size: float, col: Color) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -size),
		center + Vector2(size * 0.8, 0),
		center + Vector2(0, size),
		center + Vector2(-size * 0.8, 0),
	])
	_fill_polygon(img, pts, col)


func _fill_circle(img: Image, center: Vector2, radius: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if Vector2(x, y).distance_to(center) <= radius:
				img.set_pixel(x, y, col)


func _fill_polygon(img: Image, points: PackedVector2Array, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			if _point_in_poly(Vector2(x, y), points):
				img.set_pixel(x, y, col)


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
