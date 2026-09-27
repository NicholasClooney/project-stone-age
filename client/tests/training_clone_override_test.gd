extends SceneTree
var failures:=0
func check(ok:bool,note:String)->void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game);await process_frame
	game.session.grant_starter_pets()
	var ident:String=game.session.snapshot().pets[0].pet_id
	var helper=game.training_helper;helper.set_process(false)
	check(not helper.start_pet_training(ident) and not game.session.clone_squad_enabled and not helper.clone_override_active,"village start failure never acquires clone override")
	helper.close_menu();game.load_area_id(100,Vector2i(637,493));helper=game.training_helper;helper.set_process(false)
	check(helper.start_pet_training(ident) and game.session.clone_squad_enabled and game.clone_button.button_pressed,"training temporarily enables clones and synchronizes DEV toggle")
	helper.stop_training("manual")
	check(not game.session.clone_squad_enabled and not game.clone_button.button_pressed and not helper.clone_override_active,"manual stop restores original off state")
	game.set_clone_squad_enabled(true);helper.start_pet_training(ident);helper.stop_training("manual")
	check(game.session.clone_squad_enabled and game.clone_button.button_pressed,"previously enabled clones remain enabled after stop")
	game.set_clone_squad_enabled(false);helper.hp_floor.value=100;helper.start_pet_training(ident);helper.advance()
	check(not helper.running and not game.session.clone_squad_enabled and not game.clone_button.button_pressed,"health safety stop restores clone override")
	helper.hp_floor.value=10;helper.start_pet_training(ident)
	check(game.pet_workflow.phase=="idle","reload fixture exercises standalone training without workflow")
	game.load_area_id(100,Vector2i(637,493));helper=game.training_helper;helper.set_process(false)
	check(not game.session.clone_squad_enabled and not game.clone_button.button_pressed and not helper.clone_override_active,"map reload releases standalone helper override before rebuilding UI")
	check(not helper.start_pet_training("pet-missing") and not game.session.clone_squad_enabled,"missing target start failure does not leak clones")
	game.close_adventure_menu();game.music.stop();game.effect.stop();await create_timer(0.3).timeout;game.queue_free();await process_frame;await process_frame
	print("TRAINING CLONE OVERRIDE: %d failures"%failures);quit(1 if failures else 0)
