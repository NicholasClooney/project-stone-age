extends "res://server/backend.gd"
## Display-only fixture: visible budget projection, no public admission.
## Production configuration is unchanged; explicit closed getter preserves negative controls.
func _quest_loot_public_enabled()->bool:
	return false
func _capabilities()->Dictionary:
	return {"quest_loot_enabled":true}
