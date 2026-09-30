extends RefCounted
## One sprite's art, read from its own compact file (tools/split_manifests.py):
## a battle or pet sprite (scripts/battle_art.gd), a rider and mount composite
## (scripts/riding.gd) or a player character's walking art
## (scripts/character_art.gd). See docs/technical/sprite-sheets.md.
##
## An entry is a Dictionary:
##   key         the sprite id
##   folder      res:// folder its sheet files are relative to
##   animations  "action_direction" -> {"duration_ms": int, "frames": PackedInt32Array}
##               with FRAME ints per frame: image, x, y, sound
##   bitmaps     bitmap -> row number in `rows`
##   rows        PackedInt32Array, ROW ints per bitmap: the bitmap, its draw
##               x, y, w, h, then the sheet (index into `files`, -1 when not
##               packed) and the frame's x, y in that sheet
##   files       PackedStringArray of sheet files
##   textures    bitmap -> AtlasTexture, made on first draw
##   bytes       the file's size, for the performance panel
## Packed arrays instead of a Dictionary per frame keep a battle sprite at
## tens of KB instead of about 0.8 MB.

const SheetFrames = preload("res://scripts/sheet_frames.gd")
const FRAME := 4
const ROW := 8

## Parses a sprite file; {} when it is unreadable.
static func parse(text: String, key: String, folder: String) -> Dictionary:
	var data = JSON.parse_string(text)
	if not data is Dictionary:return {}
	var animations := {}
	var source: Dictionary = data.get("animations",{})
	for name in source:
		var row: Array = source[name]
		if row.is_empty():continue
		animations[name] = {"duration_ms":int(row[0]),"frames":PackedInt32Array(row.slice(1))}
	var rows := PackedInt32Array(data.get("bitmaps",[]))
	var bitmaps := {}
	for i in range(rows.size()/ROW):bitmaps[rows[i*ROW]] = i
	return {"key":key,"folder":folder,"animations":animations,"bitmaps":bitmaps,"rows":rows,
		"files":PackedStringArray(data.get("files",[])),"textures":{},"bytes":text.length()}

## An entry from the importers' Dictionary layout ({"frames": [{image, x, y,
## sound}], "duration_ms"} animations and {x, y, w, h} images), for walking
## art a map JSON carries itself. Its frames have no sheet.
static func from_legacy(key: String, animations: Dictionary, images: Dictionary, folder: String = "") -> Dictionary:
	var result := {}
	var bitmaps := {}
	var rows := PackedInt32Array()
	for name in animations:
		var animation: Dictionary = animations[name]
		var frames := PackedInt32Array()
		for frame in animation.get("frames",[]):
			var image := int(frame.image)
			frames.append_array([image,int(frame.get("x",0)),int(frame.get("y",0)),int(frame.get("sound",0))])
			var info: Dictionary = images.get(str(image),{})
			if not bitmaps.has(image) and not info.is_empty():
				bitmaps[image] = rows.size()/ROW
				rows.append_array([image,int(info.x),int(info.y),int(info.get("w",0)),int(info.get("h",0)),-1,0,0])
		result[name] = {"duration_ms":int(animation.get("duration_ms",1000)),"frames":frames}
	return {"key":key,"folder":folder,"animations":result,"bitmaps":bitmaps,"rows":rows,"files":PackedStringArray(),"textures":{},"bytes":0}

# ---- frames of one animation ------------------------------------------------

static func frame_count(animation: Dictionary) -> int:
	var frames: PackedInt32Array = animation.get("frames",PackedInt32Array())
	return frames.size()/FRAME

static func image(animation: Dictionary, index: int) -> int:
	return animation.frames[index*FRAME]

static func sound(animation: Dictionary, index: int) -> int:
	return animation.frames[index*FRAME+3]

## The frame as {image, x, y, sound}, for callers off the drawing path.
static func frame(animation: Dictionary, index: int) -> Dictionary:
	var frames: PackedInt32Array = animation.frames
	var at := index*FRAME
	return {"image":frames[at],"x":frames[at+1],"y":frames[at+2],"sound":frames[at+3]}

## Index of the first frame whose sound is a hit marker (>= 10000), or -1.
static func hit_frame(animation: Dictionary) -> int:
	for i in range(frame_count(animation)):
		if sound(animation,i) >= 10000:return i
	return -1

# ---- bitmaps -----------------------------------------------------------------

static func has_image(entry: Dictionary, bitmap: int) -> bool:
	return entry.get("bitmaps",{}).has(bitmap)

## Where a frame is drawn relative to the sprite's anchor: the bitmap's
## offset plus the frame's.
static func offset(entry: Dictionary, animation: Dictionary, index: int) -> Vector2:
	var at := index*FRAME
	var frames: PackedInt32Array = animation.frames
	var row := int(entry.bitmaps.get(frames[at],-1))
	if row < 0:return Vector2(frames[at+1],frames[at+2])
	return Vector2(entry.rows[row*ROW+1]+frames[at+1],entry.rows[row*ROW+2]+frames[at+2])

static func image_size(entry: Dictionary, bitmap: int) -> Vector2i:
	var row := int(entry.get("bitmaps",{}).get(bitmap,-1))
	return Vector2i(entry.rows[row*ROW+3],entry.rows[row*ROW+4]) if row >= 0 else Vector2i.ZERO

## [sheet path, Rect2i] of a packed bitmap, or [] when it has no sheet.
static func spot(entry: Dictionary, bitmap: int) -> Array:
	var row := int(entry.get("bitmaps",{}).get(bitmap,-1))
	if row < 0:return []
	var rows: PackedInt32Array = entry.rows
	var sheet := rows[row*ROW+5]
	if sheet < 0 or sheet >= entry.files.size():return []
	return [str(entry.folder)+entry.files[sheet],Rect2i(rows[row*ROW+6],rows[row*ROW+7],rows[row*ROW+3],rows[row*ROW+4])]

## The bitmap as an AtlasTexture of its sheet, or null when it has none or
## the sheet is not available yet (a web pack still downloading; nothing is
## cached then, so the next draw tries again). Frames are cached in the entry,
## so they go when the entry does.
static func texture(entry: Dictionary, bitmap: int) -> Texture2D:
	if entry.is_empty():return null
	var textures: Dictionary = entry.textures
	var cached: Texture2D = textures.get(bitmap)
	if cached != null:return cached
	var place := spot(entry,bitmap)
	if place.is_empty():return null
	var made := SheetFrames.region(str(place[0]),place[1])
	if made != null:textures[bitmap] = made
	return made
