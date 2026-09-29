extends SceneTree
## 本机极速模式 线程数: a setting of the server's computer (server_settings.gd),
## not the character's. It is validated and saved by the backend, published in
## the automation status, changed from any device's 自动抓极品 window, handed
## to the helper, and applied to a running hunt at once without losing rolls.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const ServerSettings = preload("res://server/server_settings.gd")
const CONFIG := "user://fast-hunt-threads-test.cfg"
const MAP := 300
const CELL := [509,93]
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

func prefs(tag: String) -> String:
	return "user://fast-hunt-threads-test-%s.cfg" % tag

func helper_threads(backend) -> int:
	var path: String = backend.automation.fast_hunt.input_path
	if path.is_empty() or not FileAccess.file_exists(path):return -1
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("threads "):return int(line.split(" ")[1])
	return -1

func rules() -> void:
	var cores := ServerSettings.cores()
	check(cores==maxi(1,OS.get_processor_count()),"the core count is the server's (%d)" % cores)
	check(ServerSettings.valid_threads(0) and ServerSettings.valid_threads(1) and ServerSettings.valid_threads(cores) and ServerSettings.valid_threads(2.0),"0 (auto), 1 to the core count and whole JSON numbers are accepted")
	check(not ServerSettings.valid_threads(-1) and not ServerSettings.valid_threads(cores+1) and not ServerSettings.valid_threads(1.5) and not ServerSettings.valid_threads("3") and not ServerSettings.valid_threads(null),"negative, too many, fractions, text and null are refused")
	check(ServerSettings.fast_hunt_threads()==0,"without a saved value it is automatic")
	check(ServerSettings.set_fast_hunt_threads(3).is_empty() and ServerSettings.fast_hunt_threads()==3,"a value is saved in the server's own file")
	check(not ServerSettings.set_fast_hunt_threads(cores+5).is_empty() and ServerSettings.fast_hunt_threads()==3,"a refused value leaves the saved one")
	FastHunt.threads = 0
	check(FastHunt.effective_threads(3)==3 and FastHunt.effective_threads(0)==0,"the helper gets the setting (0 lets it pick all cores but one)")
	FastHunt.threads = 2
	check(FastHunt.effective_threads(0)==2 and FastHunt.effective_threads(5)==2 and FastHunt.effective_threads(1)==1,"a test cap still bounds it")

func backend_commands() -> void:
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	backend.automation.client_attached = false
	check(backend.automation.fast_threads==3,"a new backend loads the saved 线程数")
	var hunt: Dictionary = backend.automation.status().hunt
	check(int(hunt.threads)==3 and int(hunt.threads_used)==3 and int(hunt.cores)==ServerSettings.cores(),"the status publishes 线程数, threads in use and the core count")
	check(not backend.handle({"type":"set_fast_hunt_threads"}).ok and not backend.handle({"type":"set_fast_hunt_threads","threads":-2}).ok,"a missing or invalid value is rejected")
	check(backend.handle({"type":"set_fast_hunt_threads","threads":0}).ok and int(backend.automation.status().hunt.threads_used)==(ServerSettings.cores()-1 if ServerSettings.cores() > 2 else 1),"automatic uses all cores but one")
	check(ServerSettings.fast_hunt_threads()==0,"the change is saved on the server")
	check(not backend.session.snapshot().has("fast_hunt_threads") and not str(backend.session.snapshot().get("automation_settings",{})).contains("threads"),"nothing is stored with the character")

	# A running fast hunt takes the new value at once and keeps its rolls.
	backend.handle({"type":"grant_starter_pets"})
	for command in [{"type":"gm_raise_level","index":-1,"target":20},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":200},{"type":"gm_heal"}]:
		backend.handle(command)
	var never := {"mode":"any","stop_after":1,"conditions":{"sum":{"enabled":true,"value":700,"strict":false,"keep":0}}}
	backend.handle({"type":"set_fast_hunt_threads","threads":1})
	var reply: Dictionary = backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL,"stat_filters":{"92":never},
		"filter":{"template":92,"level_one":true,"total":8,"offsets":[2,2,2,2],"auto_capture":false,"limit":0,"fast":true,"showcase":false},"settings":{"capture_hp":100}})
	check(reply.ok,"a fast find-pet cycle starts %s" % reply)
	var ticked := func(condition: Callable, seconds: float) -> bool:
		var deadline := Time.get_ticks_msec()+int(seconds*1000)
		while Time.get_ticks_msec() < deadline:
			backend._process(0.016)
			if condition.call():return true
			await process_frame
		return false
	check(await ticked.call(func():return backend.automation.fast_hunt.running() and helper_threads(backend)==1,10.0),"the helper is started with 1 thread")
	check(await ticked.call(func():return backend.automation.hunt_rolls > 0,10.0),"the helper reports rolls")
	var first_pid: int = backend.automation.fast_hunt.pid
	var rolls_before: int = backend.automation.hunt_rolls
	check(backend.handle({"type":"set_fast_hunt_threads","threads":2}).ok,"线程数 changes during the hunt")
	check(await ticked.call(func():return backend.automation.fast_hunt.running() and backend.automation.fast_hunt.pid!=first_pid and helper_threads(backend)==2,10.0),"the helper restarts at once with 2 threads")
	check(backend.automation.hunt_running and backend.automation.hunt_rolls >= rolls_before,"the hunt goes on from the rolls already done (%d, then %d)" % [rolls_before,backend.automation.hunt_rolls])
	backend.handle({"type":"auto_stop"})
	backend.automation.fast_hunt.stop()
	backend.queue_free()
	await process_frame

