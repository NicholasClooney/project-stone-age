extends RefCounted
## Client-side view of the current battle. The pet target is chosen in the UI
## and sent with the player's action as one battle_command.
var link
var state
var _pet_target := -1

func _init(target_link, client_state) -> void:
	link = target_link
	state = client_state

func snapshot() -> Dictionary:
	if state.needs_resync():state.apply(link.request({"type":"snapshot"}).snapshot)
	var result: Dictionary = state.battle.duplicate(true)
	if result.is_empty():result = {"active":false,"outcome":"","events":[]}
	return result

var capture_assist: bool:
	get:return bool(snapshot().get("capture_assist",false))

func set_capture_assist(enabled: bool) -> void:
	link.request({"type":"battle_capture_assist","enabled":enabled})

func set_pet_target(index: int) -> bool:
	_pet_target = index
	return true

func set_pet_skill(skill_id: int) -> bool:
	return bool(link.request(_for_turn({"type":"battle_pet_skill","skill_id":skill_id})).get("ok",false))

func set_pet_command(command: String) -> bool:
	return bool(link.request(_for_turn({"type":"battle_pet_command","command":command})).get("ok",false))

func submit_action(action: String, target: int = -1, pet_index: int = -2) -> Dictionary:
	var reply: Dictionary = link.request(_for_turn({"type":"battle_command","action":action,"target":target,"pet_target":_pet_target,"switch_pet":pet_index}))
	return reply.get("state",snapshot())

func developer_escape() -> Dictionary:
	var reply: Dictionary = link.request(_for_turn({"type":"battle_escape_dev"}))
	return reply.get("state",snapshot())

## Over a network other devices may act on the same battle; naming the turn
## this device saw makes the backend drop the command if that turn is over.
## In process there is only one client, so commands go unmarked.
func _for_turn(command: Dictionary) -> Dictionary:
	if link.is_local() or not state.battle.has("battle_id"):return command
	command.battle_id = str(state.battle.battle_id)
	command.turn = int(state.battle.get("turn",0))
	return command

# ---- in-process test seams: only valid with a LocalLink ----------------------

func _authority():
	state.seam_active = true
	return link.backend.battle

var _state: Dictionary:
	get:return _authority()._state
	set(value):_authority()._state = value

func _finish(outcome: String, message: String) -> void:
	_authority()._finish(outcome,message)
