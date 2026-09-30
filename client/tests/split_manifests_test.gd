extends SceneTree
## Per-sprite art files (tools/split_manifests.py, scripts/sprite_art.gd,
## scripts/art_cache.gd): the recent-entries cache, the compact entry, and
## parity with the importers' manifests they were split from: every frame,
## sound, draw offset and sheet rectangle of sample battle sprites (8.0 pets
## included), riding composites and player characters, the battle frame
## sounds, TroopArt's renderable check and the battlefield lookups.
const SpriteArt = preload("res://scripts/sprite_art.gd")
const ArtCache = preload("res://scripts/art_cache.gd")
const BattleArt = preload("res://scripts/battle_art.gd")
const Riding = preload("res://scripts/riding.gd")
const CharacterArt = preload("res://scripts/character_art.gd")
const LEGACY := "res://assets/legacy/"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func source(path: String) -> Dictionary:
	if not FileAccess.file_exists(LEGACY+path):return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEGACY+path))
	return parsed if parsed is Dictionary else {}

func run() -> void:
	cache()
	entry()
	battle()
	riding()
	characters()
	backgrounds()
	print("SPLIT MANIFESTS: %d failures" % failures)
	quit(1 if failures else 0)

## Keeps the last `capacity` entries, refreshes on use, never caches a miss.
func cache() -> void:
	var files := {"a":{"bytes":1},"b":{"bytes":1},"c":{"bytes":1}}
	var lru := ArtCache.new(2)
	var load := func(key: String) -> Dictionary: return files.get(key,{})
	check(lru.get_entry("a",load)==files.a and lru.get_entry("b",load)==files.b and lru.reads==2,"entries are read on first use")
	check(is_same(lru.get_entry("a",load),files.a) and lru.reads==2,"a cached entry is not read again")
	lru.get_entry("c",load)
	check(lru.keys()==["a","c"] and not lru.has("b"),"the least recently used entry goes first")
	check(lru.get_entry("missing",load).is_empty() and not lru.has("missing") and lru.size()==2,"a file that is not here is not cached")
	files["missing"] = {"bytes":1}
	check(lru.get_entry("missing",load)==files.missing and lru.keys()==["c","missing"],"so it is found once it arrives")
	check(lru.cached("a").is_empty() and lru.reads==5,"cached() never reads")

## The compact entry reads back the frames it was written from.
func entry() -> void:
	var text := JSON.stringify({"animations":{"3_0":[600,7,1,-2,0,8,0,0,10001],"1_0":[100,7,0,0,0]},"files":["sheets/x.png"],
		"bitmaps":[7,-10,-20,30,40,0,5,6,8,-11,-21,31,41,-1,0,0]})
	var art := SpriteArt.parse(text,"x","res://nowhere/")
	var stand: Dictionary = art.animations["3_0"]
	check(int(stand.duration_ms)==600 and SpriteArt.frame_count(stand)==2 and stand.frames is PackedInt32Array,"animations keep duration and frames as packed ints")
	check(SpriteArt.frame(stand,1)=={"image":8,"x":0,"y":0,"sound":10001} and SpriteArt.hit_frame(stand)==1,"a frame reads back its image, offset and sound")
	check(SpriteArt.offset(art,stand,0)==Vector2(-9,-22) and SpriteArt.image_size(art,7)==Vector2i(30,40),"offsets add the bitmap's and the frame's")
	check(SpriteArt.spot(art,7)==["res://nowhere/sheets/x.png",Rect2i(5,6,30,40)] and SpriteArt.spot(art,8).is_empty() and SpriteArt.spot(art,9).is_empty(),"a packed bitmap has its sheet rectangle; others none")
	check(SpriteArt.texture(art,7)==null and art.textures.is_empty(),"a missing sheet draws nothing and caches nothing")
	var legacy := SpriteArt.from_legacy("x",{"3_0":{"duration_ms":600,"frames":[{"image":7,"x":1,"y":-2,"sound":0},{"image":8,"x":0,"y":0,"sound":10001}]}},{"7":{"x":-10,"y":-20,"w":30,"h":40},"8":{"x":-11,"y":-21,"w":31,"h":41}})
	check(legacy.animations["3_0"]==stand and SpriteArt.offset(legacy,stand,1)==SpriteArt.offset(art,stand,1),"a map's own walking art converts to the same entry")

