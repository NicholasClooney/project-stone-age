extends SceneTree
## 真实 WebSocket 客户端：释放、换图、断线之后仍可安全绘制和点击。
const ProfileHub = preload("res://server/profile_hub.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
const Cleanup = preload("res://tests/lan_presence_test.gd")
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func click(players, holder) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = holder.get_global_transform_with_canvas().origin
	players._input(event)

func run() -> void:
	var dir := "user://remote-players-lifetime-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var server = ProfileHub.new(dir.path_join("accounts.json"))
	server.backups = false
	server.share_dir = ""
	root.add_child(server)
	check(server.start(),"隔离 hub 启动")
	var ws = WsServer.new(server,0,"127.0.0.1")
	root.add_child(ws)
	check(ws.start()==OK,"随机端口 WebSocket 启动")
	server.handle(900001,{"type":"create_profile","name":"Alice","pin":"1111"})
	server.handle(900002,{"type":"create_profile","name":"Bob","pin":"2222"})
	server.disconnect_connection(900002)
	server.handle(900001,{"type":"party_switch","on":true})
	var script = load("res://scripts/game.gd")
	script.server_url_override = "ws://127.0.0.1:%d" % ws.port
	var game = load("res://scenes/main.tscn").instantiate()
	script.server_url_override = ""
	game.profile_persistence = false
	root.add_child(game)
	check(await Wait.until(self,func():return is_instance_valid(game.login_screen) and game.login_screen.visible),"客户端出现登录界面")
	game.login_screen.find_child("Profile_Bob",true,false).pressed.emit()
	game.login_screen.pin.text = "2222"
	game.login_screen.login_button.pressed.emit()
	check(await Wait.until(self,func():return not game.data.is_empty() and game.link.online),"Bob 通过真实连接登录")
	await Wait.settle(self,game)
	var players = game.remote_players
	server.handle(900001,{"type":"report_position","map_id":int(game.data.map_id),"cell":[game.cell.x+1,game.cell.y],"client":"alice"})
	server.presence_tick(true)
	check(await Wait.until(self,func():return is_instance_valid(players.nodes.get("alice"))),"真实 presence 创建 Alice 节点")
	var holder = players.nodes.get("alice")
	check(holder.get_node("Name").text=="Alice" and holder.get_node("Actor")!=null,"正常人物和名字保留")
	check(players.player_at(holder.position)=="alice","正常人物可以命中")
	click(players,holder)
	check(players._pinned=="alice" and players.card.visible,"点击显示人物卡片")
	# 复现地图释放到下一次绘制之间的窗口；字典仍保存已经释放的对象。
	var point: Vector2 = holder.position
	holder.free()
	check(players.player_at(point)=="","释放后、重绘前点击不命中")
	players._place_card()
	players._draw_player(players.model.players.alice)
	holder = players.nodes.get("alice")
	check(is_instance_valid(holder) and holder.get_parent()==game.actors,"释放后的下一次绘制重建人物")
	check(players.player_at(holder.position)=="alice" and players._pinned=="alice","重建后仍能命中并保留点击选择")
	holder.queue_free()
	check(players.player_at(holder.position)=="","等待释放的节点不能再命中")
	players._draw_player(players.model.players.alice)
	check(is_instance_valid(players.nodes.get("alice")) and not players.nodes.alice.is_queued_for_deletion(),"等待释放时同样重建")
	# 真实组队换图路径同时替换 actors 与远端人物。
	var ahead: Vector2i = game.cell+game.SCREEN_DIRECTIONS[(int(game.player.facing)+4)%8]
	server.handle(900001,{"type":"report_position","map_id":int(game.data.map_id),"cell":[ahead.x,ahead.y],"client":"alice"})
	server.presence_tick(true)
	check(await Wait.until(self,func():return players.model.players.has("alice") and players.model.players.alice.cell==ahead),"组队前客户端收到队长新位置")
	game.classic_hud.find_child("PartyButton",true,false).pressed.emit()
	check(await Wait.until(self,func():return game.party_panel.is_member()),"Bob 加入 Alice 队伍")
	server.handle(900001,{"type":"report_position","map_id":1002,"cell":[16,15],"map_changed":true,"client":"alice"})
	check(await Wait.until(self,func():return int(game.data.map_id)==1002 and not game.area_transition_busy),"队长带客户端切换地图")
	await Wait.settle(self,game)
	server.presence_tick(true)
	check(await Wait.until(self,func():return is_instance_valid(players.nodes.get("alice")) and players.nodes.alice.get_parent()==game.actors),"换图后人物挂在新地图 actors")
	holder = players.nodes.get("alice")
	click(players,holder)
	check(players.player_at(holder.position)=="alice" and players.card.visible,"换图后绘制与点击正常")
	server.disconnect_connection(900001)
	server.presence_tick(true)
	check(await Wait.until(self,func():return not players.nodes.has("alice") and not players.model.players.has("alice")),"远端断线移除人物及模型")
	players._process(0.01)
	check(players.player_at(point)=="" and not players.card.visible,"断线后点击不命中且卡片隐藏")
	# UI 可独立销毁；重建卡片与销毁 world 后的迟到回调都不得访问 freed 实例。
	server.handle(900001,{"type":"login","name":"alice","pin":"1111"})
	server.presence_tick(true)
	check(await Wait.until(self,func():return is_instance_valid(players.nodes.get("alice"))),"重连恢复人物")
	players.card.free()
	click(players,players.nodes.alice)
	check(is_instance_valid(players.card) and players.card.visible,"UI 释放后点击重建卡片")
	game.remove_child(players)
	game.free()
	players._process(0.01)
	players._input(InputEventMouseButton.new())
	players.on_event({"type":"chat","mine":true,"text":"迟到回调"})
	players.reset()
	check(players.nodes.is_empty() and players.model.players.is_empty(),"world 释放后回调安全清理")
	players.free()
	ws.stop()
	ws.free()
	server.shut_down()
	server.queue_free()
	await process_frame
	Cleanup.remove_tree(dir)
	print("REMOTE PLAYERS LIFETIME: %d failures" % failures)
	quit(1 if failures else 0)
