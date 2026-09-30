extends SceneTree
## Imported frames are cut from sprite sheets (docs/technical/sprite-sheets.md):
## every animation frame of a sprite resolves to its sheet at the frame's size.
const SpriteArt = preload("res://scripts/sprite_art.gd")
const BattleArt = preload("res://scripts/battle_art.gd")
const CharacterArt = preload("res://scripts/character_art.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## Every frame of the given sprites, and the first frame of all of them.
func check_frames(label: String, entries: Dictionary, sprites: Array) -> void:
	var sheeted := true
	for key in entries:
		if entries[key].files.is_empty():sheeted = false
	check(not entries.is_empty() and sheeted,"%s: every sprite has a sheet (%d)" % [label,entries.size()])
	for sprite in sprites:
		var complete := true
		var art: Dictionary = entries[sprite]
		for animation in art.animations.values():
			for i in range(SpriteArt.frame_count(animation)):
				var bitmap := SpriteArt.image(animation,i)
				var texture := SpriteArt.texture(art,bitmap)
				if not texture is AtlasTexture or Vector2i(texture.get_size())!=SpriteArt.image_size(art,bitmap) or texture.get_image().is_invisible():complete = false
		check(complete,"%s: sprite %s draws every frame from its sheet" % [label,sprite])
	var ok := true
	for sprite in entries:
		var art: Dictionary = entries[sprite]
		var bitmap := SpriteArt.image(art.animations.values()[0],0)
		var texture := SpriteArt.texture(art,bitmap)
		if texture==null or Vector2i(texture.get_size())!=SpriteArt.image_size(art,bitmap):ok = false
	check(ok,"%s: the first frame of all %d sprites is found" % [label,entries.size()])

## Pet sprites that ship in their own web pack (BattleArt extra sprites).
func extra_sprites() -> void:
	check(BattleArt.index().get("extra_sprites",{}).size() > 300 and not BattleArt.index().sprites.has("101869"),"most pet sprites ship with their own web pack (%d)" % BattleArt.index().get("extra_sprites",{}).size())
	var art := BattleArt.art(101869)
	check(BattleArt.ensure(101869) and BattleArt.is_extra(101869) and not art.is_empty(),"巴雅's sprite (101869, 8.0) loads on first use")
	var complete := true
	var renumbered := 0
	for animation in art.animations.values():
		for i in range(SpriteArt.frame_count(animation)):
			var bitmap := SpriteArt.image(animation,i)
			if bitmap >= 1000000000:renumbered += 1
			var texture := SpriteArt.texture(art,bitmap)
			if texture==null or Vector2i(texture.get_size())!=SpriteArt.image_size(art,bitmap):complete = false
	check(complete,"every frame of it is found in its sheet")
	check(renumbered == 0,"its bitmaps keep their numbers: 2.5 has the same pictures or none under them")
	# 机豹 (101423, 8.0 only): 2.5 uses its bitmap numbers for other pictures.
	for animation in BattleArt.animations(101423).values():
		for i in range(SpriteArt.frame_count(animation)):
			if SpriteArt.image(animation,i) >= 1000000000:renumbered += 1
	check(renumbered > 0,"8.0 bitmaps whose numbers 2.5 uses for other pictures are renumbered (机豹: %d frames)" % renumbered)

func run() -> void:
	var battle := {}
	for sprite in BattleArt.index().sprites:battle[sprite] = BattleArt.read(sprite)
	check_frames("battle",battle,["100000","100250"])
	check(SpriteArt.texture(battle["100000"],-1)==null,"a frame no sheet holds draws nothing")
	check(not DirAccess.dir_exists_absolute("res://assets/legacy/battle/images"),"no per-frame battle PNGs are left for Godot to import")
	extra_sprites()
	var characters := {}
	for character in CharacterArt.index().characters:characters[character] = CharacterArt.read(character)
	check_frames("characters",characters,["100000","100010"])
	# A frame only the sheet holds has no PNG left; one a map also draws keeps it.
	var only_sheet := 0
	var total := 0
	for character in characters:
		var art: Dictionary = characters[character]
		for bitmap in art.bitmaps:
			if SpriteArt.spot(art,bitmap).is_empty():continue
			total += 1
			if not ResourceLoader.exists("res://assets/legacy/images/%d.png" % bitmap):only_sheet += 1
	check(only_sheet > total*0.9,"most packed walking frames no longer exist as single PNGs (%d of %d)" % [only_sheet,total])
	# The field draws player characters from the sheet.
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	await process_frame
	var bitmap := SpriteArt.image(characters["100000"].animations.values()[0],0)
	check(game.character_frame("100000",bitmap) is AtlasTexture,"the field draws a player character's frame from its sheet")
	check(game.player.sprite.texture!=null,"the player is drawn")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await process_frame
	print("SHEET FRAMES: %d failures" % failures)
	quit(1 if failures else 0)
