extends SceneTree
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	game.clone_button.button_pressed=true
	check(game.session.clone_squad_enabled,"DEV toggle activates five-person squad")
	game.dev_go_adventure()
	check(game.clone_button.button_pressed,"squad selection survives map rebuild")
	game.begin_battle()
	check(game.battle_session.snapshot().allies.size()==4 and game.battle_view.actors.size()==16,"real battle creates four independently rendered mirrors")
	for i in range(100):game.battle_view._process(0.1)
	game.battle_action("attack")
	var state: Dictionary=game.battle_session.snapshot()
	check(state.turn_order[0]=="player","real integrated battle acts on player command first")
	check(state.turn_order.has("ally"),"mirrors automatically act without further commands")
	for i in range(300):game.battle_view._process(0.1)
	check(game.battle_view.state.allies==state.allies,"renderer receives actual independent clone health")
	if state.active:game.battle_action("developer_escape")
	for i in range(300):game.battle_view._process(0.1)
	game.return_from_battle()
	game.session.gm_heal()
	check(game.session.grant_starter_pets() and game.session.select_pet(0) and game.session.set_character("100010") and game.session.mount_pet(1),"configure real blue dragon and tiger mount before mirror battle")
	# Default borrowing requires real combat strength, including the mount.
	game.session.gm_raise_level(-1,120);game.session.gm_raise_level(1,120)
	game.session.gm_set_base_stat(-1,"strength",500);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var real_roster: Array=game.session.snapshot().pets.duplicate(true)
	var helper=game.training_helper
	helper.set_process(false)
	helper.open_menu();helper.compact.button_pressed=true;helper.hp_floor.value=1;helper.battle_limit.value=1;helper.start_training()
	game.encounter_rng.seed=0
	check(helper.select_troops.button_pressed and helper.borrow_troops.button_pressed,"mirror regression exercises default-on local troop selection")
	var entered: bool=await Wait.until(self,func():
		if game.battle_session.snapshot().active:return true
		if helper.running:helper.advance()
		return bool(game.battle_session.snapshot().active))
	var actual: Dictionary=game.battle_session.snapshot().get("training_borrow",{})
	var admitted:=preload("res://server/training_borrow.gd").available(game.backend.encounter_catalog,game.world_catalog,game.session.snapshot())
	var accepted_pool: bool=not actual.is_empty() and admitted.any(func(row):return int(row.group_id)==int(actual.group_id) and int(row.map_id)==int(actual.map_id))
	check(entered and game.backend.automation.training_selection.ready and (accepted_pool or (actual.is_empty() and int(game.session._pending.get("group_id",-1)) in game.backend.automation.training_selection.allowed)),"default-on scoring enters an accepted local or fully audited pool troop")
	if not entered:
		helper.stop_training("entry failed");game.queue_free();await process_frame
		print("CLONE GAME INTEGRATION: %d failures"%failures);quit(1);return
	check(helper.compact_active and game.battle_session.snapshot().allies.size()==4,"map-only automation also uses five real fighters")
	check(game.backend.battle.get_script().resource_path.ends_with("squad_battle_session.gd"),"map-only automation selects the same squad authority")
	helper.stop_training("test stop")
	check(game.battle_view.visible and game.battle_view.actors.size()==20,"manual takeover restores five mounted fighters and five pets")
	if accepted_pool:check(game.battle_view.battlefield.texture.resource_path==str(actual.texture),"manual takeover renders authoritative source-map battlefield")
	var mirrored: Dictionary=game.battle_session.snapshot()
	check(mirrored.get("ally_pets",[]).size()==4,"compact authority clones all four fighting pets")
	for i in range(4):
		check(int(mirrored.allies[i].mounted_sprite)==101006 and mirrored.allies[i].mount.sprite==100330,"mirror uses current tiger mount")
		check(mirrored.ally_pets[i].sprite==100288 and game.battle_view.actors[16+i].enabled,"mirror fighting pet is independently rendered")
		check(game.battle_view.actors[12+i].character_id=="101006","mirror renders original rider composite")
	if game.battle_session.snapshot().active:game.battle_action("developer_escape")
	for i in range(300):game.battle_view._process(0.1)
	game.return_from_battle()
	check(game.session.snapshot().pets==real_roster,"temporary mirror pet and mount state never writes into the real roster")
	game.clone_button.button_pressed=false
	game.begin_battle()
	check(game.battle_session.snapshot().get("allies",[]).is_empty() and game.battle_view.actors.size()<16,"disabling mirrors restores ordinary single-player battle")
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("CLONE GAME INTEGRATION: %d failures"%failures);quit(1 if failures else 0)
