extends SceneTree
## Windows over a battle: 宠物 / 仓库 / 同种比较 and the other allowed windows
## open while a battle runs (automatic battles keep going behind them), the
## backend refuses to release, store, deploy or dismount the battle's own pets,
## and a manual battle ignores its commands while a window is open.
const Session = preload("res://server/game_session.gd")
const Backend = preload("res://server/backend.gd")
const PREFS := "user://menus-in-battle-test-viewer.cfg"
var failures := 0

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func _initialize() -> void:call_deferred("run")

func key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new();event.keycode = code;event.physical_keycode = code;event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

## Five blue dragons (template 92) with fresh ids: slots A B C D E.
func dragons(session) -> Array:
	var source: Dictionary = session._profile.pets.filter(func(pet):return pet.species=="blue_dragon")[0].duplicate(true)
	session._profile.pets = []
	for i in range(5):
		var pet := source.duplicate(true);pet.erase("pet_id");pet.favorite = false
		session._assign_pet_id(pet)
		session._profile.pets.append(pet)
	session._profile.active_pet = -1;session._profile.ride_pet = -1
	return session._profile.pets.map(func(pet):return str(pet.pet_id))

func run() -> void:
	rules()
	backend_rules()
	await ui()
	print("MENUS IN BATTLE: %d failures" % failures)
	quit(1 if failures else 0)

## GameSession alone: who is in the battle, what is refused, and the result
## landing on the right pets after others were released, stored or withdrawn.
func rules() -> void:
	var session = Session.new();session.grant_starter_pets()
	var ids := dragons(session)
	session._profile.active_pet = 2;session._profile.ride_pet = 3
	var config: Dictionary = session.start_battle_config()
	check(session.battle_pets()=={ids[2]:"出战中",ids[3]:"骑乘中"},"the battle's active pet and mount are its participants")
	var result: Dictionary = session.release_pets([ids[0],ids[2],ids[3]])
	var reasons := {}
	for item in result.skipped:reasons[item.id] = item.reason
	check(int(result.released)==1 and reasons=={ids[2]:"战斗中",ids[3]:"战斗中"},"release during a battle skips only its participants")
	check(not session.store_pet(1) and session.last_error.contains("战斗结束后才能存入仓库"),"storing the active pet is refused with the reason")
	check(session.store_pet(0) and session.snapshot().pet_storage.size()==1,"a pet outside the battle can be stored")
	check(not session.select_pet(1) and session.last_error.contains("战斗中不能更换出战宠物"),"deploying is refused during a battle")
	check(not session.mount_pet(-1) and session.last_error.contains("战斗中"),"dismounting is refused during a battle")
	check(session.retrieve_pet(0),"a warehouse pet can be withdrawn when the party has room")
	# Party now C D E B; the battle roster is still A B C D E.
	var kept: Array = session.apply_keep_rule(92,{"tiers":0,"per_tier":0,"champions":0})
	check(not kept.has(ids[2]) and not kept.has(ids[3]) and kept.size()==2,"an automatic keep-rule tidy during a battle keeps its participants")
	var party: Array = session.snapshot().pets.map(func(pet):return str(pet.pet_id))
	check(party==[ids[2],ids[3]],"the tidy released the other dragons")
	var roster: Array = config.pets.duplicate(true)
	roster[3].hp = 1
	var enemy: Dictionary = config.enemies[0]
	var level_before := int(session._profile.pets[0].level)*1000+int(session._profile.pets[0].xp)
	var finished := {"battle_id":config.battle_id,"active":false,"outcome":"win","player_hp":config.player_hp,"potions":config.potions,
		"enemies":[{"species":enemy.species,"hp":0,"defeated_by_pet_index":2,"defeated_with_ride_index":-1}],"captured_species_list":[],
		"pets":roster,"active_pet":2,"ride_pet":3}
	for i in range(1,config.enemies.size()):finished.enemies.append({"species":config.enemies[i].species,"hp":0,"defeated_by_pet_index":-1,"defeated_with_ride_index":-1})
	check(session.apply_battle_result(finished),"the result settles although the party changed during the battle")
	var after: Dictionary = session.snapshot()
	check(str(after.pets[after.active_pet].pet_id)==ids[2] and str(after.pets[after.ride_pet].pet_id)==ids[3],"active pet and mount follow their ids to the new slots")
	check(int(after.pets[1].hp)==1 and int(after.pets[0].level)*1000+int(after.pets[0].xp)>level_before,"hp and experience land on the right pets")
	check(session.battle_pets().is_empty() and session.release_pets([ids[3]]).skipped[0].reason=="骑乘中","after the battle only the usual protections remain")
	# The party keeps room for the battle's possible captures.
	var full = Session.new();full.grant_starter_pets()
	var spare: Dictionary = full._profile.pets[0].duplicate(true)
	while full._profile.pets.size()<Session.PET_CAPACITY:
		var copy := spare.duplicate(true);copy.erase("pet_id");full._assign_pet_id(copy);full._profile.pets.append(copy)
	full.store_pet(Session.PET_CAPACITY-1)
	full.start_battle_config("wooli",false,1)
	check(not full.retrieve_pet(0) and full.last_error.contains("捕捉"),"withdrawing into the last free slot waits while the battle may still capture")

