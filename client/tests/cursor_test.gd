extends SceneTree
const Cursor = preload("res://scripts/legacy_cursor.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		push_error("FAIL: " + label)
		failures += 1
	else: print("PASS: " + label)
func _initialize() -> void:
	check(Cursor.install(),"original cursor resource installs")
	check(Cursor.bitmap.get_size() == Vector2i(32,32),"cursor preserves original pixel size")
	check(Cursor.hotspot == Vector2.ZERO,"cursor preserves original top-left hotspot")
	var bitmap := Cursor.bitmap
	var transparent := 0
	var opaque := 0
	for y in range(32):
		for x in range(32):
			if bitmap.get_pixel(x,y).a == 0: transparent += 1
			else: opaque += 1
	check(transparent > 500 and opaque > 100,"original AND mask removes background and preserves fish")
	check(Cursor.install(),"installation is safe across area reloads")
	call_deferred("finish")
func finish() -> void:
	if DisplayServer.get_name() != "headless":
		var root_ui := Control.new()
		root_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(root_ui)
		for i in range(3):
			var background := ColorRect.new()
			background.color = [Color.BLACK,Color("356443"),Color("dad0b0")][i]
			background.position = Vector2(i*200,0)
			background.size = Vector2(200,200)
			root_ui.add_child(background)
			var sprite := TextureRect.new()
			sprite.texture = ImageTexture.create_from_image(Cursor.bitmap)
			sprite.position = Vector2(i*200+20,20)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(4,4)
			root_ui.add_child(sprite)
			var native := TextureRect.new()
			native.texture = sprite.texture
			native.position = Vector2(i*200+160,150)
			root_ui.add_child(native)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/stone-fish-cursor-render.png")
		root_ui.queue_free()
		await process_frame
	Cursor.uninstall()
	await process_frame
	print("Cursor failures: ",failures)
	quit(1 if failures else 0)
