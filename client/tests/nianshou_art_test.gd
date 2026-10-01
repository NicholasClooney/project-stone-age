extends SceneTree
## Imported original override records, through the real battle/follower/UI art.
const BattleArt = preload("res://scripts/battle_art.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const Palette = preload("res://scripts/palette_sheet.gd")
const Thumbs = preload("res://scripts/pet_thumbnails.gd")
const Portrait = preload("res://scripts/animated_portrait.gd")
const Follower = preload("res://scripts/pet_follower.gd")
const Battle = preload("res://scripts/battle_view.gd")
const Menu = preload("res://scripts/pet_encyclopedia_menu.gd")
const EXPECTED := {
	101152:[233685,"ffac7d5527595d669b20e4138cbed431002aa88bc489fab450b9437b5894c427"],
	101153:[233189,"57f5098905d4ecba74056feea15314083b1d02cfd2740f3fbd59f62f1b4db360"],
	101154:[233437,"96af4ea7036ddddfe23ca2c0f4545a3764361844906b5429e997b0ae8c0fe759"],
	101155:[233933,"d7697cfacc994f6683be9acb53870a4d85083bb3021c9ab2fff036b42dd9dd57"],
}
var failures := 0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func visible_sha(image: Image) -> String:
	image.convert(Image.FORMAT_RGBA8)
	var bytes := image.get_data()
	for i in range(0,bytes.size(),4):
		if bytes[i+3]==0:
			bytes[i] = 0
			bytes[i+1] = 0
			bytes[i+2] = 0
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

func palette_region(path: String, region: Rect2i) -> Image:
	var decoded := Palette.decode(FileAccess.get_file_as_bytes(path))
	if decoded.is_empty():return Image.new()
	var indices: Image = decoded.indices.get_region(region)
	var bytes := PackedByteArray()
	bytes.resize(region.size.x*region.size.y*4)
	var source := indices.get_data()
	for i in range(source.size()):
		for c in range(4):bytes[i*4+c] = decoded.palette[source[i]*4+c]
	return Image.create_from_data(region.size.x,region.size.y,false,Image.FORMAT_RGBA8,bytes)

func raw_image(path: String) -> Image:
	var image := Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return image

func run() -> void:
	var catalog: Dictionary = preload("res://server/encounter_catalog.gd").new().data
	var index := Thumbs.atlas_index()
	var battle := Battle.new()
	battle.stage = Control.new()
	var hashes := {}
	for sprite in EXPECTED:
		var key := str(sprite)
		check(int(catalog.templates[str(sprite-100251)].sprite)==sprite,"template %d maps to original sprite %d" % [sprite-100251,sprite])
		var art := BattleArt.art(key)
		check(BattleArt.renderable(key,false),"%s has every battle action in its own available sheet" % key)
		if art.is_empty():continue
		var clip: Dictionary = art.animations["3_1"]
		var first := SpriteArt.image(clip,0)
		check(first==EXPECTED[sprite][0],"%s uses corrected original standing frame %d" % [key,EXPECTED[sprite][0]])
		var place := SpriteArt.spot(art,first)
		var image := raw_image(place[0]).get_region(place[1])
		var sha := visible_sha(image)
		hashes[sha] = true
		check(sha==EXPECTED[sprite][1],"%s sheet RGBA matches original decoded bitmap SHA" % key)
		check(visible_sha(palette_region(place[0],place[1]))==sha,"%s palette indices resolve to exact original RGBA" % key)
		battle.add_actor(key,Vector2.ZERO,1)
		check(SpriteArt.image(battle.actors[-1].animation,0)==first,"real battle actor selects %s's corrected frame" % key)
		var follower := Follower.new()
		follower.name_label = Label.new()
		follower.select_pet(key,"年兽")
		check(follower.art==art and follower.animations.has("4_1"),"exploration follower reads the same corrected standing/walking art")
		follower.name_label.free()
		follower.free()
		var row: Array = index.sprites[key]
		var rect := Rect2i(int(row[1]),int(row[2]),int(row[3]),int(row[4]))
		var rgba := raw_image(Thumbs.THUMBS+str(index.files[int(row[0])])).get_region(rect)
		check(visible_sha(rgba)==sha,"%s RGBA thumbnail index selects its exact original standing pixels" % key)
		check(visible_sha(palette_region(Thumbs.THUMBS+str(index.palette_files[int(row[0])]),rect))==sha,"%s palette thumbnail index selects the same original pixels" % key)
		for on in [false,true]:
			Palette.user_on = on
			Thumbs.clear()
			art.textures.clear()
			preload("res://scripts/sheet_frames.gd").flush()
			var portrait := Portrait.new()
			portrait.setup(key,1)
			portrait._update(0)
			check(portrait.current_image==first and portrait._texture!=null and Palette.is_palette(portrait._texture)==on,"real portrait uses corrected %s art in %s mode" % [key,"palette" if on else "RGBA"])
			portrait.free()
			Thumbs.texture(sprite)
			var menu := Menu.new()
			var holder := menu._thumb(sprite,Vector2(104,86))
			var picture: TextureRect = holder.get_child(0)
			check(picture.texture!=null and Palette.is_palette(picture.texture)==on and picture.texture is AtlasTexture and (picture.texture as AtlasTexture).region==Rect2(rect),"real encyclopedia thumbnail uses %s's corrected atlas entry" % key)
			holder.free()
			menu.free()
	check(hashes.size()==4,"all four original nianshou sprites have distinct standing pixels")
	battle.stage.free()
	battle.free()
	Palette.user_on = true
	Thumbs.clear()
	print("NIANSHOU ART: %d failures" % failures)
	quit(1 if failures else 0)
