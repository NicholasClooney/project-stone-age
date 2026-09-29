extends SceneTree
## Imported frames are cut from sprite sheets (docs/technical/sprite-sheets.md):
## every animation frame of a sprite resolves to its sheet at the frame's size.
const SheetFrames = preload("res://scripts/sheet_frames.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func manifest(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}

## Every frame of the given sprites, and a sample of frames from all of them.
func check_frames(label: String, folder: String, data: Dictionary, sprites: Array) -> void:
	var sheets: Dictionary = data.get("sheets",{})
	check(not sheets.is_empty() and sheets.size()==data.characters.size(),"%s: every sprite has a sheet (%d)" % [label,sheets.size()])
	for sprite in sprites:
		var complete := true
		for animation in data.characters[sprite].values():
			for frame in animation.frames:
				var bitmap := int(frame.image)
				var texture := SheetFrames.texture(folder,sheets,sprite,bitmap)
				var info: Dictionary = data.images[str(bitmap)]
				if not texture is AtlasTexture or texture.get_size()!=Vector2(float(info.w),float(info.h)) or texture.get_image().is_invisible():complete = false
		check(complete,"%s: sprite %s draws every frame from its sheet" % [label,sprite])
	var sampled := 0
	var ok := true
	for sprite in data.characters:
		var frames: Array = data.characters[sprite].values()[0].frames
		var bitmap := int(frames[0].image)
		var texture := SheetFrames.bitmap_texture(folder,sheets,bitmap)
		if texture==null or texture.get_size()!=Vector2(float(data.images[str(bitmap)].w),float(data.images[str(bitmap)].h)):ok = false
		sampled += 1
	check(ok,"%s: the first frame of all %d sprites is found by bitmap alone" % [label,sampled])

func run() -> void:
	var battle := manifest("res://assets/legacy/battle/manifest.json")
	check_frames("battle","res://assets/legacy/battle/",battle,["100000","100250"])
	check(SheetFrames.texture("res://assets/legacy/battle/",battle.sheets,"100000",-1)==null,"a frame no sheet holds draws nothing")
	check(not DirAccess.dir_exists_absolute("res://assets/legacy/battle/images"),"no per-frame battle PNGs are left for Godot to import")
	var characters := manifest("res://assets/legacy/characters/catalog.json")
	check_frames("characters","res://assets/legacy/characters/",characters,["100000","100010"])
	# A frame only the sheet holds has no PNG left; one a map also draws keeps it.
	var only_sheet := 0
	var total := 0
	for character in characters.sheets:
		for bitmap in characters.sheets[character].frames:
			total += 1
			if not ResourceLoader.exists("res://assets/legacy/images/%s.png" % bitmap):only_sheet += 1
	check(only_sheet > total*0.9,"most packed walking frames no longer exist as single PNGs (%d of %d)" % [only_sheet,total])
	# The field draws player characters from the sheet.
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	await process_frame
	var bitmap := int(characters.characters["100000"].values()[0].frames[0].image)
	check(game.character_frame("100000",bitmap) is AtlasTexture,"the field draws a player character's frame from its sheet")
	check(game.player.sprite.texture!=null,"the player is drawn")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	await process_frame
	print("SHEET FRAMES: %d failures" % failures)
	quit(1 if failures else 0)
