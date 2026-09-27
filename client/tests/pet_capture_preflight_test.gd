extends SceneTree
const Policy=preload("res://scripts/battle_auto_policy.gd")
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets()
	var ident:String=game.session.snapshot().pets[0].pet_id
	while not game.session.snapshot().pets.is_empty():game.session.store_pet(0)
	game.load_area_id(100,Vector2i(637,493))
	var hunt=game.pet_hunt_menu;hunt.set_process(false)
	var flow=game.pet_workflow;flow.set_process(false)
	var helper=game.training_helper;helper.set_process(false)
	hunt.open_menu();hunt.start_button.pressed.emit()
	check(not hunt.running and hunt.rolls==0 and flow.phase=="paused","missing capture pet pauses before any search roll")
	check(hunt.status.text.contains("仓库") and hunt.status.text.contains("Lv.1"),"preflight explains retrieval of a living newborn capture pet")
	hunt.close_menu()
	var config:Dictionary=game.session.start_battle_config();config.enemies[0].can_capture=true;game.open_battle_config(config)
	helper.start_capture_battle(0)
	for frame in range(100):game.battle_view._process(0.2)
	helper.advance()
	check(not helper.running and game.battle_view.visible and game.battle_view.report.text.contains("没有可用低等级宠物"),"battle safety pause exposes reason in visible battle report")
	game.battle_action("developer_escape")
	for frame in range(100):game.battle_view._process(0.2)
	game.return_from_battle()
	check(game.session.retrieve_pet_by_id(ident),"player can retrieve an eligible stored pet")
	hunt.open_menu();hunt.start_button.pressed.emit()
	check(hunt.running and flow.phase=="hunt","explicit restart succeeds after eligible pet is retrieved")
	flow.stop_cycle();hunt.close_menu()
	helper.settings.capture_pet_id="pet-99999";helper._refresh_pet_choices();hunt.open_menu();hunt.start_button.pressed.emit()
	check(not hunt.running and hunt.status.text.contains("pet-99999"),"missing explicit stable-ID selection names the unavailable pet")
	var state:={"pets":[{"pet_id":"pet-1","level":1,"hp":0},{"pet_id":"pet-2","level":1,"hp":50}],"ride_pet":1}
	check(Policy.capture_pet_choice(state,{"capture_pet":-1,"capture_pet_max_level":10},1).has("stop"),"shared eligibility rejects dead and mounted newborn pets")
	state={"pets":[{"pet_id":"pet-3","level":11,"hp":50}],"ride_pet":-1}
	check(Policy.capture_pet_choice(state,{"capture_pet":-1,"capture_pet_max_level":11},1).has("stop"),"automatic selection retains target-level safety limit")
	check(Policy.capture_pet_choice(state,{"capture_pet":0,"capture_pet_id":"pet-3","capture_pet_max_level":11},1).get("index",-1)==0,"explicit user selection follows same existing max-level rule")
	game.close_adventure_menu();game.music.stop();game.effect.stop();await create_timer(0.3).timeout;game.queue_free();await process_frame;await process_frame
	print("PET CAPTURE PREFLIGHT: %d failures"%failures);quit(1 if failures else 0)
