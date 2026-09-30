extends RefCounted
## Dated copies of a profile's save, taken when a multi-profile server opens
## it (server/profile_hub.gd): <save folder>/backups/<save name>@<stamp>.json,
## the newest KEEP per save kept. The save's own .bak (the previous write)
## stays as it is; these reach further back.
const KEEP := 5

static func folder(save_path: String) -> String:
	return save_path.get_base_dir().path_join("backups")

## Copies the save (if it exists) and drops the oldest copies beyond `keep`.
## Returns the copy's path, "" when there was nothing to copy or it failed.
static func backup(save_path: String, keep: int = KEEP, stamp: String = "") -> String:
	if not FileAccess.file_exists(save_path):return ""
	if stamp.is_empty():
		var now := Time.get_datetime_dict_from_system()
		stamp = "%04d%02d%02d-%02d%02d%02d" % [now.year,now.month,now.day,now.hour,now.minute,now.second]
	var dir := folder(save_path)
	DirAccess.make_dir_recursive_absolute(dir)
	var base := save_path.get_file().get_basename()
	var target := dir.path_join("%s@%s.json" % [base,stamp])
	var serial := 1
	while FileAccess.file_exists(target):
		serial += 1
		target = dir.path_join("%s@%s-%d.json" % [base,stamp,serial])
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path),ProjectSettings.globalize_path(target))!=OK:return ""
	var copies := copies_of(save_path)
	while copies.size() > keep:
		DirAccess.remove_absolute(dir.path_join(copies.pop_front()))
	return target

## This save's copies, oldest first (the stamp sorts by time).
static func copies_of(save_path: String) -> Array:
	var base := save_path.get_file().get_basename()+"@"
	var result: Array = []
	for file in DirAccess.get_files_at(folder(save_path)):
		if file.begins_with(base) and file.ends_with(".json"):result.append(file)
	result.sort()
	return result
