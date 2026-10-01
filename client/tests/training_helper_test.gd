extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func choose_seed(game, count: int) -> int:
	var rng:=RandomNumberGenerator.new()
	for seed_value in range(10000):
		rng.seed=seed_value
		var valid:=true
		for i in range(count):
			var troop: Dictionary=game.encounter_catalog.roll(int(game.data.map_id),game.cell,rng)
			if troop.is_empty() or not game.battle_view.can_render_troop(troop.enemies):valid=false;break
		if valid:return seed_value
	return -1
func run() -> void:
	# 凯比特 (100298) stands in for original art that cannot be shown. Its
	# bitmaps decode now that overrunning runs are clipped like the original
	# client, so the skip-without-substitute path marks it missing here.
	preload("res://server/troop_art.gd")._validation["100298"] = false
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	game.training_helper.open_menu();game.training_helper.start_training()
	check(not game.training_helper.running and not game.battle_session.snapshot().active,"village refuses automation")
	game.training_helper.close_menu()
	# These pacing/takeover fixtures intentionally use the first original roll.
	game.link.request({"type":"set_automation_settings","settings":{"training":{"select_troops":false,"borrow_troops":false}}})
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,10)
	game.session.gm_set_base_stat(-1,"strength",100)
	game.session.gm_set_base_stat(-1,"toughness",100)
	game.session.gm_heal()
	var helper=game.training_helper
	helper.set_process(false)
	helper.open_menu();helper.compact.button_pressed=true;helper.battle_limit.value=2;helper.hp_floor.value=1;helper.multiplier.select(3);helper.speed.select(3)
	if "--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/training-settings.png")
	var seed_value:=choose_seed(game,2)
	check(seed_value>=0,"find deterministic valid source troops")
	game.encounter_rng.seed=seed_value
	var before: Dictionary=game.session.snapshot().duplicate(true)
	helper.start_training();helper.advance()
	check(helper.compact_active and game.battle_session.snapshot().active and not game.battle_view.visible,"compact mode starts real authority without battle screen")
	check(game.paused_input and helper.visible,"map is visible but movement locked")
	var expected_gold: Dictionary={}
	for i in range(1000):
		if not helper.running:break
		if not game.session._pending.is_empty():expected_gold[game.session._pending.battle_id]=int(game.session._pending.battle_gold)
		helper.advance()
	check(helper.battles==2 and not helper.running,"two battles settle then encounter loop stops at cap")
	check(game.session._pending.is_empty() and not game.paused_input,"final settlement leaves no pending battle or input lock")
	check(game.session.snapshot().player.level>before.player.level,"100x awards actual levels")
	check(game.session.snapshot().player.stat_points>before.player.stat_points,"multiple levels grant allocatable stats")
	var total_gold:=0
	for amount in expected_gold.values():total_gold+=int(amount)
	check(expected_gold.size()==2 and game.session.snapshot().player.gold==before.player.gold+total_gold,"automation awards original level-based currency once per battle without XP multiplier")
	check(game.cell==Vector2i(637,493),"stationary encounters preserve location")
	helper.open_menu();helper.target_level.value=game.session.snapshot().player.level;helper.start_training();helper.advance()
	check(not helper.running and game.session._pending.is_empty(),"target level prevents next encounter")
	helper.open_menu();helper.target_level.value=120;helper.hp_floor.value=100;helper.start_training();helper.advance()
	check(not helper.running and game.session._pending.is_empty(),"health floor protects before entering combat")
	game.encounter_rng.seed=seed_value
	helper.open_menu();helper.hp_floor.value=1;helper.start_training();helper.advance()
	var battle_id: String=game.battle_session.snapshot().battle_id
	await process_frame
	var click:=InputEventMouseButton.new()
	click.position=helper.stop_button.get_global_transform_with_canvas()*(helper.stop_button.size/2)
	click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;root.push_input(click,true)
	click.pressed=false;root.push_input(click,true)
	check(game.battle_view.visible and not helper.running and not helper.compact_active,"stop expands compact battle for manual control")
	check(game.battle_session.snapshot().battle_id==battle_id,"manual takeover keeps same live battle")
	game.battle_action("developer_escape")
	for i in range(100):game.battle_view._process(0.2)
	game.return_from_battle()
	check(not game.paused_input and game.session._pending.is_empty(),"manual takeover can finish normally")
	game.encounter_rng.seed=seed_value
	helper.open_menu();helper.compact.button_pressed=false;helper.battle_limit.value=1;helper.start_training()
	for i in range(1200):
		if not helper.running:break
		game.battle_view._process(0.1);helper.advance()
	check(helper.battles==1 and not helper.running,"animated mode also completes automatic battle and stops")
	game.encounter_rng.seed=seed_value
	helper.open_menu();helper.compact.button_pressed=true;helper.target_level.value=0;helper.start_training();helper.advance()
	check(game.battle_session.snapshot().active,"zero level target permits continued pet training")
	for i in range(200):
		if not game.battle_session.snapshot().active:break
		helper.advance()
	var settled: Dictionary=game.session.snapshot().duplicate(true)
	helper.stop_training("stop after reward")
	check(not game.battle_view.visible and not game.paused_input,"stopping completed compact battle returns directly without stale result screen")
	check(game.session.snapshot()==settled and game.session._pending.is_empty(),"stopping after settlement does not duplicate rewards")
	# Stop on real battle health and retain the same individual/authority.
	game.encounter_rng.seed=seed_value
	helper.open_menu();helper.compact.button_pressed=true;helper.hp_floor.value=20;helper.start_training();helper.advance()
	game.battle_session._state.player_hp=1
	helper.advance()
	check(not helper.running and game.battle_view.visible and game.battle_session.snapshot().active,"low combat HP stops and exposes manual takeover")
	game.battle_action("developer_escape")
	for i in range(100):game.battle_view._process(0.2)
	game.return_from_battle();game.session.gm_heal()
	var low_pet:={"player_hp":100,"player_max_hp":100,"active_pet":0,"ride_pet":-1,"pets":[{"hp":1,"max_hp":100,"name":"pet"}]}
	var automation=game.backend.automation
	automation.settings.protect = false
	check(not helper.health_reason(low_pet).is_empty(),"without 练级保护 active pet health triggers protection")
	automation.settings.protect = true
	check(helper.health_reason(low_pet).is_empty(),"with 练级保护 a low pet does not stop the run (it may fall and is brought back)")
	check(not helper.health_reason({"player_hp":100,"player_max_hp":100,"active_pet":-1,"ride_pet":0,"pets":[{"hp":1,"max_hp":100,"name":"mount"}]}).is_empty(),"ridden pet health triggers protection")
	helper.starting_ride=0
	check(not helper.health_reason({"player_hp":100,"player_max_hp":100,"active_pet":-1,"ride_pet":-1,"pets":[{"hp":0,"max_hp":100,"name":"mount"}]}).is_empty(),"dead dismounted pet still triggers protection")
	# Source art failures are retried without substituting a different enemy.
	var missing_seed:=-1
	var rng:=RandomNumberGenerator.new()
	for seed_candidate in range(1000):
		rng.seed=seed_candidate
		var troop: Dictionary=game.encounter_catalog.roll(100,game.cell,rng)
		if not troop.is_empty() and not game.battle_view.can_render_troop(troop.enemies):missing_seed=seed_candidate;break
	game.encounter_rng.seed=missing_seed
	helper.open_menu();helper.hp_floor.value=1;helper.start_training();helper.advance()
	check(missing_seed>=0 and helper.running and helper.skipped==1 and game.session._pending.is_empty(),"missing art troop skips without pending battle or reward")
	helper.stop_training("test skip")
	# A lethal first enemy action settles defeat and ends the loop in the village.
	game.encounter_rng.seed=seed_value
	helper.open_menu();helper.start_training();helper.advance()
	game.battle_session._state.player_hp=0
	game.battle_session._finish("defeat","test lethal outcome")
	game.battle_action("attack")
	check(game.session.snapshot().location.map_id==1000,"compact defeat checkpoint uses village before return tick")
	helper.advance()
	check(int(game.data.map_id)==1000 and not game.training_helper.running and game.session._pending.is_empty(),"defeat settles once and returns to village without restarting")
	check(game.training_helper.multiplier.selected==3 and game.battle_view.playback_speed==8,"helper choices survive map rebuild")
	# A find-pet cycle's capture runs never pop this progress window up, and
	# their end leaves the player's open windows and input alone.
	helper.hide();game.pet_hunt_menu.minimized=false
	game.show_adventure_menu("pets")
	var flow_status:={"running":true,"flow":{"phase":"capture","showcase":false}}
	helper.on_status(flow_status)
	check(not helper.visible,"a find-pet capture run does not show the progress window")
	game.state.automation["flow"]={"phase":"capture","showcase":false}
	helper.on_event({"kind":"battle_stopped","reason":"本场自动战斗已完成"})
	check(game.adventure_menu.visible and not helper.visible,"its end leaves the open pet window as it was")
	game.state.automation["flow"]={"phase":"idle"}
	game.close_adventure_menu()
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("TRAINING HELPER: %d failures"%failures)
	quit(1 if failures else 0)
