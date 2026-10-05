extends "res://server/backend.gd"
## Test-only capability fixture for remote suites that exercise budget display.
## It never changes ledger enabled/can_* fields or production configuration.
func _capabilities()->Dictionary:
	return {"quest_loot_enabled":true}
