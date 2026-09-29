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
const FOLDER := "res://assets/legacy/battle/"
const AnimatedPortrait = preload("res://scripts/animated_portrait.gd")
const STAND := 3
const FACING := 1
const LIMIT := 128

## sprite -> ImageTexture, or false when it can never be made here.
static var _made: Dictionary = {}

## Whether the manifest has standing art for the sprite at all.
static func has_art(sprite: int) -> bool:
	return not AnimatedPortrait.animation_for(str(sprite),STAND,FACING).get("frames",[]).is_empty()

static func cached(sprite: int) -> Texture2D:
	var made = _made.get(sprite)
	return made if made is Texture2D else null

## False once a sprite is known to have no picture in this build.
static func possible(sprite: int) -> bool:
	return not (_made.get(sprite) is bool) and has_art(sprite)

## The sheet file the picture comes from, or "".
static func sheet_path(sprite: int) -> String:
	var frames: Array = AnimatedPortrait.animation_for(str(sprite),STAND,FACING).get("frames",[])
	if frames.is_empty():return ""
	var sheet: Dictionary = AnimatedPortrait.manifest().get("sheets",{}).get(str(sprite),{})
	var spot: Array = sheet.get("frames",{}).get(str(int(frames[0].image)),[])
	if spot.size() < 5:return ""
	return FOLDER+str(sheet.files[int(spot[0])])

## Makes (or returns) the picture. Null when the sheet is not available yet;
## call again later (a web pack may still arrive).
static func texture(sprite: int) -> Texture2D:
	if _made.has(sprite):return cached(sprite)
	if not has_art(sprite):
		_made[sprite] = false
		return null
	var path := sheet_path(sprite)
	if path.is_empty():
		_made[sprite] = false
		return null
	if not ResourceLoader.exists(path):return null
	var frames: Array = AnimatedPortrait.animation_for(str(sprite),STAND,FACING).frames
	var spot: Array = AnimatedPortrait.manifest().sheets[str(sprite)].frames[str(int(frames[0].image))]
	var sheet: Texture2D = load(path)
	var image: Image = sheet.get_image() if sheet != null else null
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
	return result

## Lets a test supply pictures without a renderer.
static func set_texture(sprite: int, value: Texture2D) -> void:
	_made[sprite] = value if value != null else false

static func clear() -> void:
	_made.clear()
