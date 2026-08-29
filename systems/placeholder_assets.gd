extends RefCounted

## Generates placeholder textures/sprites in code. Swap paths in asset catalogs later.


static func make_color_texture(color: Color, size: Vector2i = Vector2i(64, 64)) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


static func make_character_sprite(color: Color, label: String = "") -> ImageTexture:
	var img := Image.create(48, 64, false, Image.FORMAT_RGBA8)
	img.fill(color.darkened(0.25))
	# Simple body/face silhouette keeps generated characters readable in every scene.
	for y in range(24, 58):
		for x in range(8, 40):
			if absf(float(x - 24)) < 12.0:
				img.set_pixel(x, y, color)
	if not label.is_empty():
		# Simple head circle
		for y in range(8, 24):
			for x in range(16, 32):
				if Vector2(x - 24, y - 16).length() < 10:
					img.set_pixel(x, y, color.lightened(0.3))
	return ImageTexture.create_from_image(img)


static func make_bg_texture(base: Color, accent: Color, size: Vector2i = Vector2i(960, 540)) -> ImageTexture:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(base)
	for y in range(size.y / 2, size.y):
		for x in range(size.x):
			var t := float(y - size.y / 2) / float(size.y / 2)
			img.set_pixel(x, y, base.lerp(accent, t * 0.5))
	# Add subtle vertical bands and horizon glow for scene distinction without external art.
	for x in range(0, size.x, 48):
		for y in range(size.y / 2, size.y):
			var band := accent.lightened(0.08) if int(x / 48) % 2 == 0 else accent.darkened(0.08)
			var strength := 0.08 * (1.0 - float(y - size.y / 2) / float(size.y / 2))
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(band, strength))
	return ImageTexture.create_from_image(img)


static func create_fill_background(parent: Node, bounds: Rect2, base: Color, accent: Color, z_index: int = -100) -> Sprite2D:
	var pixel_size := Vector2i(
		maxi(960, ceili(bounds.size.x)),
		maxi(540, ceili(bounds.size.y))
	)
	var bg := Sprite2D.new()
	bg.texture = make_bg_texture(base, accent, pixel_size)
	bg.position = bounds.position
	bg.centered = false
	bg.z_index = z_index
	parent.add_child(bg)
	parent.move_child(bg, 0)
	return bg