## Compares an entry with the importer layout it came from; the sheet of a
## bitmap is its own sheet, else the one that holds it.
func same(art: Dictionary, animations: Dictionary, images: Dictionary, sheets: Dictionary, key: String, folder: String) -> bool:
	if art.is_empty() or art.animations.size()!=animations.size():return false
	var owners := {}
	for owner in sheets:
		for bitmap in sheets[owner].get("frames",{}):owners[bitmap] = owner
	for name in animations:
		var expected: Dictionary = animations[name]
		var got: Dictionary = art.animations.get(name,{})
		if got.is_empty() or int(got.duration_ms)!=int(expected.duration_ms) or SpriteArt.frame_count(got)!=expected.frames.size():return false
		for i in range(expected.frames.size()):
			var frame: Dictionary = expected.frames[i]
			var bitmap := int(frame.image)
			if SpriteArt.frame(got,i)!={"image":bitmap,"x":int(frame.x),"y":int(frame.y),"sound":int(frame.sound)}:return false
			var info: Dictionary = images.get(str(bitmap),{})
			if info.is_empty():
				if SpriteArt.has_image(art,bitmap):return false
				continue
			if SpriteArt.offset(art,got,i)!=Vector2(int(info.x)+int(frame.x),int(info.y)+int(frame.y)) or SpriteArt.image_size(art,bitmap)!=Vector2i(int(info.w),int(info.h)):return false
			var owner: String = key if sheets.get(key,{}).get("frames",{}).has(str(bitmap)) else str(owners.get(str(bitmap),""))
			var place := SpriteArt.spot(art,bitmap)
			if owner.is_empty():
				if not place.is_empty():return false
				continue
			var spot: Array = sheets[owner].frames[str(bitmap)]
			if place!=[folder+str(sheets[owner].files[int(spot[0])]),Rect2i(int(spot[1]),int(spot[2]),int(spot[3]),int(spot[4]))]:return false
	return true

## TroopArt's check before the split, on the importer layout.
func old_renderable(key: String, animations: Dictionary, images: Dictionary, sheets: Dictionary) -> bool:
	var valid := true
	for action in [0,1,2,3,4,10]:
		for direction in range(8):
			var frames: Array = animations.get("%d_%d" % [action,direction],{}).get("frames",[])
			if frames.is_empty():valid = false
			for frame in frames:
				var bitmap := str(int(frame.image))
				var spot: Array = sheets.get(key,{}).get("frames",{}).get(bitmap,[])
				if not images.has(bitmap) or spot.size() < 5 or not ResourceLoader.exists(BattleArt.ROOT+str(sheets[key].files[int(spot[0])])):valid = false
	return valid

func battle() -> void:
	var manifest := source("battle/manifest.json")
	if manifest.is_empty():
		print("SKIP: no importer battle manifest to compare with")
		return
	var index := BattleArt.index()
	check(index.sprites.size()==manifest.characters.size() and index.extra_sprites.size()==manifest.extra_sprites.size(),"the index lists every sprite (%d) and pet sprite (%d)" % [index.sprites.size(),index.extra_sprites.size()])
	check(index.frame_sounds==manifest.frame_sounds and index.equipment_variants==manifest.equipment_variants and index.ui==manifest.ui and index.audio==manifest.audio,"frame sounds, club variants, UI and audio are unchanged")
	var sheets: Dictionary = manifest.sheets.duplicate()
	var extras := {}
	for key in manifest.extra_sprites:
		var extra := source("battle/"+str(manifest.extra_sprites[key]))
		extras[key] = extra
		sheets.merge(extra.get("sheets",{}),true)
	var sample := ["100000","100002","100250","100251","100373"]
	for key in manifest.equipment_variants.get("club",{}).values().slice(0,4):
		if not sample.has(str(key)):sample.append(str(key))
	for key in sample:
		check(same(BattleArt.read(key),manifest.characters[key],manifest.images,sheets,key,BattleArt.ROOT),"battle sprite %s: every frame, sound, offset and sheet rectangle is unchanged" % key)
	for key in ["101869","101423","100018"]:
		if not extras.has(key):continue
		var extra: Dictionary = extras[key]
		check(same(BattleArt.read(key),extra.characters[key],extra.images,sheets,key,BattleArt.ROOT),"8.0 pet sprite %s: every frame is unchanged" % key)
	var agree := true
	var checked := 0
	for key in manifest.characters.keys().slice(0,40):
		checked += 1
		if BattleArt.renderable(key,false)!=old_renderable(key,manifest.characters[key],manifest.images,manifest.sheets):agree = false
	for key in extras.keys().slice(0,40):
		checked += 1
		var extra: Dictionary = extras[key]
		if BattleArt.renderable(key,false)!=old_renderable(key,extra.characters[key],extra.images,extra.get("sheets",{})):agree = false
	check(agree,"TroopArt's renderable check agrees with the full manifest check (%d sprites)" % checked)
	check(not BattleArt.renderable("999999",true) and not BattleArt.known("999999") and BattleArt.art("999999").is_empty(),"an unknown sprite is neither known nor renderable")
	var before: int = BattleArt.cache().reads
	BattleArt.art("100250")
	BattleArt.art("100250")
	check(BattleArt.cache().reads-before<=1 and BattleArt.cache().has("100250"),"a sprite's file is read once while it is recent")
	for key in manifest.characters.keys().slice(0,BattleArt.LIMIT+5):BattleArt.art(key)
	check(BattleArt.cache().size()==BattleArt.LIMIT,"at most %d sprites are kept" % BattleArt.LIMIT)
	BattleArt.cache().clear()
	check(not BattleArt.peek("100250").is_empty() and not BattleArt.cache().has("100250"),"peek reads a sprite without keeping it")

