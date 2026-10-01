extends RefCounted
## Keeps the most recently used sprite entries (scripts/sprite_art.gd) and
## drops the oldest beyond `capacity`. A node drawing a sprite holds its entry
## itself, so dropping one here never takes art away from the screen; it only
## means the file is read again the next time something asks for it.
##
## get_entry() takes the loader, a Callable(key: String) -> Dictionary that
## reads one file, {} when it is not here (a web pack still downloading).
## Nothing is cached then, so the next call tries again. The cache does not
## keep the loader: a loader bound to the script that holds this cache in a
## static var would keep that script alive at exit.

const PerfRegistry = preload("res://scripts/perf_registry.gd")

var capacity: int
## Name in the performance panel's manifest list ("" = not reported).
var report_as: String
## Files read so far (tests check that a cached entry is not read again).
var reads := 0
## Insertion order is recency: get() moves an entry to the end.
var _entries: Dictionary = {}

func _init(limit: int, report_name: String = "") -> void:
	capacity = maxi(1,limit)
	report_as = report_name

func get_entry(key: String, load_entry: Callable) -> Dictionary:
	if _entries.has(key):
		var entry: Dictionary = _entries[key]
		_entries.erase(key)
		_entries[key] = entry
		return entry
	var loaded: Dictionary = load_entry.call(key)
	reads += 1
	if loaded.is_empty():return {}
	_entries[key] = loaded
	while _entries.size() > capacity:_entries.erase(_entries.keys()[0])
	_report()
	return loaded

## The entry when it is cached, else {} (without reading anything).
func cached(key: String) -> Dictionary:
	return _entries.get(key,{})

func has(key: String) -> bool:
	return _entries.has(key)

func keys() -> Array:
	return _entries.keys()

func size() -> int:
	return _entries.size()

## Drops the frames every cached entry made (SpriteArt.texture), so they are
## cut again from freshly loaded sheets.
func forget_frames() -> void:
	for entry in _entries.values():entry.textures.clear()

func clear() -> void:
	_entries.clear()
	_report()

func _report() -> void:
	if report_as.is_empty():return
	var total := 0
	for entry in _entries.values():total += int(entry.get("bytes",0))
	PerfRegistry.track_manifest(report_as,total)
