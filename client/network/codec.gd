extends RefCounted
## JSON wire format for backend messages. Godot parses every JSON number as a
## float, so integral values are restored to int on decode; rules compare and
## index with ints. Values stay JSON-safe on both sides (no Vector2i or objects).

static func encode(message: Dictionary) -> String:
	return JSON.stringify(message)

## Returns {} for anything that is not a JSON object.
static func decode(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return normalize(parsed) if parsed is Dictionary else {}

static func normalize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value==floorf(value) and absf(value)<9007199254740992.0:
		return int(value)
	if value is Array:
		var items: Array = []
		for item in value:items.append(normalize(item))
		return items
	if value is Dictionary:
		var result := {}
		for key in value:result[key] = normalize(value[key])
		return result
	return value
