extends SceneTree
## Writes the packs planned by tools/plan_web_packs.py:
##   godot --headless --path client --script res://tools/build_web_packs.gd -- <plan.json> <out dir>
## Imported files are packed as the editor stores them (the .import remap plus
## the converted resource under .godot/imported), so load() behaves the same
## once a pack is mounted. Each pack file name carries a content hash; the
## index packs.json maps names to files and the game's lookups.

func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() < 2:
		printerr("usage: -- <plan.json> <out dir>");quit(2);return
	var plan = JSON.parse_string(FileAccess.get_file_as_string(arguments[0]))
	if not plan is Dictionary:
		printerr("unreadable plan ",arguments[0]);quit(2);return
	var out: String = arguments[1]
	DirAccess.make_dir_recursive_absolute(out)
	var index := {"version":Time.get_datetime_string_from_system(true),"packs":{}}
	for key in ["maps","sprites","riding","characters","files"]:index[key] = plan.get(key,{})
	var names: Array = plan.packs.keys()
	names.sort()
	var failed := 0
	for name in names:
		var entry := _write_pack(str(name),plan.packs[name],out)
		if entry.is_empty():failed += 1
		else:index.packs[name] = entry
	var file := FileAccess.open(out.path_join("packs.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(index))
	file.close()
	print("wrote %d packs to %s (%d failed)" % [index.packs.size(),out,failed])
	quit(1 if failed else 0)

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
	return {"file":file_name,"bytes":FileAccess.get_file_as_bytes(target).size(),"sha256":digest}

func _add(packer: PCKPacker, path: String) -> bool:
	var remap_file := path+".import"
	if not FileAccess.file_exists(remap_file):
		return FileAccess.file_exists(path) and packer.add_file(path,path)==OK
	var config := ConfigFile.new()
	if config.load(remap_file)!=OK:return false
	if packer.add_file(remap_file,remap_file)!=OK:return false
	for key in config.get_section_keys("remap"):
		if key=="path" or key.begins_with("path."):
			var imported := str(config.get_value("remap",key))
			if not FileAccess.file_exists(imported) or packer.add_file(imported,imported)!=OK:return false
	return true
