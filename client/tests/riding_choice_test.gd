extends SceneTree
## Every imported ridePetTable mount: backend rules, the pet window's ride
## button and a mounted battle with a mount other than the gold tiger.
const Riding = preload("res://scripts/riding.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failures += 1
func _initialize() -> void: call_deferred("run")

## Starter pets re-dressed as 格鲁西斯 (100329), rideable by appearance 100000,
## and gold tiger (100330), which only other appearances ride.
func prepare(session) -> void:
	session.grant_starter_pets()
	session.set_character("100000")
	session._profile.pets[0].sprite = 100329
	session._profile.pets[0].name = "格鲁西斯"
	session._profile.pets[1].sprite = 100330
	session._profile.pets[1].name = "金虎"
	for pet in session._profile.pets:pet.loyalty = 100

func run() -> void:
	check(Riding.manifest().get("pairs",{}).size() > 19,"importer provides more than the gold tiger and brontosaurus pairs")
	check(Riding.composite("100000",100329) == 101004 and Riding.composite("100020",100396) == 101010,"ridePetTable pairs for other mounts resolve")
	check(Riding.rideable_pets("100000") == [100329,100352],"appearance 100000 rides its two source mounts")
	check(Riding.pet_name(100329) == "格鲁西斯","mount names come from the source enemy templates")
	backend_rules()
	await menu_button()
	await mounted_battle()
	print("Riding choice failures: ",failures)
	quit(1 if failures else 0)

func backend_rules() -> void:
	var session = preload("res://server/game_session.gd").new()
	prepare(session)
	check(not session.mount_pet(1),"pet without a composite for this character is rejected")
	check(session.last_error.contains("可骑乘") and session.last_error.contains("格鲁西斯") and session.last_error.contains("布林帖斯"),"rejection names the pets this character can ride")
	check(session.mount_pet(0) and int(session.snapshot().ride_pet) == 0,"rideable source mount is accepted")
	check(not session.mount_pet(2) and session.last_error.contains("下骑"),"a second mount needs a dismount first")
	check(session.mount_pet(-1) and int(session.snapshot().ride_pet) == -1,"dismount")
	session._profile.pets[0].loyalty = 99
	check(not session.mount_pet(0) and session.last_error.contains("忠诚"),"loyalty 100 required")
	session._profile.pets[0].loyalty = 100
	session._profile.pets[0].level = 7
	check(not session.mount_pet(0) and session.last_error.contains("5"),"player level + 5 bound")
	session._profile.pets[0].level = 1
	session.select_pet(0)
	check(not session.mount_pet(0) and session.last_error.contains("出战"),"battling pet cannot be ridden")
	session.select_pet(-1)
	check(session.mount_pet(0),"mount again after standby")
	session.set_character("100010")
	check(int(session.snapshot().ride_pet) == -1,"changing to an appearance without that composite dismounts")

func menu_button() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.profile_persistence = false
	root.add_child(world)
	await process_frame
	world.muted = true
	prepare(world.session)
	world.show_adventure_menu("pets")
	var menu = world.adventure_menu
	menu.selected_pet = 1
	menu.rebuild()
	var button: Button = menu.panel.find_child("PetMount",true,false)
	var reason = menu.panel.find_child("PetMountReason",true,false)
	check(button != null and button.disabled and button.text.contains("金虎"),"ride button is disabled for a pet this character cannot ride")
	check(reason != null and reason.text.contains("格鲁西斯"),"disabled ride button explains why")
	menu.selected_pet = 0
	menu.rebuild()
	button = menu.panel.find_child("PetMount",true,false)
	check(not button.disabled and button.text.begins_with("骑乘"),"ride button enabled for a rideable pet")
	button.pressed.emit()
	await process_frame
	check(int(world.session.snapshot().ride_pet) == 0,"ride button mounts the selected pet")
	check(str(world.player.mounted_character_id) == "101004","walking art switches to the native composite")
	button = menu.panel.find_child("PetMount",true,false)
	check(button.text.begins_with("下骑") and not button.disabled,"ride button offers dismount for the ridden pet")
	button.pressed.emit()
	await process_frame
	check(int(world.session.snapshot().ride_pet) == -1 and str(world.player.mounted_character_id) == "","dismount from the pet window")
	world.close_adventure_menu()
	world.dev_toggle_riding()
	check(int(world.session.snapshot().ride_pet) == 0,"DEV riding picks the first pet this character can ride")
	world.dev_toggle_riding()
	check(int(world.session.snapshot().ride_pet) == -1,"DEV riding toggles back off")
	world.music.stop();world.effect.stop();world.queue_free()
	await process_frame
	await process_frame

func mounted_battle() -> void:
	var session = preload("res://server/game_session.gd").new()
	prepare(session)
	session.mount_pet(0)
	var config: Dictionary = session.start_battle_config("wooli",false,1)
	check(int(config.mounted_sprite) == 101004,"battle config carries the new mount's composite")
	config.player_attack = 10000
	config.player_speed = 10000
	var authority = preload("res://server/battle_session.gd").new()
	var state: Dictionary = authority.start_battle(config)
	var view = load("res://scripts/battle_view.gd").new()
	root.add_child(view)
	await process_frame
	view.set_process(false)
	view.battle_effects.set_process(false)
	view.open_battle(state)
	for i in range(120): view._process(1.0/60.0)
	check(str(view.actors[0].character_id) == "101004","battle draws the native 格鲁西斯 rider composite")
	check(view.actors[0].animations.has("0_3") and view.riding_hp_bar.visible,"mounted actor has attack art and mount health")
	var result: Dictionary = authority.submit_action("attack")
	view.show_state(result)
	check(result.outcome == "win" and session.apply_battle_result(result),"mounted battle settles")
	check(int(session.snapshot().pets[0].xp) > 0 and int(session.snapshot().ride_pet) == 0,"new mount earns riding experience and stays mounted")
	view.queue_free()
	await process_frame
