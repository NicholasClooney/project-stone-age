extends SceneTree
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
	var helper=game.training_helper
	helper.set_process(false)
	helper.open_menu();helper.compact.button_pressed=true;helper.hp_floor.value=1;helper.battle_limit.value=1;helper.start_training()
	game.encounter_rng.seed=0
	helper.advance()
	check(helper.compact_active and game.battle_session.snapshot().allies.size()==4,"map-only automation also uses five real fighters")
	check(game.battle_session.get_script().resource_path.ends_with("squad_battle_session.gd"),"map-only automation selects the same squad authority")
	helper.stop_training("test stop")
	check(game.battle_view.visible and game.battle_view.actors.size()==16,"manual takeover restores all five fighters")
	if game.battle_session.snapshot().active:game.battle_action("developer_escape")
	for i in range(300):game.battle_view._process(0.1)
	game.return_from_battle()
	game.clone_button.button_pressed=false
	game.begin_battle()
	check(game.battle_session.snapshot().get("allies",[]).is_empty() and game.battle_view.actors.size()<16,"disabling mirrors restores ordinary single-player battle")
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("CLONE GAME INTEGRATION: %d failures"%failures);quit(1 if failures else 0)
