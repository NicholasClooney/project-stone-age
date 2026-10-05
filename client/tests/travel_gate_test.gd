extends SceneTree
const Game = preload("res://server/game_session.gd")
const Wait = preload("res://tests/support/wait.gd")
const Travel = preload("res://scripts/world_travel.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if value:print("PASS: "+message)
	else:
		failures += 1
		push_error("FAIL: "+message)
func _initialize() -> void:
	call_deferred("run")

func click(button: Control) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
		root.push_input(event,true)
	await process_frame

func run() -> void:
	var game = Game.new()
	check(not game.has_travel_pass(),"new player has no undersea permit")
	check(not game.buy_travel_pass() and game.snapshot().player.gold==20,"legacy internal developer purchase requires200gold without partialcharge")
	game._profile.player.gold = 250
	check(game.buy_travel_pass() and game.snapshot().player.gold==50,"legacy internal developer purchase costs200 and grants compatibility flag")
	check(game.has_travel_pass() and game.has_travel_pass(),"legacy compatibility flag checks do not consume it")
	check(not game.buy_travel_pass() and game.snapshot().player.gold==50,"duplicate purchase does not charge")
	var path := "user://travel-permit-test.json"
	check(game.save_game(path),"permit saves")
	var loaded = Game.new()
	check(loaded.load_game(path) and loaded.has_travel_pass(),"permit survivesload")
	var old: Dictionary = game.snapshot()
	old.erase("travel_pass")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old))
	file.close()
	check(loaded.load_game(path) and not loaded.has_travel_pass(),"oldsave migrates withoutgrantingpermit")
	old.travel_pass = "true"
	check(not game._valid_profile(old),"invalidpermit rejected")
	var blocked = Game.new()
	blocked._profile.player.gold = 200
	blocked.start_battle_config()
	check(not blocked.buy_travel_pass(),"battle authority blocks purchase")
	var helper = Travel.new()
	helper.entries = [{"cell":[22,28]},{"cell":[22,32]}]
	check(helper.blocks(Vector2i(22,28)) and helper.blocks(Vector2i(22,32)) and not helper.blocks(Vector2i(21,28)),"guardcells blockwalking")
	helper.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
	var world = load("res://scenes/main.tscn").instantiate()
	world.profile_persistence = false
	root.add_child(world)
	await process_frame
	world.muted = true
	check(world.load_area_id(10202,Vector2i(21,28)),"undersea gate map loads")
	await process_frame
	var gate = world.world_travel
	if gate and gate.entries.size()>=2:
		gate.selected = 0
		gate._open()
		check(gate.overlay.visible and not gate.choice.visible,"guard dialogue refuses missingpermit")
		world.show_adventure_menu("status")
		world.classic_hud.toggle_map()
		check(not world.adventure_menu.visible and not world.classic_hud.map_panel.visible,"original bottom menus cannot bypass travel dialogue")
		gate._close()
		# Explicit already-owned legacy compatibility fixture, NOT a public purchase.
		world.backend.session._profile.travel_pass = true
		world.backend.publish()
		check(world.session.has_travel_pass(),"authoritative legacy compatibility fixture reaches client")
		gate._open()
		check(gate.choice.visible,"permit enables crossingconfirmation")
		await click(gate.choice)
		check(await Wait.until(self,func():return world.cell==Vector2i(21,33) and not world.area_transition_busy),"northguard confirmation crosses originaldestination")
		check(world.session.has_travel_pass(),"firstcrossing retainspermit")
		gate = world.world_travel
		gate.approach(1)
		check(await Wait.until(self,func():return not world.moving and world.path.is_empty() and gate.pending==-1 and gate.selected==1 and gate.overlay.visible and gate.choice.visible),"walking up to return guard opens original dialogue")
		await click(gate.choice)
		check(await Wait.until(self,func():return world.cell==Vector2i(21,27) and not world.area_transition_busy) and world.session.has_travel_pass(),"returncrossing uses samepermit")
	else:check(false,"both imported guards available")
	world.music.stop()
	world.effect.stop()
	world.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("TRAVEL GATE: %d failures" % failures)
	quit(1 if failures else 0)
