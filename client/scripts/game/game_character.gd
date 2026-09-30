extends RefCounted
## The player character of the game scene (scripts/game.gd): changing its
## appearance, the pet that follows it, and what it rides (including the
## developer ride toggle), each waiting for its web pack first. The actors
## stay on the game; see docs/technical/game-scripts.md.
const PetFollower = preload("res://scripts/pet_follower.gd")
const Riding = preload("res://scripts/riding.gd")
var game: GameScene

func _init(owner: GameScene) -> void:
	game = owner

func change_character(id: String = "") -> void:
	if game.battle_view.visible or game.area_transition_busy:return
	if id.is_empty():
		game.character_selection.open_menu()
		return
	if not game.asset_packs.is_ready([game.asset_packs.character_pack(id)]):
		game.asset_packs.ensure([game.asset_packs.character_pack(id)],func(ok: bool):if ok:change_character(id),"角色")
		return
	if not (game.character_catalog.get("characters",{}).has(id) or game.data.get("characters",{}).has(id)) or not game.session.set_character(id):return
	game.player.character_id = id
	refresh_riding()
	game.player.current_image = -1
	game.player.elapsed = 0.0
	game.message.text = "Original character %s" % id
	game.play_click()
	game.checkpoint()

func refresh_companion() -> void:
	var profile_now: Dictionary = game.session.snapshot()
	var wanted: Array = []
	if int(profile_now.active_pet)>=0 and int(profile_now.active_pet)<profile_now.pets.size():wanted.append(game.asset_packs.sprite_pack(profile_now.pets[int(profile_now.active_pet)].sprite))
	if not game.asset_packs.is_ready(wanted):
		game.asset_packs.ensure(wanted,func(ok: bool):if ok and is_instance_valid(game.player):refresh_companion())
		return
	refresh_riding()
	if is_instance_valid(game.pet_follower):
		game.pet_follower.queue_free()
	game.pet_follower = null
	var profile: Dictionary = game.session.snapshot()
	if int(profile.active_pet)<0 or not preload("res://scripts/battle_art.gd").present():return
	var pet: Dictionary = profile.pets[int(profile.active_pet)]
	if int(pet.hp)<=0:return
	game.pet_follower = PetFollower.new()
	game.pet_follower.world = game
	game.pet_follower.position = game.player.position
	game.actors.add_child(game.pet_follower)
	game.pet_follower.select_pet(str(int(pet.sprite)),str(pet.name))

func refresh_riding() -> void:
	if not is_instance_valid(game.player): return
	var profile: Dictionary = game.session.snapshot()
	var index := int(profile.get("ride_pet",-1))
	var composite := -1
	if index >= 0 and index < profile.pets.size():
		composite = preload("res://scripts/riding.gd").composite(str(profile.get("character_id","100000")),int(profile.pets[index].sprite))
	if composite >= 0 and not game.asset_packs.is_ready([game.asset_packs.riding_pack(composite)]):
		game.asset_packs.ensure([game.asset_packs.riding_pack(composite)],func(ok: bool):if ok:refresh_riding())
		return
	game.player.mounted_character_id = str(composite) if composite >= 0 else ""

## DEV: dismount, or ride the pet selected in the pet window, else the first
## carried pet this character can ride (a battling pet goes to standby first).
func dev_toggle_riding() -> void:
	if game.paused_input or game.moving or game.area_transition_busy or not game.session.has_method("mount_pet"): return
	var profile: Dictionary = game.session.snapshot()
	if int(profile.get("ride_pet",-1)) >= 0:
		game.session.mount_pet(-1)
		game.message.text = "下骑。"
	else:
		var order: Array = []
		if is_instance_valid(game.adventure_menu) and game.adventure_menu.selected_pet >= 0 and game.adventure_menu.selected_pet < profile.pets.size():
			order.append(game.adventure_menu.selected_pet)
		for i in range(profile.pets.size()):
			if not order.has(i):order.append(i)
		var index := -1
		var first_reason := ""
		for i in order:
			var candidate: Dictionary = profile.duplicate(true)
			if int(candidate.active_pet) == i: candidate.active_pet = -1
			var reason: String = Riding.can_mount(candidate,i)
			if reason.is_empty():
				index = i
				break
			if first_reason.is_empty() and Riding.composite(str(profile.get("character_id","100000")),int(profile.pets[i].sprite)) >= 0:
				first_reason = str(profile.pets[i].name)+"："+reason
		if index < 0:
			game.message.text = first_reason if not first_reason.is_empty() else "没有此造型可骑乘的伙伴。可骑乘：%s。" % "、".join(PackedStringArray(Riding.rideable_pets(str(profile.get("character_id","100000"))).map(func(sprite): return Riding.pet_name(sprite))))
			refresh_companion()
			return
		if int(profile.active_pet) == index: game.session.select_pet(-1)
		if not game.session.mount_pet(index):
			game.message.text = game.session.last_error
			return
		game.message.text = "骑乘%s。" % str(profile.pets[index].name)
	refresh_companion()
	game.play_click()
	game.checkpoint()
