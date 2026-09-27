extends RefCounted
## Client-side view of the player's profile. Reads come from ClientState;
## every mutation is a backend command. Method names mirror GameSession so UI
## scripts keep their call sites.
const GameSession = preload("res://server/game_session.gd")
const PET_CAPACITY := GameSession.PET_CAPACITY
const MAX_LEVEL := GameSession.MAX_LEVEL

var link
var state
var last_error := ""

func _init(target_link, client_state) -> void:
	link = target_link
	state = client_state

func request(command: Dictionary) -> bool:
	var reply: Dictionary = link.request(command)
	last_error = "" if reply.get("ok",false) else str(reply.get("reason",""))
	return bool(reply.get("ok",false))

func _fresh() -> void:
	if state.needs_resync():state.apply(link.request({"type":"snapshot"}).snapshot)

func snapshot() -> Dictionary:
	_fresh()
	return state.full_profile()

func has_travel_pass() -> bool:
	_fresh()
	return bool(state.derived.get("has_travel_pass",false))

func can_fight_boss() -> bool:
	_fresh()
	return bool(state.derived.get("can_fight_boss",false))

func effective_player_stats() -> Dictionary:
	_fresh()
	return state.derived.get("effective_stats",{}).duplicate(true)

func gm_pending() -> bool:
	_fresh()
	return bool(state.derived.get("gm_pending",false))

var clone_squad_enabled: bool:
	get:
		_fresh()
		return bool(state.options.get("clone_squad",false))
	set(value):
		request({"type":"set_options","clone_squad":value})

var experience_multiplier: int:
	get:
		_fresh()
		return int(state.options.get("experience_multiplier",1))
	set(value):
		request({"type":"set_options","experience_multiplier":value})

func buy_item(item: String) -> bool:return request({"type":"buy_item","item":item})
func sell_item(item: String) -> bool:return request({"type":"sell_item","item":item})
func use_item(item: String = "potion") -> bool:return request({"type":"use_item","item":item})
func equip_item(item: String = "club") -> bool:return request({"type":"equip_item","item":item})
func buy_travel_pass() -> bool:return request({"type":"buy_travel_pass"})
func heal() -> bool:return request({"type":"heal"})
func heal_carried_pets() -> bool:return request({"type":"heal_carried_pets"})
func grant_pet_care_items() -> bool:return request({"type":"grant_pet_care_items"})
func level_pet_to(pet_id: String, target: int) -> bool:return request({"type":"level_pet_to","pet_id":pet_id,"target":target})
func prune_hunt_pets(template_id: int, keep: Dictionary) -> int:
	return int(link.request({"type":"prune_hunt_pets","template_id":template_id,"keep":keep}).get("pruned",0))
func release_pets(ids: Array) -> Dictionary:
	var reply: Dictionary = link.request({"type":"release_pets","ids":ids})
	last_error = str(reply.get("error",""))
	return reply.get("result",{"released":0})
func store_pet(index: int, auto_hunt: bool = false) -> bool:return request({"type":"store_pet","index":index,"auto_hunt":auto_hunt})
func retrieve_pet(index: int) -> bool:return request({"type":"retrieve_pet","index":index})
func retrieve_pet_by_id(pet_id: String) -> bool:return request({"type":"retrieve_pet_by_id","pet_id":pet_id})
func select_pet(index: int) -> bool:return request({"type":"select_pet","index":index})
func mount_pet(index: int) -> bool:return request({"type":"mount_pet","index":index})
func rename_pet(index: int, pet_name: String) -> bool:return request({"type":"rename_pet","index":index,"name":pet_name})
func set_pet_favorite(pet_id: String, favorite: bool) -> bool:return request({"type":"set_pet_favorite","pet_id":pet_id,"favorite":favorite})
func allocate_stat(stat: String, amount: int = 1) -> bool:return request({"type":"allocate_stat","stat":stat,"amount":amount})
func distribute_stats(stats: Array) -> bool:return request({"type":"distribute_stats","stats":stats})
func learn_pet_skill(index: int, skill_id: int) -> bool:return request({"type":"learn_pet_skill","index":index,"skill_id":skill_id})
func set_character(id: String) -> bool:return request({"type":"set_character","id":id})
func accept_quest() -> bool:return request({"type":"accept_quest"})
func claim_quest() -> bool:return request({"type":"claim_quest"})
func grant_starter_pets() -> bool:return request({"type":"grant_starter_pets"})
func claim_default_companions() -> bool:return request({"type":"claim_default_companions"})
func gm_raise_level(index: int, target: Variant) -> bool:return request({"type":"gm_raise_level","index":index,"target":target})
func gm_set_base_stat(index: int, stat: String, value: Variant, additive: bool = false) -> bool:return request({"type":"gm_set_base_stat","index":index,"stat":stat,"value":value,"additive":additive})
func gm_grant_points(amount: Variant) -> bool:return request({"type":"gm_grant_points","amount":amount})
func gm_heal(index: int = -2) -> bool:return request({"type":"gm_heal","index":index})
func gm_clear_modified(index: int = -2) -> bool:return request({"type":"gm_clear_modified","index":index})

## Developer and test fixtures: the backend issues the config it will accept.
func start_battle_config(species: String = "wooli", boss: bool = false, enemy_count: int = 1) -> Dictionary:
	return link.request({"type":"start_battle_config","species":species,"boss":boss,"enemy_count":enemy_count}).get("config",{})

func start_wild_battle_config(troop: Dictionary) -> Dictionary:
	return link.request({"type":"start_wild_battle_config","troop":troop}).get("config",{})

# ---- in-process test seams: only valid with a LocalLink ----------------------

func _authority():
	state.seam_active = true
	return link.backend.session

var _profile: Dictionary:
	get:return _authority()._profile
	set(value):_authority()._profile = value

var _pending: Dictionary:
	get:return _authority()._pending
	set(value):_authority()._pending = value

func set_location(map_id: int, x: int, y: int) -> bool:
	return _authority().set_location(map_id,x,y)

func save_game(path: String) -> bool:
	return _authority().save_game(path)

func load_game(path: String) -> bool:
	return _authority().load_game(path)

func apply_battle_result(result: Dictionary) -> bool:
	return _authority().apply_battle_result(result)

var login_clock: Callable:
	get:return _authority().login_clock
	set(value):_authority().login_clock = value

func _gain_xp(actor: Dictionary, amount: int) -> void:
	_authority()._gain_xp(actor,amount)
