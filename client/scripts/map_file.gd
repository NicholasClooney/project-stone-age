extends RefCounted
## Reads a map into the game's map dictionary (`game.data`): the small fields
## as JSON (map_id, name, origin, width, height, music_markers, images,
## map_colors, characters) plus three packed grids:
##   ground  PackedInt32Array, width*height tile image ids (y*width+x), 0 = none
##   blocked PackedByteArray, width*height, nonzero = not walkable
##   objects PackedInt32Array, x, y, image id per object (3 entries each)
## world/<id>.map files (tools/map_file.py) are read straight into these
## without building a Variant per cell; a parsed map JSON costs 10 to 20 times
## its size (docs/technical/memory-baseline.md). Older map JSON (samgir.json,
## shop.json, wilderness.json) is converted to the same shape.

const VERSION := 1

## The map at `path`, or {} when it is missing or unreadable.
static func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	if path.get_extension()=="map":return _read_packed(path)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_json(parsed) if parsed is Dictionary else {}

## Size of the file on disk, for the performance panel.
static func file_size(path: String) -> int:
	var file := FileAccess.open(path,FileAccess.READ)
	return file.get_length() if file!=null else 0

## Converts a parsed map JSON (ground as [x, y, id] triples, blocked and
## objects as arrays) in place to the packed shape and returns it.
static func from_json(data: Dictionary) -> Dictionary:
	var width := int(data.get("width",0))
	var height := int(data.get("height",0))
	var ground := PackedInt32Array()
	ground.resize(width*height)
	for entry in data.get("ground",[]):
		ground[int(entry[1])*width+int(entry[0])] = int(entry[2])
	var blocked := PackedByteArray()
	blocked.resize(width*height)
	var flags: Array = data.get("blocked",[])
	for index in range(mini(flags.size(),blocked.size())):
		blocked[index] = 1 if int(flags[index])!=0 else 0
	var objects := PackedInt32Array()
	for entry in data.get("objects",[]):
		objects.append_array([int(entry[0]),int(entry[1]),int(entry[2])])
	data.ground = ground
	data.blocked = blocked
	data.objects = objects
	return data

static func object_count(data: Dictionary) -> int:
	return (data.objects as PackedInt32Array).size()/3

static func _read_packed(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:return {}
	file.big_endian = false
	if file.get_buffer(6).get_string_from_ascii()!="SAMAP" or file.get_16()!=VERSION:
		push_error("not a version %d map file: %s" % [VERSION,path])
		return {}
	var header = JSON.parse_string(file.get_buffer(file.get_32()).get_string_from_utf8())
	if not header is Dictionary:return {}
	var data: Dictionary = header
	var cells := int(data.width)*int(data.height)
	if file.get_32()!=cells:return {}
	data.ground = file.get_buffer(cells*4).to_int32_array()
	if file.get_32()!=cells:return {}
	data.blocked = file.get_buffer(cells)
	var count := file.get_32()
	data.objects = file.get_buffer(count*12).to_int32_array()
	if data.ground.size()!=cells or data.blocked.size()!=cells or data.objects.size()!=count*3:
		push_error("truncated map file: %s" % path)
		return {}
	return data
