extends SceneTree
## A game client playing against a backend over a real localhost WebSocket:
## handshake, battles, profile commands, automation that keeps running while
## the client is disconnected, reconnection with a summary, and takeover.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const WsLink = preload("res://network/ws_link.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## Waits up to seconds for condition; the link and server poll every frame.
func until(condition: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < deadline:
		if condition.call():return true
		await physics_frame
	return bool(condition.call())

func run() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	for command in [{"type":"gm_raise_level","index":-1,"target":10},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":100},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":100},{"type":"gm_heal"}]:
		backend.handle(command)
	var port := 20000+randi()%20000
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = "ws://127.0.0.1:%d" % port
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	root.add_child(game)
	check(await until(func():return not game.data.is_empty(),10.0),"remote client connects and builds the world from the backend snapshot")
	check(not game.link.is_local() and game.backend==null,"client holds no authority of its own")
	check(int(game.session.snapshot().player.level)==int(backend.session.snapshot().player.level),"profile arrives from the backend")

	game.load_area_id(100,Vector2i(637,493))
	check(await until(func():return backend.automation.position_map==100 and backend.automation.position_cell==Vector2i(637,493)),"map changes are reported to the backend")

	var points: int = int(game.session.snapshot().player.stat_points)
	check(game.session.gm_grant_points(3),"profile command is sent")
	check(await until(func():return int(game.session.snapshot().player.stat_points)==points+3),"accepted command updates the client through events")

	# Open panels redraw when the backend's update arrives, not when a command is sent.
	var gm = game.dev_gm_menu
	gm.open_menu()
	backend.session._profile.player.hp = 1
	backend.publish()
	check(await until(func():return gm.summary.text.contains("体力 1 /")),"an open GM panel shows data pushed by the backend")
	var max_hp: int = int(backend.session._profile.player.max_hp)
	gm._apply(game.session.gm_heal(-2))
	check(await until(func():return gm.summary.text.contains("体力 %d / %d" % [max_hp,max_hp])),"restoring health over the network updates the open GM panel")
	gm.close_menu()

	check(game.begin_battle(false,1),"battle request is sent")
	check(await until(func():return game.battle_view.visible and backend.battle_open),"backend battle opens the client battle view")
	game.battle_action("developer_escape")
	check(await until(func():return not game.battle_session.snapshot().get("active",true)),"battle turn result arrives")
	for i in range(200):
		if not game.battle_view.is_animating():break
		game.battle_view._process(0.2)
	game.return_from_battle()
	check(await until(func():return not backend.battle_open and not game.battle_view.visible),"closing returns both sides to the map")

	# Automation runs on the backend and survives the client disconnecting.
	var helper = game.training_helper
	helper.open_menu();helper.compact.button_pressed=true;helper.battle_limit.value=3;helper.hp_floor.value=1;helper.speed.select(3);helper.preset.select(0)
	helper.start_training()
	check(await until(func():return bool(game.state.automation.get("running",false))),"automation starts on the backend")
	server._controller.close()
	check(await until(func():return not game.link.online and not backend.automation.client_attached),"client disconnect is noticed on both sides")
	check(game.link_blocked() and game._link_status.text.contains("断开连接"),"a lost connection covers the game with a notice")
	var cell_before: Vector2i = game.cell
	var press := InputEventAction.new();press.action = "east";press.pressed = true
	Input.parse_input_event(press)
	for i in range(30):await physics_frame
	press.pressed = false;Input.parse_input_event(press)
	check(game.cell==cell_before and game.held.is_empty(),"the world does not move while offline")
	var before: int = backend.automation.battles
	check(await until(func():return backend.automation.battles>before or not backend.automation.running,20.0),"backend keeps fighting while no client is connected")
	check(await until(func():return game.link.online,15.0),"client reconnects on its own")
	check(await until(func():return int(game.state.automation.get("battles",-1))==backend.automation.battles),"reconnect resyncs automation progress")
	check(game.message.text.begins_with("已重新连接"),"reconnect shows an offline summary")
	check(not game.link_blocked(),"reconnecting removes the notice")

	# A server that stops answering without closing (killed host, Wi-Fi drop) is noticed too.
	game.link.silence_limit = 1.5
	server.process_mode = Node.PROCESS_MODE_DISABLED
	check(await until(func():return game.link_blocked(),6.0),"a silent server is detected by the heartbeat")
	server.process_mode = Node.PROCESS_MODE_INHERIT
	check(await until(func():return game.link.online and not game.link_blocked(),15.0),"the client recovers once the server answers again")
	game.link.silence_limit = game.link.SILENCE_LIMIT

	# A second device takes over; the first stops syncing.
	var other = WsLink.new("ws://127.0.0.1:%d" % port)
	other.connect_now()
	check(await until(func():
		other.poll(1.0/60.0)
		return other.online and game.link.superseded),"newest connection takes control and the old client is told")
	check(await until(func():return game.link_blocked() and game._take_over_button.visible),"the superseded window offers to continue here")
	game._take_over_button.pressed.emit()
	check(await until(func():
		other.poll(1.0/60.0)
		return game.link.online and not game.link_blocked() and other.superseded),"continuing here takes control back")
	other.close()
	backend.handle({"type":"auto_stop"})
	server.stop()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	backend.queue_free();server.queue_free()
	await process_frame
	print("REMOTE LINK: %d failures" % failures)
	quit(1 if failures else 0)
