extends SceneTree
## A remote client minimizes a running 自动抓极品 over a real localhost
## WebSocket: the hunt keeps searching on the backend while the player stores
## and releases pets in the warehouse, the open menu follows updates pushed by
## the backend, and a reloaded page comes back to the bar.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const MAP := 100
const CELL := Vector2i(637,493)
const PREFS := "user://remote-minimize-test-viewer.cfg"
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func until(condition: Callable, seconds: float = 10.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():return true
		await physics_frame
	return bool(condition.call())

func connect_client(port: int):
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = PREFS
	root.add_child(game)
	await until(func():return not game.data.is_empty() and game.link.online)
	return game

func close_client(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func stored(backend, pet_id: String) -> bool:
	return backend.session.snapshot().get("pet_storage",[]).any(func(pet):return str(pet.pet_id)==pet_id)

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var backend = Backend.new()
	root.add_child(backend)
	backend.handle({"type":"grant_starter_pets"})
	var port := 20000+randi()%20000
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")

	var game = await connect_client(port)
	check(not game.data.is_empty() and not game.link.is_local(),"remote client connects")
	game.random_encounters = false
	game.load_area_id(MAP,CELL)
	check(await until(func():return backend.automation.position_map==MAP and backend.automation.position_cell==CELL),"client travels to the hunting ground")

	var hunt = game.pet_hunt_menu
	hunt.open_menu()
	hunt.auto_capture.button_pressed = false
	hunt.train_after_capture.button_pressed = false
	# Slow, so the hunt is still searching throughout.
	hunt.rate.value = 2
	hunt.start_hunt()
	check(await until(func():return hunt.running and not hunt.minimize_button.disabled),"the hunt window starts a backend hunt")
	hunt.minimize()
	check(hunt.minimized and not hunt.visible and hunt.chip.visible and game.paused_input,"the hunt window collapses to its bar and holds the character")

	game.show_adventure_menu("pets")
	var menu = game.adventure_menu
	check(menu.visible,"the pet menu opens beside the minimized hunt")
	var profile: Dictionary = game.session.snapshot()
	var pet_id := ""
	for i in range(profile.pets.size()):
		if i!=int(profile.active_pet) and i!=int(profile.get("ride_pet",-1)):pet_id = str(profile.pets[i].pet_id)
	check(not pet_id.is_empty(),"fixture has a spare carried pet")
	menu.pet_storage_open = true;menu.pet_storage_target_id = pet_id;menu.rebuild()
	menu.panel.get_node("PetStoragePanel/StoreSelectedPet").pressed.emit()
	check(await until(func():return stored(backend,pet_id)),"storing a pet reaches the backend")
	check(await until(func():return menu.visible and not menu.panel.find_children("StorageRow_"+pet_id,"",true,false).is_empty()),"the open warehouse shows the stored pet once the backend confirms it")

	var drawn: int = menu.panel.get_instance_id()
	var gold := int(backend.session._profile.player.gold)
	backend.session._profile.player.gold = gold+7
	backend.publish()
	check(await until(func():return int(game.session.snapshot().player.gold)==gold+7 and menu.panel.get_instance_id()!=drawn),"a backend update redraws the open menu")

	game.release_pets([pet_id])
	check(await until(func():return not stored(backend,pet_id)),"releasing the stored pet reaches the backend")
	check(await until(func():return menu.panel.find_children("StorageRow_"+pet_id,"",true,false).is_empty()),"the open warehouse drops the released pet")

	var rolls: int = backend.automation.hunt_rolls
	check(await until(func():return backend.automation.hunt_rolls>rolls,5.0) and backend.automation.hunt_running,"the hunt keeps searching through the warehouse work")
	check(await until(func():return hunt.chip.detail.text.begins_with("遇敌 %d 组" % hunt.rolls) and hunt.rolls>0),"the bar shows the backend's encounter count")
	game.close_adventure_menu()
	for i in range(10):await physics_frame
	check(backend.automation.hunt_running and hunt.minimized and game.paused_input,"closing the menu leaves the hunt minimized and running")

	await close_client(game)
	check(await until(func():return server.clients().is_empty()),"the page is closed")
	var second = await connect_client(port)
	for i in range(30):await physics_frame
	var again = second.pet_hunt_menu
	check(backend.automation.hunt_running,"reloading does not stop the hunt")
	check(again.minimized and not again.visible and is_instance_valid(again.chip) and again.chip.visible and second.paused_input,"the reloaded page comes back to the bar this device chose")
	again.open_menu()
	check(again.visible and not again.minimized and again.running and not again.stop_button.disabled,"展开 on the reloaded page shows the running hunt")
	check(second.viewer_pref("hunt_minimized")==false,"restoring is remembered for the next reload")

	again.close_menu()
	check(await until(func():return not backend.automation.hunt_running),"closing the full window still stops the hunt")
	await close_client(second)
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("REMOTE MINIMIZE: %d failures" % failures)
	quit(1 if failures else 0)