func connect_client(port: int, tag: String):
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	game.viewer_prefs_path = prefs(tag)
	root.add_child(game)
	await until(func():return not game.data.is_empty() and game.link.online)
	game.random_encounters = false
	return game

func close_client(game) -> void:
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.link.close()
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame

func remote_devices() -> void:
	ServerSettings.set_fast_hunt_threads(0)
	var backend = Backend.new()
	root.add_child(backend)
	backend.handle({"type":"grant_starter_pets"})
	var port := 20000+randi()%20000
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	var a = await connect_client(port,"a")
	var b = await connect_client(port,"b")
	a.load_area_id(MAP,Vector2i(CELL[0],CELL[1]))
	check(await until(func():return int(b.data.map_id)==MAP),"both devices stand on the hunting ground")
	for i in range(10):await physics_frame
	var menu_a = a.pet_hunt_menu
	var menu_b = b.pet_hunt_menu
	menu_a.open_menu();menu_b.open_menu()
	check(await until(func():return menu_a.thread_count.visible and menu_b.thread_count.visible and int(menu_b.thread_count.max_value)==ServerSettings.cores()),"both windows show 线程数 with the server's core count as the maximum")
	check(menu_a.cores_label.text=="本机%d核" % ServerSettings.cores() and int(menu_b.thread_count.value)==0,"本机 N 核 is shown and the value starts at the server's (automatic)")
	menu_a.thread_count.value = 2
	check(await until(func():return backend.automation.fast_threads==2 and ServerSettings.fast_hunt_threads()==2),"device A's change reaches the server")
	check(await until(func():return int(menu_b.thread_count.value)==2),"device B's open window shows it")
	var refused: Array = []
	a.link.request({"type":"set_fast_hunt_threads","threads":ServerSettings.cores()+1},func(reply):refused.append(reply))
	check(await until(func():return not refused.is_empty()) and not refused[0].ok and str(refused[0].reason).contains("线程数"),"a remote device's invalid value is rejected with the reason")
	check(backend.automation.fast_threads==2,"and the setting is unchanged")
	menu_a.close_menu();menu_b.close_menu()
	await close_client(a);await close_client(b)
	server.stop()
	backend.queue_free();server.queue_free()
	await process_frame

func run() -> void:
	ServerSettings.path_override = CONFIG
	FastHunt.threads = 2
	for path in [CONFIG,prefs("a"),prefs("b")]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	rules()
	check(FastHunt.available(),"the helper is built (%s)" % FastHunt.unavailable_reason())
	await backend_commands()
	await remote_devices()
	for path in [CONFIG,prefs("a"),prefs("b")]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	ServerSettings.path_override = ""
	print("FAST HUNT THREADS: %d failures" % failures)
	quit(1 if failures else 0)
