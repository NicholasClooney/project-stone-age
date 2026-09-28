extends SceneTree
const Policy=preload("res://scripts/battle_auto_policy.gd")
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets();game.load_area_id(300,Vector2i(509,90))
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var helper=game.training_helper;helper.set_process(false)
	var flow=game.pet_workflow;flow.set_process(false)
	check(helper.capture_hp.value==100 and helper.settings.capture_hp==100 and helper.capture_hp.max_value==100,"new capture UI and helper allow and default to100 percent")
	check(hunt.limit.value==0 and hunt.rate.value==0,"hunt defaults to unlimited rolls and unlimited rate")
	check(hunt.train_after_capture.button_pressed and hunt.auto_capture.button_pressed and not hunt.running,"capture-to120 is checked by default but opening does not start")
	check(helper.capture_hp.get_parent()==hunt.capture_page and helper.capture_pet.get_parent()==hunt.capture_page and helper.capture_pet_max_level.get_parent()==hunt.capture_page,"capture settings are single shared controls owned by hunt tab")
	hunt.open_menu();hunt.show_capture_settings(true);await process_frame
	check(helper.capture_hp.is_visible_in_tree() and not hunt.species.is_visible_in_tree(),"capture tab displays settings instead of filter controls")
	check(hunt.panel.get_global_rect().end.x<=1280 and hunt.panel.get_global_rect().end.y<=800,"tabbed hunt panel fits viewport")
	for control in [helper.capture_hp,helper.capture_pet,helper.capture_pet_max_level,hunt.train_after_capture]:
		check(hunt.panel.get_global_rect().encloses(control.get_global_rect()),"capture control fits inside hunt panel")
	check(hunt.status.text.contains("自动找宠") and not hunt.status.text.contains("手动捕捉"),"fresh checked mode has accurate automatic workflow ready hint")
	game.encounter_rng.seed=778899;hunt.start_button.pressed.emit();hunt.set_process(true);await process_frame;await process_frame;hunt.set_process(false)
	check(hunt.running and flow.phase=="hunt" and game.paused_input,"fresh checked default starts actual processing without toggling mode")
	flow.stop_cycle()
	helper.capture_hp.value=37;helper.capture_pet_max_level.value=4;helper.capture_pet.select(1);helper.capture_pet.item_selected.emit(1)
	var ident:String=game.session.snapshot().pets[0].pet_id
	check(game.training_settings.capture_hp==37 and game.training_settings.capture_pet_id==ident,"capture tab preserves explicit threshold and stable-ID selection")
	hunt.close_menu();helper.open_menu()
	check(helper.capture_hp.value==37 and str(helper.capture_pet.get_item_metadata(helper.capture_pet.selected))==ident,"opening helper does not reset shared capture settings")
	check(not helper.capture_hp.is_visible_in_tree(),"training panel has no duplicate visible capture controls")
	helper.close_menu()
	game.adventure_menu.open_pet_comparison(ident)
	var overlay=game.adventure_menu.panel.get_node("PetComparisonPanel")
	check(not overlay.has_node("CompareStartCycle"),"comparison no longer starts a workflow directly")
	overlay.get_node("CompareContinueHunt").pressed.emit()
	check(hunt.visible and not hunt.running and not flow.active() and hunt.species.get_selected_id()==92,"comparison opens hunt with same species preselected without starting")
	hunt.train_after_capture.button_pressed=false
	hunt.show_capture_settings(false);hunt.limit.value=234567
	hunt.rate.get_line_edit().grab_focus();hunt.rate.get_line_edit().text="6789"
	hunt.start_button.pressed.emit()
	check(int(hunt.filter.rate)==6789 and int(hunt.filter.limit)==234567 and helper.capture_hp.value==37,"start commits pending typed rate on first click and preserves cap/capture settings")
	check(hunt.running and not flow.active(),"unchecked start uses ordinary hunt")
	hunt.stop_hunt("test")
	hunt.train_after_capture.button_pressed=true;await process_frame
	check(not hunt.start_button.get_global_rect().intersects(hunt.stop_button.get_global_rect()),"long training start caption does not overlap Stop")
	hunt.start_button.pressed.emit()
	check(hunt.running and flow.phase=="hunt" and hunt.auto_capture.button_pressed,"checked start routes to one cycle and implies capture")
	hunt.set_process(true);await process_frame;await process_frame;hunt.set_process(false)
	check(hunt.running and world_lock(game),"start from already-open panel preserves input lock through real hunt processing")
	hunt.show_capture_settings(true)
	check(not helper.capture_hp.editable and helper.capture_pet.disabled and not helper.capture_pet_max_level.editable and hunt.train_after_capture.disabled,"all shared capture controls remain locked during hunt across tabs")
	flow.stop_cycle();hunt.close_menu()
	var config:Dictionary=game.session.start_battle_config();game.open_battle_config(config)
	helper.start_capture_battle(0)
	check(helper.settings.capture_hp==37 and helper.settings.capture_pet_id==ident and helper.settings.capture_pet_max_level==4,"ordinary capture handoff uses exact custom hunt settings")
	helper.stop_training("test")
	var state:={"enemies":[{"hp":100,"max_hp":100,"can_capture":true}],"pets":[],"active_pet":-1}
	check(Policy.decide(state,{"preset":"capture"},0).get("action","")=="capture","policy fallback attempts capture at full HP")
	check(Policy.decide(state,{"preset":"capture"},0).get("pet","")=="defend","full HP capture does not attack with the pet")
	check(Policy.decide(state,{"preset":"capture","capture_hp":59},0).has("stop"),"explicit59 still requires an eligible shaving pet above threshold")
	check(Policy.decide(state,{"preset":"capture","capture_hp":20},0).has("stop"),"explicit20 percent threshold is not overwritten by new default")
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();await create_timer(0.3).timeout;game.queue_free();await process_frame;await process_frame
	print("PET CAPTURE SETTINGS: %d failures"%failures);quit(1 if failures else 0)

func world_lock(game)->bool:return game.paused_input and game.pet_workflow.phase=="hunt"
