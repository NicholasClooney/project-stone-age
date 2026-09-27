extends SceneTree
var failures:=0
class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng) -> Dictionary:return troop.duplicate(true)
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var flow=game.pet_workflow;flow.set_process(false)
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var helper=game.training_helper;helper.set_process(false)
	check(flow.start_cycle(),"cycle starts at current wilderness location")
	check(hunt.preset.selected==3 and hunt.rate.value==5000,"cycle preserves default full +2 / 5000 criteria")
	flow.stop_cycle();flow.advance()
	check(flow.phase=="paused" and not hunt.running,"stop cancels hunt without restarting")
	hunt.close_menu();hunt.apply_preset(0)
	check(flow.start_cycle(),"new cycle uses current hunt criteria")
	var fixture=FixedTroop.new()
	var rng=RandomNumberGenerator.new();rng.seed=1234
	for i in range(100):
		var rolled: Dictionary=game.encounter_catalog.roll(100,game.cell,rng)
		for actor in rolled.get("enemies",[]):
			if int(actor.level)==1 and actor.can_capture and game.battle_view.can_render_troop([actor]):
				actor.hp=1
				fixture.troop={"enemies":[actor]};break
		if not fixture.troop.is_empty():break
	check(not fixture.troop.is_empty(),"small fixture uses real local newborn with capture-ready health")
	hunt.hunt_catalog=fixture;hunt.scan_once()
	check(flow.phase=="capture" and helper.capture_target==0,"hunt hands exact matched target to capture phase")
	for i in range(100):
		game.battle_view._process(0.2);helper.advance();flow.advance()
		if flow.phase!="capture":break
	check(flow.phase=="train" and not flow.pet_id.is_empty(),"real capture settlement identifies new stable ID and starts training")
	check(game.session.snapshot().pets[game.session.snapshot().active_pet].pet_id==flow.pet_id,"captured individual is active")
	check(helper.running and helper.settings.level==0 and helper.settings.xp==10 and helper.settings.speed==8 and helper.compact_active==false,"level-120 player does not stop pet goal and uses requested speed/XP")
	# Exercise one actual compact training battle before the fast level boundary.
	game.encounter_rng.seed=1234
	for i in range(100):
		helper.advance()
		if helper.compact_active or not helper.running:break
	check(helper.compact_active and game.battle_session.snapshot().active and game.battle_session.snapshot().allies.size()==4,"training starts actual compact battle with five-person clone team")
	for i in range(250):
		helper.advance()
		if helper.battles>=1 or not helper.running:break
	check(helper.battles==1 and helper.running,"training settles one actual battle and continues below pet goal")
	# Fast boundary fixture: progression authority raises this one pet to the goal;
	# production helper still performs the real stop and controller comparison handoff.
	game.session.gm_raise_level(game.session.snapshot().active_pet,120)
	helper.advance();flow.advance()
	check(flow.phase=="compare" and game.adventure_menu.visible,"pet level goal ends one cycle at comparison")
	check(not game.session.clone_squad_enabled and not game.clone_button.button_pressed,"completed pet cycle restores original clone-off state and DEV toggle")
	var count: int=game.session.snapshot().pets.size()
	flow.advance();flow.advance()
	check(game.session.snapshot().pets.size()==count and not helper.running and not hunt.running,"comparison waits with no repeated reward or next cycle")
	game.adventure_menu.hide();game.paused_input=false
	check(flow.start_cycle(),"explicit next cycle can start")
	game.cell+=Vector2i.ONE;flow.advance()
	check(flow.phase=="paused" and not hunt.running,"location change pauses current cycle")
	game.cell-=Vector2i.ONE;hunt.close_menu()
	check(not flow.start_cycle("original_999999") and flow.phase=="paused","comparison species unavailable locally never silently falls back to another pet")
	hunt.close_menu()
	var changed: Dictionary=fixture.troop.enemies[0].duplicate(true)
	changed.growth_seed=int(changed.growth_seed)+1
	check(not flow.same_capture(changed,fixture.troop.enemies[0]),"capture identity guard rejects different growth seed")
	check(flow.start_cycle(),"cycle can restart after explicit local adjustment")
	hunt.hunt_catalog=fixture;hunt.scan_once()
	var battle_id: String=game.battle_session.snapshot().battle_id
	helper.stop_training("已手动停止");flow.advance()
	check(flow.phase=="paused" and game.battle_session.snapshot().active and game.battle_session.snapshot().battle_id==battle_id,"capture stop preserves same live battle for takeover and never starts training")
	check(game.session.snapshot().pets.size()==count,"capture stop grants no pet or duplicate reward")
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("PET WORKFLOW: %d failures"%failures);quit(1 if failures else 0)
