extends SceneTree
const Filter=preload("res://scripts/pet_stat_filter.gd")
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets();game.load_area_id(300,Vector2i(509,90));game.session.gm_heal()
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var flow=game.pet_workflow;flow.set_process(false)
	game.training_helper.set_process(false);game.training_helper.capture_hp.value=100
	check(Filter.enabled(Filter.defaults(92)) and Filter.defaults(92).conditions.sum.value==620,"blue dragon defaults to minimum actual sum 620")
	check(not Filter.enabled(Filter.defaults(194)),"blue default does not leak to other species")
	hunt.open_menu();hunt.show_stat_settings()
	check(hunt.stat_page.visible and not hunt.capture_page.visible and not hunt.species.visible,"attribute tab exclusively displays its own controls")
	hunt.stat_numbers.sum.get_line_edit().grab_focus();hunt.stat_numbers.sum.get_line_edit().text="625";hunt.commit_stat_settings()
	check(game.pet_stat_filters[92].conditions.sum.value==625,"typed minimum commits on first start/apply")
	hunt.stat_numbers.sum.get_line_edit().release_focus();hunt.stat_numbers.sum.value=620;hunt.save_stat_settings()
	check(flow.start_cycle(),"workflow starts with current per-species filter settings")
	check(flow.stat_filter_snapshot[92].conditions.sum.value==620,"loop snapshots current configuration")
	game.pet_stat_filters[92].conditions.sum.value=999
	check(flow.stat_filter_snapshot[92].conditions.sum.value==620,"later UI data mutation cannot change running loop threshold")
	hunt.stop_hunt("test boundary");hunt.hide();game.paused_input=false
	var source:Dictionary=game.session.snapshot().pets[0].duplicate(true)
	var previous_storage:int=game.session.snapshot().pet_storage.size()
	for turn in range(2):
		var pet:Dictionary=source.duplicate(true);pet.pet_id="pet-filter-%d"%turn;pet.level=120;pet.attack=290;pet.defence=178;pet.speed=151
		game.session._profile.pets.append(pet);game.session._profile.active_pet=game.session._profile.pets.size()-1
		flow.pet_id=pet.pet_id;flow.phase="train";flow.target_stat_filter=Filter.defaults(92)
		flow.complete_trained_pet(pet)
		check(flow.phase=="restart" and flow.stored_count==turn+1 and game.session.snapshot().pet_storage.back().pet_id==pet.pet_id,"unmet actual total 619 stores exact trained individual, round %d"%turn)
		flow.complete_trained_pet(pet)
		check(game.session.snapshot().pet_storage.size()==previous_storage+turn+1,"duplicate completion never stores another pet")
		flow.advance()
		check(flow.phase=="hunt" and hunt.running and hunt.status.text.contains("已自动存仓") and hunt.status.text.contains(pet.pet_id),"next hunt starts and retained notification identifies stored individual")
		hunt.stop_hunt("test boundary");hunt.hide();game.paused_input=false
	var good:Dictionary=source.duplicate(true);good.pet_id="pet-filter-good";good.level=120;good.attack=291;good.defence=178;good.speed=151
	game.session._profile.pets.append(good);game.session._profile.active_pet=game.session._profile.pets.size()-1
	flow.pet_id=good.pet_id;flow.phase="train";flow.target_stat_filter=Filter.defaults(92);flow.complete_trained_pet(good)
	check(flow.phase=="compare" and flow.reason.contains("已达标") and game.adventure_menu.pet_compare_id==good.pet_id,"actual sum 620 stops loop and opens correct comparison")
	check(game.session.snapshot().pet_storage.size()==previous_storage+2 and not hunt.running,"qualified pet remains carried and no new hunt starts")
	var all_conditions:=Filter.defaults(92)
	for condition in all_conditions.conditions.values():condition.enabled=true
	flow.reason="已达标 · pet-long-identifier · "+Filter.describe(good,all_conditions)
	game.adventure_menu.rebuild();await process_frame
	var overlay=game.adventure_menu.panel.get_node("PetComparisonPanel")
	var info=overlay.get_node("PetComparisonInfo")
	var pinned=overlay.get_node("ComparePinned_选中")
	check(info.position.y+info.size.y<=pinned.position.y and info.size.x<=overlay.size.x,"four threshold results stay within dedicated wrapped area above selected stats")
	check(hunt.status.position.y+hunt.status.size.y<=hunt.start_button.position.y,"loop progress stays above hunt action buttons")
	game.adventure_menu.hide();game.paused_input=false
	flow.phase="restart"
	var cancel:=InputEventAction.new();cancel.action="ui_cancel";cancel.pressed=true;root.push_input(cancel);flow.advance()
	check(flow.phase=="paused" and not hunt.running,"manual stop between storage and restart is final")
	var stored_before:int=game.session.snapshot().pet_storage.size()
	game.session._profile.ride_pet=game.session.snapshot().pets.size()-1
	flow.phase="train";flow.target_stat_filter.conditions.sum.value=999;flow.complete_trained_pet(good)
	check(flow.phase=="paused" and game.session.snapshot().pet_storage.size()==stored_before and not hunt.running,"storage rejection pauses without deleting, swapping or restarting")
	game.session._profile.ride_pet=-1
	flow.phase="train";flow.target_stat_filter=Filter.defaults(194);flow.complete_trained_pet(good)
	check(flow.phase=="compare" and game.session.snapshot().pet_storage.size()==stored_before,"no enabled conditions retains legacy single cycle even below blue threshold")
	game.adventure_menu.hide();game.paused_input=false
	flow.phase="restart";flow.prepare_scene_reload();flow.advance()
	check(flow.phase=="paused" and not hunt.running,"scene reload after storage cancels restart")
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free();await process_frame
	print("PET STAT WORKFLOW: %d failures"%failures);quit(1 if failures else 0)
