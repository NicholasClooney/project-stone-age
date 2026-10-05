extends RefCounted
## Latest backend state as seen by one client. UI reads from here only; it is
## replaced by backend events and never written by presentation code.
signal changed(kind: String)

var rev := 0
var profile: Dictionary = {}
var pet_storage: Array = []
var derived: Dictionary = {}
var options: Dictionary = {}
var battle: Dictionary = {}
var battle_open := false
var automation: Dictionary = {"running":false}
## Server-owned feature publication. Missing or malformed capability data fails
## closed, including on a profile update from an older server.
var capabilities: Dictionary = {}
## Set when a test seam touched authority internals directly; the next read resyncs.
var stale := false
## Once a seam hands out authority internals, later writes through that
## reference are invisible, so every read resyncs from then on (tests only).
var seam_active := false

func needs_resync() -> bool:
	return stale or seam_active

func apply(message: Dictionary) -> void:
	var kind := str(message.get("type",""))
	match kind:
		"snapshot":
			rev = int(message.rev)
			profile = message.profile
			pet_storage = profile.get("pet_storage",[])
			profile.erase("pet_storage")
			derived = message.derived
			options = message.options
			battle = message.battle
			battle_open = bool(message.battle_open)
			automation = message.automation
			capabilities = message.get("capabilities",{}) if message.get("capabilities",{}) is Dictionary else {}
			stale = false
		"profile":
			rev = int(message.rev)
			profile = message.profile
			derived = message.derived
			options = message.options
			capabilities = message.get("capabilities",{}) if message.get("capabilities",{}) is Dictionary else {}
		"pet_storage":
			pet_storage = message.pet_storage
		"battle_started":
			battle = message.state
			battle_open = true
		"battle_turn","battle_state":
			battle = message.state
		"battle_closed":
			battle_open = false
		"auto_status":
			automation = message.status
		_:
			return
	changed.emit(kind)

## Profile with storage merged back, in the shape GameSession.snapshot() returns.
func full_profile() -> Dictionary:
	var result: Dictionary = profile.duplicate(true)
	result.pet_storage = pet_storage.duplicate(true)
	return result

func quest_loot_enabled() -> bool:
	var value = capabilities.get("quest_loot_enabled",false)
	return value is bool and value
