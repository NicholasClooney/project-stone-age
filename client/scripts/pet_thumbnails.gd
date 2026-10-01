extends RefCounted
## Small still pictures of battle sprites for 宠物大全's grid and list: the
## first standing frame, cut out of the sprite's sheet into its own small
## texture. The sheet (about 2048 x 1024) is dropped afterwards, so browsing
## hundreds of species never keeps hundreds of sheets in memory; only the open
## detail view animates a full sheet (scripts/animated_portrait.gd).
##
## texture(sprite) returns the cached picture, or null while there is none:
## the art is missing, its web pack is not downloaded yet (asset_packs
## sprite_pack names it), or the renderer cannot read textures back (headless).
## Every sprite's animations live in its own file (scripts/battle_art.gd);
## has_art() answers extra sprites from the index without reading them, and a
## picture reads the file without keeping it (BattleArt.peek), so browsing the
## grid does not keep hundreds of animation sets in memory.
const FOLDER := "res://assets/legacy/battle/"
## Pre-cut thumbnails (tools/build_pet_thumbs.py): atlases of every sprite's
## standing frame, so a picture needs a few small files, not the sprite's
## whole sheet (which on the web is a whole sprite pack to download).
const THUMBS := "res://assets/legacy/thumbs/"
const BattleArt = preload("res://scripts/battle_art.gd")
const SpriteArt = preload("res://scripts/sprite_art.gd")
const PaletteSheet = preload("res://scripts/palette_sheet.gd")
const PerfRegistry = preload("res://scripts/perf_registry.gd")
const STAND := 3
const FACING := 1
const LIMIT := 128

## sprite -> ImageTexture, or false when it can never be made here.
static var _made: Dictionary = {}
## sprite -> whether it has a standing frame (sprites in the core set only).
static var _standing: Dictionary = {}
## sprite -> its standing frame's spot, once found (the file is not kept).
static var _spots: Dictionary = {}
static var _atlas_index: Dictionary = {}
static var _atlas_loaded := false

## {limit, files, sprites: {sprite: [file, x, y, w, h]}} or {} without them.
static func atlas_index() -> Dictionary:
	if not _atlas_loaded:
		_atlas_loaded = true
		var path := THUMBS+"index.json"
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:_atlas_index = parsed
	return _atlas_index

## The atlas file a sprite's thumbnail is in, or "" (then the sheet is cut).
static func atlas_path(sprite: int) -> String:
	var spot: Array = atlas_index().get("sprites",{}).get(str(sprite),[])
	return THUMBS+str(atlas_index().files[int(spot[0])]) if not spot.is_empty() else ""

## The web packs holding the atlases (empty on desktop, where nothing is packed).
static func atlas_packs(asset_packs) -> Array:
	var result: Array = []
	if asset_packs == null or not asset_packs.enabled:return result
	for path in atlas_paths():
		var pack: String = asset_packs.file_pack(path)
		if not pack.is_empty() and not result.has(pack):result.append(pack)
	return result

## Every atlas file, for a background download of all thumbnails at once.
static func atlas_paths() -> Array:
	return atlas_index().get("files",[]).map(func(name):return THUMBS+str(name))

## Whether the manifest has standing art for the sprite at all.
static func has_art(sprite: int) -> bool:
	if BattleArt.is_extra(sprite):return true
	if not _standing.has(sprite):
		var animations: Dictionary = BattleArt.peek(sprite).get("animations",{})
		_standing[sprite] = SpriteArt.frame_count(animations.get("%d_%d" % [STAND,FACING],animations.get("%d_0" % STAND,{}))) > 0
	return _standing[sprite]

static func cached(sprite: int) -> Texture2D:
	var made = _made.get(sprite)
	return made if made is Texture2D else null

## False once a sprite is known to have no picture in this build.
static func possible(sprite: int) -> bool:
	return not (_made.get(sprite) is bool) and has_art(sprite)

## [sheet file, x, y, w, h] of the standing frame, or [] (no art, or an
## extra sprite whose web pack is not here yet).
static func _spot(sprite: int) -> Array:
	if _spots.has(sprite):return _spots[sprite]
	var entry := BattleArt.peek(sprite)
	var animations: Dictionary = entry.get("animations",{})
	var animation: Dictionary = animations.get("%d_%d" % [STAND,FACING],animations.get("%d_0" % STAND,{}))
	if SpriteArt.frame_count(animation) == 0:return []
	var place := SpriteArt.spot(entry,SpriteArt.image(animation,0))
	if place.is_empty():return []
	var rect: Rect2i = place[1]
	_spots[sprite] = [str(place[0]),rect.position.x,rect.position.y,rect.size.x,rect.size.y]
	return _spots[sprite]

## The sheet file the picture comes from, or "".
static func sheet_path(sprite: int) -> String:
	var spot := _spot(sprite)
	return str(spot[0]) if not spot.is_empty() else ""

## Makes (or returns) the picture. Null when the sheet is not available yet;
## call again later (a web pack may still arrive).
static func texture(sprite: int) -> Texture2D:
	if _made.has(sprite):return cached(sprite)
	var atlas := atlas_path(sprite)
	if not atlas.is_empty():
		# Null until the atlas (a web pack) is here; try again later.
		if not ResourceLoader.exists(atlas):return null
		var spot: Array = atlas_index().sprites[str(sprite)]
		var piece := AtlasTexture.new()
		piece.atlas = load(atlas)
		piece.region = Rect2(int(spot[1]),int(spot[2]),int(spot[3]),int(spot[4]))
		_made[sprite] = piece
		return piece
	if not has_art(sprite):
		_made[sprite] = false
		return null
	var spot := _spot(sprite)
	if spot.is_empty():
		# An extra sprite's file comes with its web pack: not yet, not never.
		if BattleArt.is_extra(sprite) and BattleArt.peek(sprite).is_empty():return null
		_made[sprite] = false
		return null
	var path: String = spot[0]
	if not PaletteSheet.exists(path):return null
	var image := PaletteSheet.picture(path)
	if image == null or image.is_empty():
		_made[sprite] = false
		return null
	if image.is_compressed():image.decompress()
	var picture := image.get_region(Rect2i(int(spot[1]),int(spot[2]),int(spot[3]),int(spot[4])))
	var longest := maxi(picture.get_width(),picture.get_height())
	if longest > LIMIT:
		var scale := float(LIMIT)/longest
		picture.resize(maxi(1,int(picture.get_width()*scale)),maxi(1,int(picture.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	var result := ImageTexture.create_from_image(picture)
	_made[sprite] = result
	PerfRegistry.track_texture("thumbnails",sprite,result)
	return result

## Lets a test supply pictures without a renderer.
static func set_texture(sprite: int, value: Texture2D) -> void:
	_made[sprite] = value if value != null else false

static func clear() -> void:
	_made.clear()
