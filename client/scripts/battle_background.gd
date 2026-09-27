extends RefCounted
# The original selects from three entries by ground tile, not floor ID.
const ROOT := "res://assets/legacy/battle/"
var catalog: Dictionary = {}
var rng := RandomNumberGenerator.new()
var last_ground := -1
var last_field := -1

func _init() -> void:
	rng.randomize()
	if FileAccess.file_exists(ROOT+"backgrounds.json"):
		catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"backgrounds.json"))

func choose(bitmap: String) -> String:
	last_ground = int(catalog.get("bitmap_to_ground",{}).get(bitmap,-1))
	var choices: Array = catalog.get("ground_to_battlefields",{}).get(str(last_ground),[0,0,0])
	last_field = int(choices[rng.randi_range(0,2)])
	var available: Dictionary = catalog.get("backgrounds",{})
	if not available.has(str(last_field)):
		# Explicit compatibility fallback for an unavailable source asset.
		push_warning("Original battlefield %d unavailable; using classic battlefield 0." % last_field)
		last_field = 0 if available.has("0") else -1
	return ROOT+str(available[str(last_field)].path) if last_field>=0 else ROOT+"background.png"