## The authority over its command interface (what a remote client sends).
func backend_rules() -> void:
	var backend = Backend.new()
	backend.session.grant_starter_pets()
	var ids := dragons(backend.session)
	backend.session._profile.active_pet = 1
	check(bool(backend.handle({"type":"begin_battle"}).ok),"battle opens")
	var derived: Dictionary = backend.full_snapshot().derived
	check(derived.battle_pets=={ids[1]:"出战中"},"clients learn the battle's pets from the profile")
	var store: Dictionary = backend.handle({"type":"store_pet","index":1})
	check(not store.ok and str(store.reason).contains("战斗结束后才能存入仓库"),"store_pet of the active pet is rejected with the reason")
	var deploy: Dictionary = backend.handle({"type":"select_pet","index":0})
	check(not deploy.ok and str(deploy.reason).contains("战斗中不能更换出战宠物"),"select_pet is rejected during a battle")
	var released: Dictionary = backend.handle({"type":"release_pets","ids":[ids[0],ids[1]]})
	check(int(released.result.released)==1 and released.result.skipped[0].reason=="战斗中","release_pets releases the bystander and skips the fighter")
	check(bool(backend.handle({"type":"store_pet","index":1}).ok),"a bystander can be stored")
	# Party now B D E; roster slot 0 (released) and 2 (stored) cannot come in.
	var switch: Dictionary = backend.handle({"type":"battle_command","action":"switch","target":0,"switch_pet":2})
	check(not switch.ok and str(switch.reason).contains("不能换上场"),"a pet stored during the battle cannot be switched in")
	backend.set_capture_assist(true)
	var helpers: Dictionary = backend.session.battle_pets()
	check(helpers.values().has("削血宠") and helpers[ids[1]]=="出战中","an automatic capture battle also holds its capture helpers")
	backend.set_capture_assist(false)
	backend.handle({"type":"battle_escape_dev"})
	backend.handle({"type":"battle_close"})
	check(backend.session.battle_pets().is_empty() and backend.full_snapshot().derived.battle_pets.is_empty(),"the locks lift when the battle ends")
	backend.free()

