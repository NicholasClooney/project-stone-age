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
	print("SHEET FRAMES: %d failures" % failures)
	quit(1 if failures else 0)
