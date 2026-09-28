extends SceneTree
## A page reload while automation runs on the backend: the new client starts
## where the character is, does not report that as travel (which would stop
## the hunt), and reopens the hunt window.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const MAP := 100
const CELL := Vector2i(637,493)
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
	root.add_child(game)
	await until(func():return not game.data.is_empty() and game.link.online)
	return game

func close_client(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func run() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	backend.handle({"type":"grant_starter_pets"})
	var port := 20000+randi()%20000
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")

	var first = await connect_client(port)
	check(not first.data.is_empty(),"first client connects")
	first.random_encounters = false
	first.load_area_id(MAP,CELL)
	check(await until(func():return backend.automation.position_map==MAP and backend.automation.position_cell==CELL),"first client travels to the hunting ground")
	first.pet_hunt_menu.open_menu()
	var filter: Dictionary = first.pet_hunt_menu.build_filter()
	check(not filter.is_empty(),"the hunt window builds a filter")
	# Slow, so the hunt is still searching when the page comes back.
	filter.rate = 1
	var started: Dictionary = backend.handle({"type":"auto_start","kind":"hunt","filter":filter,"map_id":MAP,"cell":[CELL.x,CELL.y]})
	check(bool(started.ok) and backend.automation.hunt_running,"a hunt runs on the backend")

	await close_client(first)
	check(await until(func():return server.clients().is_empty()),"the page is closed")
	var rolls: int = backend.automation.hunt_rolls
	check(await until(func():return backend.automation.hunt_rolls>rolls,5.0) and backend.automation.hunt_running,"the hunt keeps searching with no client connected")

	var second = await connect_client(port)
	check(not second.data.is_empty(),"a reloaded page connects")
	for i in range(30):await physics_frame
	check(backend.automation.hunt_running,"reconnecting does not stop the hunt")
	check(int(second.data.map_id)==MAP and second.cell==CELL,"the reloaded page starts where the character is")
	check(second.pet_hunt_menu.visible and second.pet_hunt_menu.running,"the hunt window reopens showing the running hunt")

	backend.handle({"type":"auto","name":"stop_hunt","reason":"test"})
	await close_client(second)
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame
	print("REMOTE RESUME: %d failures" % failures)
	quit(1 if failures else 0)
