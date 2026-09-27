extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok:failures+=1
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	await process_frame
	check(not game.begin_wild_battle(),"village cannot force a wild encounter")
	check(game.switch_area(true,Vector2i(45,45)),"load ordinary Samgir wilderness")
	var next: Vector2i = game.cell+Vector2i.LEFT
	# Find a deterministic first-step hit without changing source probabilities.
	var chosen := -1
	for seed_value in range(1000):
		game.encounter_catalog.pressure=0
		game.encounter_rng.seed=seed_value
		if game.encounter_catalog.step(int(game.data.map_id),next,game.encounter_rng):
			chosen=seed_value
			break
	check(chosen>=0,"original area permits ordinary encounters")
	game.encounter_catalog.pressure=0
	game.encounter_rng.seed=chosen
	check(game.request_step(next),"actual wilderness step accepted")
	game._physics_process(1.0)
	await process_frame
	var state: Dictionary = game.battle_session.snapshot()
	if not state.get("active",false):
		check(false,"source walking encounter failed: "+str(game.message.text))
		game.queue_free()
		await process_frame
		quit(1)
		return
	check(game.battle_view.visible and state.active and game.paused_input,"walking opens integrated source battle")
	check(state.enemies.size()>=1 and state.enemies.size()<=10,"source troop count survives renderer")
	for foe in state.enemies:
		check(str(foe.species).begins_with("original_") and foe.has("source_enemy_id"),"foe retains original template and enemy provenance")
	var battle_id: String = state.battle_id
	game.dev_encounter()
	check(game.battle_session.snapshot().battle_id==battle_id,"developer button cannot replace live battle")
	while game.battle_view.is_animating():game.battle_view._process(0.25)
	game.battle_action("developer_escape")
	while game.battle_view.is_animating():game.battle_view._process(0.25)
	game.return_from_battle()
	check(not game.paused_input and not game.battle_view.visible and game.cell==next,"source battle settles and resumes same field cell")
	var missing := [{"sprite":100298}]
	check(not game.battle_view.can_render_troop(missing),"broken original animation is rejected without replacement")
	check(game.session._pending.is_empty(),"rejected art and escape leave no pending battle")
	game.random_encounters=false
	game.encounter_catalog.pressure=100
	game.handle_arrival()
	check(not game.battle_view.visible,"developer encounter toggle suppresses walking encounters")
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop()
	game.music.stream=null;game.effect.stream=null
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("WILD INTEGRATION: %d failures"%failures)
	quit(1 if failures else 0)