func riding() -> void:
	var manifest := source("riding/manifest.json")
	if manifest.is_empty():
		print("SKIP: no importer riding manifest to compare with")
		return
	var index := Riding.index()
	check(index.composites.size()==manifest.characters.size() and index.pairs==manifest.pairs and index.names==manifest.names and index.frame_sounds==manifest.frame_sounds,"the riding index keeps pairs, names and frame sounds")
	var sample := ["101000","101004","101009"]
	if manifest.characters.has("101309"):sample.append("101309")
	for key in sample:
		check(same(Riding.read(key),manifest.characters[key],manifest.images,manifest.sheets,key,Riding.ROOT),"riding composite %s: every frame is unchanged" % key)
	for key in manifest.characters.keys().slice(0,Riding.LIMIT+3):Riding.art(key)
	check(Riding.cache().size()==Riding.LIMIT,"at most %d riding composites are kept" % Riding.LIMIT)
	Riding.cache().clear()

func characters() -> void:
	var catalog := source("characters/catalog.json")
	if catalog.is_empty():
		print("SKIP: no importer character catalog to compare with")
		return
	var index := CharacterArt.index()
	check(index.choices==catalog.choices and index.characters.size()==catalog.characters.size(),"the character index keeps the chooser's list")
	for key in ["100000","100010","100235"]:
		if catalog.characters.has(key):
			check(same(CharacterArt.read(key),catalog.characters[key],catalog.images,catalog.sheets,key,CharacterArt.ROOT),"character %s: every walking frame is unchanged" % key)

func backgrounds() -> void:
	var catalog := source("battle/backgrounds.json")
	if catalog.is_empty():
		print("SKIP: no importer backgrounds.json to compare with")
		return
	var selector = preload("res://scripts/battle_background.gd").new()
	var ok := true
	for bitmap in catalog.bitmap_to_ground:
		if selector.ground_of(int(bitmap))!=int(catalog.bitmap_to_ground[bitmap]):ok = false
	check(ok,"every ground bitmap finds its ground (%d)" % catalog.bitmap_to_ground.size())
	ok = true
	for ground in catalog.ground_to_battlefields:
		var expected: Array = []
		for field in catalog.ground_to_battlefields[ground]:expected.append(int(field))
		if selector.choices(int(ground))!=expected:ok = false
	for ground in [-1,999999]:
		if selector.choices(ground)!=[0,0,0]:ok = false
	for ground in range(0,121000):
		if not catalog.ground_to_battlefields.has(str(ground)) and selector.choices(ground)!=[0,0,0]:ok = false
	check(ok,"every ground offers the same three battlefields, and an unlisted one battlefield 0")
	ok = selector.catalog.backgrounds.size()==catalog.backgrounds.size()
	for key in catalog.backgrounds:
		if str(selector.catalog.backgrounds.get(key,""))!=str(catalog.backgrounds[key].path):ok = false
	check(ok,"every battlefield keeps its picture")
