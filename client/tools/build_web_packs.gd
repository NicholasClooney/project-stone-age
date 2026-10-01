extends SceneTree
## Writes the packs planned by tools/plan_web_packs.py:
##   godot --headless --path client --script res://tools/build_web_packs.gd -- <plan.json> <out dir> [cache.json]
## Imported files are packed as the editor stores them (the .import remap plus
## the converted resource under .godot/imported), so load() behaves the same
## once a pack is mounted. Each pack file name carries a content hash; the
## index packs.json maps names to files and the game's lookups.
##
## Incremental: with a cache file, a pack whose source files (paths and
## modification times, including the imported copies) match the last build is
## kept as it is in <out dir> instead of being written again. build-web.sh
## seeds <out dir> with a copy-on-write clone of the served packs. Files in
## <out dir> that the new index does not name are removed.

## Bump when the packing itself changes, so every pack is rewritten once.
const FORMAT := 1
const PaletteSheet = preload("res://scripts/palette_sheet.gd")

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		printerr("usage: -- <plan.json> <out dir> [cache.json]");quit(2);return
	var plan = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not plan is Dictionary:
		printerr("unreadable plan ",arguments[0]);quit(2);return
	var out: String = arguments[1]
	var cache_path: String = arguments[2] if arguments.size() > 2 else ""
	var cache: Dictionary = {}
	if not cache_path.is_empty() and FileAccess.file_exists(cache_path):
		var loaded = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
		if loaded is Dictionary and int(loaded.get("format",0))==FORMAT:cache = loaded.get("packs",{})
	DirAccess.make_dir_recursive_absolute(out)
	var index := {"version":Time.get_datetime_string_from_system(true),"packs":{}}
	for key in ["maps","sprites","riding","characters","files"]:index[key] = plan.get(key,{})
	var names: Array = plan.packs.keys()
	names.sort()
	var failed := 0
	var reused := 0
	var next_cache := {}
	for name in names:
		var paths: Array = plan.packs[name]
		var fingerprint := _fingerprint(paths)
		var previous: Dictionary = cache.get(name,{})
		var entry: Dictionary = {}
		if not fingerprint.is_empty() and str(previous.get("fingerprint",""))==fingerprint and FileAccess.file_exists(out.path_join(str(previous.get("entry",{}).get("file","")))):
			entry = previous.entry
			reused += 1
		else:
			entry = _write_pack(str(name),paths,out)
		if entry.is_empty():
			failed += 1
			continue
		index.packs[name] = entry
		next_cache[name] = {"fingerprint":fingerprint,"entry":entry}
	_remove_unlisted(out,index.packs)
	var file := FileAccess.open(out.path_join("packs.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(index))
	file.close()
	if not cache_path.is_empty():
		DirAccess.make_dir_recursive_absolute(cache_path.get_base_dir())
		var cache_file := FileAccess.open(cache_path,FileAccess.WRITE)
		cache_file.store_string(JSON.stringify({"format":FORMAT,"packs":next_cache}))
		cache_file.close()
	print("wrote %d packs to %s (%d rewritten, %d unchanged, %d failed)" % [index.packs.size(),out,index.packs.size()-reused,reused,failed])
	quit(1 if failed else 0)

## Identifies a pack's inputs: each source path with its modification time,
## plus the .import remap and the imported files it points to. Empty when a
## file is missing, which forces a rewrite (and reports the problem there).
func _fingerprint(paths: Array) -> String:
	var parts := PackedStringArray([str(FORMAT)])
	for path in paths:
		var source := str(path)
		if PaletteSheet.ships_png(source):
			if not FileAccess.file_exists(source):return ""
			parts.append("palette %s@%d" % [source,FileAccess.get_modified_time(source)])
			continue
		var remap_file := source+".import"
		if not FileAccess.file_exists(remap_file):
			if not FileAccess.file_exists(source):return ""
			parts.append("%s@%d" % [source,FileAccess.get_modified_time(source)])
			continue
		parts.append("%s@%d" % [remap_file,FileAccess.get_modified_time(remap_file)])
		for imported in _imported_files(remap_file):
			if not FileAccess.file_exists(imported):return ""
			parts.append("%s@%d" % [imported,FileAccess.get_modified_time(imported)])
	return "\n".join(parts).sha256_text()

func _imported_files(remap_file: String) -> PackedStringArray:
	var files := PackedStringArray()
	var config := ConfigFile.new()
	if config.load(remap_file)!=OK:return files
	for key in config.get_section_keys("remap"):
		if key=="path" or key.begins_with("path."):files.append(str(config.get_value("remap",key)))
	return files

func _write_pack(name: String, paths: Array, out: String) -> Dictionary:
	var temporary := out.path_join(name+".tmp")
	var packer := PCKPacker.new()
	if packer.pck_start(temporary)!=OK:
		printerr("cannot write ",temporary);return {}
	for path in paths:
		if not _add(packer,str(path)):
			printerr("missing ",path," in ",name);return {}
	packer.flush()
	var digest := FileAccess.get_sha256(temporary).substr(0,12)
	var file_name := "%s-%s.pck" % [name,digest]
	var target := out.path_join(file_name)
	if FileAccess.file_exists(target):DirAccess.remove_absolute(target)
	DirAccess.rename_absolute(temporary,target)
	var written := FileAccess.open(target,FileAccess.READ)
	var size := written.get_length()
	written.close()
	return {"file":file_name,"bytes":size,"sha256":digest}

## A sheet drawn from its palette PNG (scripts/palette_sheet.gd) ships that
## PNG as it is, without the imported RGBA copy.
func _add(packer: PCKPacker, path: String) -> bool:
	var remap_file := path+".import"
	if PaletteSheet.ships_png(path) or not FileAccess.file_exists(remap_file):
		return FileAccess.file_exists(path) and packer.add_file(path,path)==OK
	if packer.add_file(remap_file,remap_file)!=OK:return false
	for imported in _imported_files(remap_file):
		if not FileAccess.file_exists(imported) or packer.add_file(imported,imported)!=OK:return false
	return true

## Drops pack files (and leftover temporaries) the new index does not name.
func _remove_unlisted(out: String, packs: Dictionary) -> void:
	var keep := {}
	for entry in packs.values():keep[str(entry.file)] = true
	for file_name in DirAccess.get_files_at(out):
		if (file_name.ends_with(".pck") or file_name.ends_with(".tmp")) and not keep.has(file_name):
			DirAccess.remove_absolute(out.path_join(file_name))
