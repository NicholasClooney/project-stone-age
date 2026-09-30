extends RefCounted
# The original selects from three entries by ground tile, not floor ID.
# battle/battlefields.json (tools/split_manifests.py) keeps the server's table
# as packed lookups: the distinct battlefield triples, one uint16 per ground
# id naming its triple (0 = not listed: battlefield 0), and the ground of each
# ground bitmap as two sorted arrays.
const ROOT := "res://assets/legacy/battle/"
const FILE := ROOT+"battlefields.json"
static var _catalog: Dictionary = {}
var catalog: Dictionary = {}
var rng := RandomNumberGenerator.new()
var last_ground := -1
var last_field := -1

func _init() -> void:
	rng.randomize()
	catalog = load_catalog()

## Parsed once and shared: {choices, ground_choice, bitmaps, grounds, backgrounds}.
static func load_catalog() -> Dictionary:
	if _catalog.is_empty() and FileAccess.file_exists(FILE):
		var text := FileAccess.get_file_as_string(FILE)
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			_catalog = {"choices":PackedInt32Array(parsed.get("choices",[])),
				"ground_choice":Marshalls.base64_to_raw(str(parsed.get("ground_choice",""))),
				"bitmaps":PackedInt32Array(parsed.get("bitmaps",[])),
				"grounds":PackedInt32Array(parsed.get("grounds",[])),
				"backgrounds":parsed.get("backgrounds",{})}
		preload("res://scripts/perf_registry.gd").track_manifest("battlefields",text.length())
	return _catalog

## The ground a ground bitmap stands for, or -1.
func ground_of(bitmap: int) -> int:
	var bitmaps: PackedInt32Array = catalog.get("bitmaps",PackedInt32Array())
	var at := bitmaps.bsearch(bitmap)
	return int(catalog.grounds[at]) if at < bitmaps.size() and bitmaps[at]==bitmap else -1

## The ground's three battlefield choices ([0, 0, 0] when it is not listed).
func choices(ground: int) -> Array:
	var column: PackedByteArray = catalog.get("ground_choice",PackedByteArray())
	var row := column.decode_u16(ground*2) if ground >= 0 and ground*2+1 < column.size() else 0
	var table: PackedInt32Array = catalog.get("choices",PackedInt32Array([0,0,0]))
	return [table[row*3],table[row*3+1],table[row*3+2]]

func choose(bitmap: String) -> String:
	last_ground = ground_of(int(bitmap)) if bitmap.is_valid_int() else -1
	var options := choices(last_ground)
	last_field = int(options[rng.randi_range(0,2)])
	var available: Dictionary = catalog.get("backgrounds",{})
	if not available.has(str(last_field)):
		# Explicit compatibility fallback for an unavailable source asset.
		push_warning("Original battlefield %d unavailable; using classic battlefield 0." % last_field)
		last_field = 0 if available.has("0") else -1
	return ROOT+str(available[str(last_field)]) if last_field>=0 else ROOT+"background.png"
