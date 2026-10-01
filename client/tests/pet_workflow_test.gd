extends SceneTree
var failures:=0
class FixedTroop extends RefCounted:
	var troop: Dictionary
	func roll(_map, _cell, _rng, _held_items: Array = []) -> Dictionary:return troop.duplicate(true)
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game)
	await process_frame
	game.session.grant_starter_pets()
	# 展示模式 off: this suite covers the full-speed find-pet cycle.
	game.link.request({"type":"set_automation_settings","settings":{"hunt":{"showcase":false,"stop_after":1}}})
	game.load_area_id(100,Vector2i(637,493))
	game.session.gm_raise_level(-1,120);game.session.gm_set_base_stat(-1,"toughness",500);game.session.gm_heal()
	var flow=game.pet_workflow;flow.set_process(false)
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var helper=game.training_helper;helper.set_process(false)
	check(flow.start_cycle(),"cycle starts at current wilderness location")
	check(hunt.preset.selected==3 and hunt.rate.value==0,"cycle preserves default full +2 / unlimited-rate criteria")
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
	check(flow.phase=="compare" and not flow.pet_id.is_empty() and game.adventure_menu.visible,"real capture settlement identifies new stable ID, levels it and compares")
	var active_pet:Dictionary=game.session.snapshot().pets[game.session.snapshot().active_pet]
	check(active_pet.pet_id==flow.pet_id and int(active_pet.level)==120,"captured individual is active at level 120")
	check(not helper.running and not game.battle_view.visible,"compact capture and instant levelling run no training battles")
	var projected:Dictionary=preload("res://server/progression.gd").project_pet(fixture.troop.enemies[0],120)
	check(projected.base_stats==active_pet.base_stats and int(projected.attack)==int(active_pet.attack) and int(projected.defence)==int(active_pet.defence) and int(projected.speed)==int(active_pet.speed) and int(projected.max_hp)==int(active_pet.max_hp),"hunt-time Lv.120 projection equals the real captured and levelled pet")
	check(not game.session.clone_squad_enabled and not game.clone_button.button_pressed,"completed pet cycle leaves clone-off state and DEV toggle unchanged")
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