func ui() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	var ids := dragons(game.backend.session)
	game.backend.publish()
	game.session.gm_set_base_stat(-1,"toughness",300);game.session.gm_heal()
	game.session.select_pet(0)
	var view = game.battle_view
	check(view.get_index()<game.adventure_menu.get_index() and view.get_index()<game.settings_menu.get_index(),"allowed windows sit above the battle view in the tree")
	# ---- an automatic battle keeps running behind the pet window ----
	game.link.request({"type":"begin_battle","enemy_count":3})
	await process_frame
	check(view.visible and game.battle_session.snapshot().active,"a battle is on screen")
	var helper = game.training_helper
	helper.compact.button_pressed = false
	helper.start_training()
	helper.minimize()
	check(helper.running and helper.minimized,"本场自动战斗 runs, minimized")
	var speed: float = view.playback_speed
	game.show_adventure_menu("pets")
	var menu = game.adventure_menu
	check(menu.visible and view.visible and helper.running,"the pet window opens over the automatic battle")
	check(menu.z_index>20 and view.world_modal_open(),"it draws above the battle and holds the battle's commands")
	menu.open_pet_comparison(ids[1]);await process_frame
	var overlay = menu.panel.get_node("PetComparisonPanel")
	var fighter: CheckBox = overlay.find_child("CompareSelect_"+ids[0],true,false)
	check(fighter.disabled and fighter.tooltip_text.contains("战斗结束后才能放生"),"同种比较 greys the fighting pet with the reason")
	check(overlay.find_child("CompareTransfer_"+ids[0],true,false).disabled and overlay.find_child("CompareDeploy_"+ids[1],true,false).disabled,"its 存入仓库 and every 出战 wait for the battle")
	var bystander: CheckBox = overlay.find_child("CompareSelect_"+ids[1],true,false)
	check(not bystander.disabled,"other pets stay selectable")
	bystander.button_pressed = true;await process_frame
	menu.panel.get_node("PetComparisonPanel").find_child("CompareRelease",true,false).pressed.emit();await process_frame
	menu.panel.get_node("PetComparisonPanel").find_child("CompareReleaseConfirm",true,false).pressed.emit();await process_frame
	check(not game.session.snapshot().pets.any(func(pet):return str(pet.pet_id)==ids[1]) and game.battle_session.snapshot().active,"releasing a bystander works mid-battle")
	menu.pet_compare_open = false;menu.pet_storage_open = true;menu.pet_storage_target_id = ids[2];menu.rebuild();await process_frame
	menu.panel.get_node("PetStoragePanel/StoreSelectedPet").pressed.emit();await process_frame
	check(game.session.snapshot().pet_storage.any(func(pet):return str(pet.pet_id)==ids[2]),"仓库 stores a bystander mid-battle")
	menu.pet_storage_target_id = ids[0];menu.rebuild();await process_frame
	var store: Button = menu.panel.get_node("PetStoragePanel/StoreSelectedPet")
	check(store.disabled and store.tooltip_text.contains("战斗结束后才能存入仓库"),"仓库 will not store the fighting pet")
	var turn := int(game.battle_session.snapshot().get("turn",0))
	for i in range(80):
		if int(game.battle_session.snapshot().get("turn",0))>turn+1 or not game.battle_session.snapshot().active:break
		view._process(0.5);helper.advance()
		await process_frame
	check(int(game.battle_session.snapshot().get("turn",0))>turn or not game.battle_session.snapshot().active,"the battle keeps playing behind the window")
	check(menu.visible and view.visible and view.playback_speed==speed,"window and battle stay up at the same speed")
	var shown: String = str(view.state.get("battle_id",""))
	var clock: float = view.elapsed
	game.close_adventure_menu()
	check(view.visible and str(view.state.get("battle_id",""))==shown and view.elapsed>=clock,"closing the window leaves the battle as it was")
	for i in range(120):
		if not helper.running:break
		view._process(0.5);helper.advance()
		await process_frame
	game.link.request({"type":"auto_stop"})
	if game.battle_session.snapshot().active:game.battle_session.developer_escape()
	for i in range(20):
		if not game.state.battle_open:break
		view._process(1.0);game.return_from_battle()
		await process_frame
	check(not game.state.battle_open and game.session.battle_pets().is_empty(),"the automatic battle finished and its locks lifted")
	# ---- a manual battle waits while a window is open ----
	game.link.request({"type":"begin_battle"})
	await process_frame
	view._process(5.0)
	game.settings_menu.open_menu()
	var capture: TextureButton = view.commands.filter(func(button):return button.get_meta("action")=="capture")[0]
	var preselected: String = view.selected_action
	var first_turn := int(game.battle_session.snapshot().get("turn",0))
	capture.pressed.emit()
	view.select_target(1)
	check(view.selected_action==preselected and int(game.battle_session.snapshot().get("turn",0))==first_turn,"battle commands and targets do nothing under 设置")
	await key(KEY_ESCAPE)
	check(not game.settings_menu.visible and view.visible and game.battle_session.snapshot().active,"Esc closes 设置 and the battle waits")
	capture.pressed.emit()
	check(view.selected_action=="capture","closing the window returns control")
	await key(KEY_ESCAPE)
	check(view.selected_action=="" and not game.settings_menu.visible,"Esc still backs out of a chosen command")
	await key(KEY_ESCAPE)
	check(game.settings_menu.visible,"with nothing to back out of, Esc opens 设置 over the battle")
	game.settings_menu.close_menu()
	await key(KEY_G)
	check(game.helper_menu.visible and not game.helper_menu.find_child("HelperPets",true,false).disabled and game.helper_menu.find_child("HelperMapOverview",true,false).disabled,"游戏助手 opens in battle with only the allowed entries")
	game.helper_menu.close_menu()
	await key(KEY_B)
	check(game.pet_encyclopedia.visible and view.world_modal_open(),"宠物大全 opens over the battle")
	game.pet_encyclopedia.close_menu()
	game.battle_session.developer_escape()
	view._process(5.0)
	game.settings_menu.open_menu()
	await key(KEY_ENTER)
	check(view.visible,"Enter does not leave the finished battle while a window is open")
	game.settings_menu.close_menu()
	await key(KEY_ENTER)
	check(not view.visible and not game.state.battle_open and not game.paused_input,"after closing it Enter returns to the map")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream = null;game.effect.stream = null
	game.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
