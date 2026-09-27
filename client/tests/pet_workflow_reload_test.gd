extends SceneTree
var failures:=0
func check(ok: bool,note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate();game.profile_persistence=false;root.add_child(game)
	await process_frame
	game.load_area_id(100,Vector2i(637,493))
	check(game.pet_workflow.phase=="idle","ordinary travel does not invent workflow pause")
	var old_flow=game.pet_workflow
	var old_hunt=game.pet_hunt_menu
	old_flow.set_process(false);old_hunt.set_process(false)
	check(old_flow.start_cycle(),"start hunt before actual scene reload")
	game.battle_session.set_capture_assist(true)
	check(game.load_area_id(100,Vector2i(637,493)),"validated map reload succeeds")
	check(old_flow.phase=="paused" and not old_hunt.running,"old workflow and hunt quiesced before UI disposal")
	check(game.pet_workflow!=old_flow and game.pet_workflow.phase=="paused" and not game.battle_session.capture_assist,"new UI retains pause and clears capture assist")
	check(game.last_adventure_message.contains("地图发生变化") and game.message.text==game.last_adventure_message,"map pause reason remains visible")
	await process_frame
	game.session._profile.player.hp=1
	var config: Dictionary=game.session.start_battle_config()
	game.open_battle_config(config)
	var flow=game.pet_workflow;flow.set_process(false);flow.phase="capture"
	var helper=game.training_helper;helper.set_process(false);helper.start_capture_battle(0,true)
	for i in range(30):
		for frame in range(100):game.battle_view._process(0.2)
		if not game.battle_session.snapshot().active:break
		game.battle_action("defend")
	check(game.battle_session.snapshot().outcome=="defeat","real authority battle reaches defeat fixture")
	for frame in range(100):game.battle_view._process(0.2)
	game.return_from_battle()
	check(game.pet_workflow!=flow and game.pet_workflow.phase=="paused","defeat return rebuilds UI once without recursive helper settlement")
	check(not helper.running and not game.training_helper.running and not game.battle_session.capture_assist,"defeat disables old and new automation and capture assist")
	check(game.last_adventure_message.contains("战斗失败") and game.pet_workflow.reason.contains("战斗失败"),"defeat-specific pause reason survives rebuild")
	game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
	await process_frame
	print("PET WORKFLOW RELOAD: %d failures"%failures);quit(1 if failures else 0)
