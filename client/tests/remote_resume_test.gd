extends SceneTree
## A page reload while automation runs on the backend: the new client starts
## where the character is, does not report that as travel (which would stop
## the hunt), and reopens the hunt window.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const MAP := 100
const CELL := Vector2i(637,493)
const Wait = preload("res://tests/support/wait.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func until(condition: Callable, seconds: float = Wait.DEADLINE) -> bool:
	return await Wait.until(self,condition,seconds)

func connect_client(port: int):
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	root.add_child(game)
	check(await until(func():return not game.data.is_empty() and game.link.online) and await Wait.settle(self,game),"a client connects and its startup reaches the backend")
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
	var port := 0 # any free port; the server reports the one it got
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	port = server.port

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
	check(await until(func():return backend.automation.hunt_rolls>rolls) and backend.automation.hunt_running,"the hunt keeps searching with no client connected")

	var second = await connect_client(port)
	check(not second.data.is_empty(),"a reloaded page connects")
	await until(func():return second.pet_hunt_menu.visible and second.pet_hunt_menu.running)
	check(backend.automation.hunt_running,"reconnecting does not stop the hunt")
	check(int(second.data.map_id)==MAP and second.cell==CELL,"the reloaded page starts where the character is")
	check(second.pet_hunt_menu.visible and second.pet_hunt_menu.running,"the hunt window reopens showing the running hunt")

	# Another device joins without opening the hunt window: it shares the run
	# and must not stop it (the backend guards position and battles itself).
	var third = await connect_client(port)
	# Joining mid-hunt reopens the window; a device that was already connected
	# when the hunt started never showed it. Hide it without closing (closing
	# the window is how a player stops the hunt).
	third.pet_hunt_menu.hide()
	check(not third.data.is_empty() and not third.pet_hunt_menu.visible,"a second device has the hunt window closed")
	var rolls_before: int = backend.automation.hunt_rolls
	# Anything the joining device sent (a stop would be one) has been handled.
	await Wait.settle(self,third)
	check(backend.automation.hunt_running and backend.automation.hunt_rolls>=rolls_before,"a device without the hunt window does not stop the shared hunt")
	await close_client(third)

	backend.handle({"type":"auto","name":"stop_hunt","reason":"test"})
	await close_client(second)
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame
	print("REMOTE RESUME: %d failures" % failures)
	quit(1 if failures else 0)
