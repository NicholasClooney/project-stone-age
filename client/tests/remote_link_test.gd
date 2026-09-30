extends SceneTree
## A game client playing against a backend over a real localhost WebSocket:
## handshake, battles, profile commands, automation that keeps running while
## the client is disconnected, reconnection with a summary, and several
## devices driving one session.
const Backend = preload("res://server/backend.gd")
const WsServer = preload("res://server/ws_server.gd")
const WsLink = preload("res://network/ws_link.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

## Waits up to seconds for condition; the link and server poll every frame.
func until(condition: Callable, seconds: float = Wait.DEADLINE) -> bool:
	return await Wait.until(self,condition,seconds)

func run() -> void:
	var backend = Backend.new()
	root.add_child(backend)
	for command in [{"type":"gm_raise_level","index":-1,"target":10},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":100},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":100},{"type":"gm_heal"}]:
		backend.handle(command)
	var port := 0 # any free port; the server reports the one it got
	var server = WsServer.new(backend,port,"127.0.0.1")
	root.add_child(server)
	check(server.start()==OK,"backend listens on localhost")
	port = server.port
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
	for peer in server.clients():peer.close()
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

	# A second device joins: both stay connected, see the same updates and can act.
	backend.handle({"type":"auto_stop"})
	var other = WsLink.new("ws://127.0.0.1:%d" % port)
	var other_events: Array = []
	other.message.connect(func(event: Dictionary):other_events.append(event))
	other.connect_now()
	var poll_other := func():other.poll(1.0/60.0)
	check(await until(func():
		poll_other.call()
		return other.online),"a second device connects")
	for i in range(30):
		poll_other.call()
		await physics_frame
	check(game.link.online and server.clients().size()==2,"the first device stays connected")
	points = int(game.session.snapshot().player.stat_points)
	other.request({"type":"gm_grant_points","amount":2})
	check(await until(func():
		poll_other.call()
		return int(game.session.snapshot().player.stat_points)==points+2),"a command from one device updates the other")

	# Walking on one device moves the character on the other.
	var start_cell: Vector2i = game.cell
	var next_cell := Vector2i(-1,-1)
	for offset in game.SCREEN_DIRECTIONS:
		if game.can_step(start_cell,start_cell+offset):next_cell = start_cell+offset;break
	check(next_cell.x>=0,"the test finds a walkable neighbour")
	var steps_before: int = game.field_steps
	other.request({"type":"report_position","map_id":int(game.data.map_id),"cell":[next_cell.x,next_cell.y],"client":"other"})
	check(await until(func():
		poll_other.call()
		return game.cell==next_cell and not game.moving),"another device's step is walked here")
	check(game.field_steps==steps_before,"a mirrored step does not roll encounters again")
	var reported := other_events.filter(func(event):return str(event.type)=="position")
	check(reported.size()==1 and reported[0].client=="other","the follower does not echo the position back")
	var far_cell := Vector2i(-1,-1)
	for y in range(start_cell.y-12,start_cell.y+12):
		for x in range(start_cell.x-12,start_cell.x+12):
			if far_cell.x<0 and maxi(absi(x-next_cell.x),absi(y-next_cell.y))>3 and game.is_walkable(Vector2i(x,y)):far_cell = Vector2i(x,y)
	other.request({"type":"report_position","map_id":int(game.data.map_id),"cell":[far_cell.x,far_cell.y],"client":"other"})
	check(await until(func():
		poll_other.call()
		return game.cell==far_cell),"a distant position is jumped to")

	# Two devices answering the same battle turn: the first wins, the second is dropped quietly.
	var opened: Dictionary = backend.handle({"type":"begin_battle","enemy_count":1})
	check(bool(opened.ok),"a battle opens for both devices")
	var live: Dictionary = backend.battle.snapshot()
	var first: Dictionary = backend.handle({"type":"battle_command","action":"defend","battle_id":live.battle_id,"turn":live.turn})
	var second: Dictionary = backend.handle({"type":"battle_command","action":"defend","battle_id":live.battle_id,"turn":live.turn})
	check(bool(first.ok) and not bool(second.ok) and bool(second.get("stale",false)),"a command for an already resolved turn is dropped")
	check(bool(backend.handle({"type":"begin_battle"}).get("stale",false)),"starting a battle another device already started is stale")
	await until(func():return game.battle_view.visible)
	game.message.text = ""
	game.battle_session.submit_action("defend")
	var stale_turn: Dictionary = backend.battle.snapshot()
	other.request({"type":"battle_command","action":"defend","battle_id":stale_turn.battle_id,"turn":int(stale_turn.turn)-1})
	for i in range(30):
		poll_other.call()
		await physics_frame
	check(not game.message.text.contains("服务器拒绝"),"a lost race shows no error")
	other.close()
	backend.handle({"type":"auto_stop"})
	server.stop()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	backend.queue_free();server.queue_free()
	await process_frame
	print("REMOTE LINK: %d failures" % failures)
	quit(1 if failures else 0)
