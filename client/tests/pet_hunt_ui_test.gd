extends SceneTree
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, description: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+description)
	if not ok:failures+=1
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false
	root.add_child(game)
	await process_frame
	game.pet_hunt_menu.open_menu()
	check(game.pet_hunt_menu.start_button.disabled,"village cannot start hunting")
	game.pet_hunt_menu.close_menu()
	check(game.switch_area(true,Vector2i(45,45)),"enter original wilderness")
	var menu=game.pet_hunt_menu
	menu.open_menu()
	check(menu.preset.selected==3 and menu.total.value==8 and menu.min_offsets()==[2,2,2,2],"default is full four-stat +2 quality")
	check(menu.rate.value==3000,"default requested rate is 3000 groups per second")
	check(not menu.start_button.disabled and game.paused_input,"modal pauses walking and enables local hunt")
	check(menu.species.item_count==3 and menu.species.is_item_disabled(2),"unavailable original pet art is explicit")
	if "--visual-review" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("/tmp/pet-hunt-menu.png")
	var before: Dictionary=game.session.snapshot().duplicate(true)
	game.encounter_rng.seed=1234
	menu.start_hunt()
	menu.scan_once()
	check(game.session.snapshot()==before,"skipping a troop grants nothing and starts no battle")
	menu.close_menu()
	check(not menu.running and not game.paused_input and menu.total.editable,"closing cancels and unlocks settings")
	menu.open_menu()
	menu.start_hunt()
	for i in range(20000):
		if not menu.running:break
		menu.scan_once()
	check(not menu.last_hit.is_empty(),"real source rolls find a matching newborn")
	check(game.battle_view.visible and not menu.visible,"match enters ordinary battle")
	if not menu.last_hit.is_empty() and game.battle_view.visible:
		var index: int=menu.last_hit.index
		var actor: Dictionary=menu.last_hit.actor
		var state: Dictionary=game.battle_session.snapshot()
		check(state.enemies[index].growth_weights==actor.growth_weights and state.enemies[index].base_stats==actor.base_stats,"exact individual survives battle handoff without reroll")
		check(state.enemies[index].name==actor.name,"highlight does not mutate pet name")
		check(game.battle_view.actor_labels[game.battle_view.enemy_actor(index)].text.begins_with("★"),"matched enemy is visibly marked")
		check(menu.last_hit.quality.total_offset==8 and actor.level==1,"found individual meets requested filters")
	check(game.session.snapshot().pets==before.pets,"helper does not capture automatically")
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
	game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("PET HUNT UI: %d failures"%failures)
	quit(1 if failures else 0)
