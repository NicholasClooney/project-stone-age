extends SceneTree
## Texture caches stay bounded: SheetFrames keeps the last SHEETS sheets (an
## older one is freed once nothing draws it), and a map change keeps only the
## tiles the next map uses.
const SheetFrames = preload("res://scripts/sheet_frames.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func run() -> void:
	var paths: Array = []
	for name in DirAccess.get_files_at("res://assets/legacy/battle/sheets"):
		var file := str(name).trim_suffix(".import").trim_suffix(".remap")
		if file.ends_with(".png") and not paths.has("res://assets/legacy/battle/sheets/"+file):paths.append("res://assets/legacy/battle/sheets/"+file)
		if paths.size() > SheetFrames.SHEETS+6:break
	check(paths.size() > SheetFrames.SHEETS,"enough sheets to overflow the cache (%d)" % paths.size())
	var first: WeakRef = weakref(SheetFrames.sheet(paths[0]))
	var kept: Texture2D = SheetFrames.sheet(paths[1])
	for path in paths.slice(2):SheetFrames.sheet(path)
	check(SheetFrames.held() == SheetFrames.SHEETS,"the cache holds the last %d sheets" % SheetFrames.SHEETS)
	await process_frame
	check(first.get_ref() == null,"an old sheet nothing draws is freed")
	check(kept != null and is_instance_valid(kept),"one still used elsewhere stays alive")
	SheetFrames.sheet(paths[paths.size()-1])
	check(SheetFrames.held() == SheetFrames.SHEETS,"using a cached sheet again does not grow it")

	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	for i in range(30):await process_frame
	var before: int = game.textures.size()
	check(before > 0,"the village drew some tiles (%d)" % before)
	check(game.load_area_id(1002,Vector2i(16,15)),"walk into a shop")
	check(await Wait.until(self,func():return int(game.data.map_id) == 1002 and not game.area_transition_busy),"the shop is loaded")
	var images: Dictionary = game.data.get("images",{})
	var village_only: Array = game.textures.keys().filter(func(key):return not images.has(key))
	check(village_only.size() <= 8,"tiles only the village used are let go (%d left of %d drawn before; actor frames load again)" % [village_only.size(),before])
	game.queue_free()
	await process_frame
	print("TEXTURE CACHE: %d failures" % failures)
	quit(1 if failures else 0)
