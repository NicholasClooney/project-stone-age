extends RefCounted
## Test-side state preparation only: never part of a UI or network command.
static func set_fields(game, fields: Dictionary)->void:
	assert(game.backend!=null and game.link.is_local())
	for key in fields:game.backend.automation.set(key,fields[key])
	game.backend.automation._emit_status()
