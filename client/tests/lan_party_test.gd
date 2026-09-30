extends SceneTree
## LAN phase 3 (docs/development/lan-profiles.md): 组队 on the map. The
## party rules (server/party.gd: joining the player in front, the 组队
## switch, 5 at most, leaving, 踢出, disbanding), members following the leader
## in a line and across map changes, encounters for the leader only, the
## automation refused in a party, 队伍频道, the presence feed's party field,
## disconnects, and one real game client as a member.
##
## The functional core runs for real: the party rules, the hub, real backends
## taking report_position, field_step, battles and auto_start. Only the shell
## is faked: the clock, and connections as plain ids (as in profile_hub_test);
## the client part uses a real localhost WebSocket.
const Party = preload("res://server/party.gd")
const ProfileHub = preload("res://server/profile_hub.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
var failures := 0
var now := 10000
var dir := ""

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clock() -> int:
	return now

func seconds() -> float:
	return now/1000.0

static func remove_tree(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):return
	for sub in DirAccess.get_directories_at(folder):remove_tree(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)

func run() -> void:
	dir = "user://lan-party-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	rules()
	follow()
	await hub()
	await client()
	remove_tree(dir)
	print("LAN PARTY: %d failures" % failures)
	quit(1 if failures else 0)

func profile(id: String, cell: Vector2i, map_id := 1000, battle := false, auto := false) -> Dictionary:
	return {"id":id,"name":id.capitalize(),"level":5,"map":map_id,"cell":cell,"battle":battle,"auto":auto,"connections":[id]}

## Facing whose front cell is one step east (+x): DIRECTIONS[(f+4)%8]==(1,0).
const EAST := 5

## Joining, the switch, the limit, leaving, 踢出 and disbanding.
func rules() -> void:
	var party = Party.new()
	check(Party.front(Vector2i(10,10),EAST)==Vector2i(11,10) and Party.front(Vector2i(10,10),0)==Vector2i(9,11),"the cell in front follows the client's facing")
	var a := profile("a",Vector2i(11,10))
	var b := profile("b",Vector2i(10,10))
	var all := [a,b]
	check(party.accepts("a"),"the 组队 switch starts on")
	party.set_accept("a",false)
	var refused: Dictionary = party.join("b",EAST,all)
	check(not refused.ok and refused.reason.contains("组队开关"),"A's 组队 switch is off: B cannot join (%s)" % refused.reason)
	party.set_accept("a",true)
	check(not party.join("b",0,all).ok and party.join("b",0,all).reason.contains("面前没有"),"facing away from A, there is nobody in front")
	a.battle = true
	check(party.join("b",EAST,all).reason.contains("战斗"),"A fighting cannot be joined")
	a.battle = false
	a.auto = true
	check(party.join("b",EAST,all).reason.contains("自动"),"nor A running automation")
	a.auto = false
	b.auto = true
	check(party.join("b",EAST,all).reason.contains("停止"),"and B must stop its own automation first")
	b.auto = false
	var joined: Dictionary = party.join("b",EAST,all)
	check(joined.ok and joined.leader=="a" and joined.created and joined.members==["a","b"],"B joins A, who becomes the leader")
	check(party.is_leader("a") and party.is_member("b") and party.members("b")==["a","b"],"A leads, B is a member")
	check(not party.join("b",EAST,all).ok,"a member cannot join again")
	# C stands in front of B (a member): it joins B's leader, A, if A is within a cell.
	var c := profile("c",Vector2i(9,10))
	all.append(c)
	check(not party.join("c",EAST,all).ok,"C two cells from A cannot join through B")
	c.cell = Vector2i(10,11)
	b.cell = Vector2i(11,11)
	check(party.join("c",EAST,all).ok and party.members("a")==["a","b","c"],"C in front of B and next to A joins A's party")
	var d := profile("d",Vector2i(11,9))
	var e := profile("e",Vector2i(12,9))
	var f := profile("f",Vector2i(10,9))
	all.append_array([d,e,f])
	check(party.join("d",7,all).ok,"D joins (facing 7: the cell in front, (11,10), is A)")
	# E faces A diagonally: from (12,9) the step (-1,1) is facing 0.
	check(party.join("e",0,all).ok and party.members("a").size()==Party.MAX_MEMBERS,"E makes five")
	var full: Dictionary = party.join("f",6,all)
	check(Party.front(f.cell,6)==Vector2i(11,10) and not full.ok and full.reason.contains("已满"),"a sixth is refused: %s" % full.reason)
	# 踢出, leaving, disbanding.
	check(not party.kick("b","c").ok,"only the leader kicks")
	var kicked: Dictionary = party.kick("a","e")
	check(kicked.ok and kicked.left==["e"] and not party.in_party("e") and party.members("a").size()==4,"the leader kicks E")
	var left: Dictionary = party.leave("d")
	check(left.ok and not left.disbanded and left.members==["a","b","c"],"D leaves; the party goes on")
	var gone: Dictionary = party.leave("a")
	check(gone.ok and gone.disbanded and gone.left==["a","b","c"] and not party.in_party("b") and party.parties.is_empty(),"the leader leaving disbands the party")
	# The last member leaving ends the party too.
	check(party.join("b",EAST,[a,profile("b",Vector2i(10,10))]).ok,"B joins A again")
	var last: Dictionary = party.leave("b")
	check(last.disbanded and not party.in_party("a"),"when the last member leaves, A is no leader any more")
	# A disconnected player (no devices) cannot be joined.
	a.connections = []
	check(not party.join("b",EAST,[a,profile("b",Vector2i(10,10))]).ok,"a player with no device online cannot be joined")

## The line behind the leader, warps and map changes.
func follow() -> void:
	var party = Party.new()
	party.set_accept("a",true)
	var all := [profile("a",Vector2i(13,10)),profile("b",Vector2i(12,10)),profile("c",Vector2i(12,9))]
	party.join("b",EAST,all)
	all[2].cell = Vector2i(12,11)
	party.join("c",4,all)
	check(party.members("a")==["a","b","c"],"a party of three")
	var positions := {"b":[1000,Vector2i(12,10)],"c":[1000,Vector2i(12,11)]}
	var moves: Array = party.follow("a",1000,Vector2i(13,10),1000,Vector2i(14,10),positions)
	check(moves==[["b",1000,Vector2i(13,10),false],["c",1000,Vector2i(12,10),false]],"a step east: B takes A's old cell, C steps onto B's (%s)" % str(moves))
	for move in moves:positions[move[0]] = [move[1],move[2]]
	moves = party.follow("a",1000,Vector2i(14,10),1000,Vector2i(15,10),positions)
	for move in moves:positions[move[0]] = [move[1],move[2]]
	check(positions.b[1]==Vector2i(14,10) and positions.c[1]==Vector2i(13,10),"another step: they walk in a line behind A (%s)" % str(positions))
	check(party.follow("a",1000,Vector2i(15,10),1000,Vector2i(15,10),positions).is_empty(),"no step, no moves")
	check(party.follow("b",1000,Vector2i(14,10),1000,Vector2i(15,10),positions).is_empty(),"a member's own step moves nobody")
	moves = party.follow("a",1000,Vector2i(15,10),100,Vector2i(600,500),positions)
	check(moves==[["b",100,Vector2i(600,500),true],["c",100,Vector2i(600,500),true]],"a map change takes everyone to the leader's destination")
	for move in moves:positions[move[0]] = [move[1],move[2]]
	moves = party.follow("a",100,Vector2i(600,500),100,Vector2i(640,520),positions)
	check(moves.size()==2 and moves.all(func(move):return move[2]==Vector2i(640,520) and not move[3]),"a 瞬移 on the same map puts them on the leader's cell")
	for move in moves:positions[move[0]] = [move[1],move[2]]
	moves = party.follow("a",100,Vector2i(640,520),100,Vector2i(641,520),positions)
	for move in moves:positions[move[0]] = [move[1],move[2]]
	moves = party.follow("a",100,Vector2i(641,520),100,Vector2i(642,520),positions)
	for move in moves:positions[move[0]] = [move[1],move[2]]
	check(positions.b[1]==Vector2i(641,520) and positions.c[1]==Vector2i(640,520),"stacked after a warp, they spread out again as the leader walks (%s)" % str(positions))

class Wire extends RefCounted:
	var messages: Array = []
	func take(connection: int, message: Dictionary) -> void:
		messages.append([connection,message])
	func of(connection: int, type: String) -> Array:
		return messages.filter(func(item):return item[0]==connection and str(item[1].type)==type).map(func(item):return item[1])
	func last_party(connection: int) -> Dictionary:
		var views := of(connection,"party")
		return views[-1] if not views.is_empty() else {}
	func system(connection: int) -> Array:
		return of(connection,"chat").filter(func(event):return event.channel=="系统").map(func(event):return event.text)

func report(server, connection: int, map_id: int, cell: Vector2i, map_changed := false) -> Dictionary:
	return server.handle(connection,{"type":"report_position","map_id":map_id,"cell":[cell.x,cell.y],"map_changed":map_changed,"client":"c%d" % connection})

func where(server, id: String) -> Array:
	var automation = server.backends[id].automation
	return [automation.position_map,automation.position_cell]

## Through the hub: real backends, positions, encounters, battles, automation.
func hub() -> void:
	var server = ProfileHub.new(dir.path_join("accounts.json"),seconds)
	server.tick = false
	server.backups = false
	server.share_dir = ""
	server.presence_clock = clock
	root.add_child(server)
	check(server.start(),"a hub starts")
	var wire := Wire.new()
	server.outgoing.connect(wire.take)
	for info in [[1,"Alice","1111"],[2,"Bob","2222"],[3,"Cid","3333"],[4,"Dan","4444"]]:
		check(server.handle(info[0],{"type":"create_profile","name":info[1],"pin":info[2]}).ok,"%s logs in" % info[1])
	server.presence_tick(true)
	var views: Dictionary = wire.last_party(1)
	check(not views.is_empty() and views.me=="alice" and views.leader=="" and views.accept,"after a login the next tick tells a device its party view: no party, switch on")
	report(server,1,1000,Vector2i(81,90))
	report(server,2,1000,Vector2i(80,90))
	report(server,3,1000,Vector2i(81,91))
	report(server,4,2000,Vector2i(5,5))
	check(server.handle(1,{"type":"party_switch","on":false}).ok and not bool(wire.last_party(1).accept),"Alice switches 组队 off; her devices see it")
	var joined: Dictionary = server.handle(2,{"type":"party_join","facing":EAST,"seq":3})
	check(not joined.ok and joined.type=="rejected" and joined.seq==3 and str(joined.reason).contains("组队开关"),"Bob cannot join Alice while her 组队 is off")
	wire.messages.clear()
	check(server.handle(1,{"type":"party_switch","on":true}).ok and bool(wire.last_party(1).accept),"Alice switches 组队 on; her devices see it")
	joined = server.handle(2,{"type":"party_join","facing":EAST})
	check(joined.ok and joined.leader=="alice","Bob joins Alice, standing next to her and facing her")
	check(wire.system(2).has("加入团队！") and wire.system(1).has("Bob 加入团队！"),"both hear it, as the original's system lines")
	var bob_view: Dictionary = wire.last_party(2)
	check(bob_view.leader=="alice" and bob_view.members.map(func(m):return m.name)==["Alice","Bob"] and not bob_view.battle,"Bob's view: Alice leads, Alice and Bob")
	# Cid in front of Bob (a member), next to Alice: joins Alice.
	check(server.handle(3,{"type":"party_join","facing":2}).ok and server.party.members("alice")==["alice","bob","cid"],"Cid, facing Bob, joins through him into Alice's party")
	# Presence carries the party.
	now += 1000
	wire.messages.clear()
	server.presence_tick(true)
	var alice_sees: Array = wire.of(1,"presence")
	check(not alice_sees.is_empty() and alice_sees[-1].players.all(func(entry):return entry.pt=="alice"),"others see Bob and Cid in Alice's party (pt)")
	# The leader walks: members follow in a line; their devices are moved.
	wire.messages.clear()
	report(server,1,1000,Vector2i(82,90))
	check(where(server,"bob")==[1000,Vector2i(81,90)] and where(server,"cid")==[1000,Vector2i(80,90)],"Alice steps east; Bob takes her old cell, Cid takes Bob's (%s %s)" % [str(where(server,"bob")),str(where(server,"cid"))])
	var moved: Array = wire.of(2,"position")
	check(moved.size()==1 and moved[0].client=="party" and moved[0].cell==[81,90],"Bob's device is told to follow: %s" % str(moved))
	# A member's own walk is refused; the device is sent back.
	wire.messages.clear()
	var own: Dictionary = report(server,2,1000,Vector2i(70,70))
	check(own.ok and own.get("party",false) and where(server,"bob")==[1000,Vector2i(81,90)],"Bob's own report does not move him")
	check(wire.of(2,"position").size()==1 and wire.of(2,"position")[0].cell==[81,90],"his device is told where he is")
	# Encounters: the leader only.
	var step: Dictionary = server.handle(2,{"type":"field_step","map_id":100,"cell":[600,500],"encounter":true})
	check(step.ok and not step.battle and not step.hit,"a member's field step meets nothing")
	check(not server.handle(2,{"type":"wild_encounter","map_id":100,"cell":[600,500]}).ok and not server.backends.bob.battle_open,"a member cannot start a wild battle")
	# Automation: members start none; hunts are refused for the leader too (LAN phase 4c).
	var auto: Dictionary = server.handle(2,{"type":"auto_start","kind":"battle"})
	check(not auto.ok and str(auto.reason).contains("队员跟着队长走"),"a member cannot start 自动练级: %s" % str(auto.get("reason","")))
	check(not server.handle(1,{"type":"auto_start","kind":"hunt"}).ok and not server.backends.alice.automation.hunt_running,"nor can the leader start a hunt")
	check(not server.handle(4,{"type":"auto_start","kind":"nothing"}).reason.contains("组队中"),"Dan, alone, is not refused for a party")
	# The leader's encounter is the whole party's battle (LAN phase 4a; see
	# lan_party_battle_test). Only a member out of it sees 队长战斗中.
	wire.messages.clear()
	var fight: Dictionary = server.handle(1,{"type":"begin_battle"})
	check(fight.ok and server.backends.alice.battle_open and server.backends.bob.battle_open and server.backends.cid.battle_open,"Alice's encounter pulls Bob and Cid into one party battle")
	now += 1000
	server.presence_tick()
	check(not bool(wire.last_party(2).get("battle",false)),"Bob fights too, so his view shows no 队长战斗中")
	server.backends.alice.abandon_battle()
	for connection in [2,3]:server.handle(connection,{"type":"battle_close"})
	check(not server.backends.bob.battle_open and not server.backends.cid.battle_open and not server.party_battles.in_battle("bob"),"it ends for everyone; the members' devices close it")
	# A map change carries the members to the leader's destination.
	wire.messages.clear()
	report(server,1,100,Vector2i(600,500),true)
	check(where(server,"bob")==[100,Vector2i(600,500)] and where(server,"cid")==[100,Vector2i(600,500)],"Alice goes to another map; Bob and Cid arrive where she did")
	check(wire.of(3,"position").size()==1 and wire.of(3,"position")[0].map_id==100,"Cid's device loads that map")
	# 队伍频道 reaches the party anywhere; 一般 stays on the map.
	report(server,4,100,Vector2i(700,500))
	wire.messages.clear()
	var said: Dictionary = server.handle(3,{"type":"say","text":"跟上！","channel":"队伍"})
	var heard: Array = wire.messages.filter(func(item):return item[1].type=="chat").map(func(item):return item[0])
	check(said.ok and heard==[1,2,3] and wire.of(1,"chat")[0].channel=="队伍","队伍频道 reaches the three members only, not Dan on the same map")
	check(not server.handle(4,{"type":"say","text":"hi","channel":"队伍"}).ok,"Dan has no party to talk to")
	# 踢出 and leaving.
	wire.messages.clear()
	check(not server.handle(2,{"type":"party_kick","id":"cid"}).ok,"a member cannot kick")
	check(server.handle(1,{"type":"party_kick","id":"cid"}).ok and not server.party.in_party("cid"),"Alice kicks Cid")
	check(wire.system(3).has("被队长踢出队伍。") and wire.system(2).has("Cid 被踢出队伍。"),"Cid and Bob hear it")
	check(report(server,3,100,Vector2i(605,505)).get("party",false)==false and where(server,"cid")==[100,Vector2i(605,505)],"Cid walks on his own again")
	# The leader disconnects: the party disbands.
	wire.messages.clear()
	server.disconnect_connection(1)
	check(not server.party.in_party("bob") and server.party.parties.is_empty(),"Alice's last device drops: the party disbands")
	check(wire.system(2).has("团队已解散！") and wire.last_party(2).leader=="","Bob hears 团队已解散！ and his view has no party")
	# A member's disconnect: they leave.
	server.handle(1,{"type":"login","name":"alice","pin":"1111"})
	report(server,1,100,Vector2i(601,500))
	server.handle(1,{"type":"party_switch","on":true})
	check(server.party.accepts("alice"),"Alice's switch stayed on across her reconnect")
	report(server,2,100,Vector2i(600,500))
	check(server.handle(2,{"type":"party_join","facing":EAST}).ok,"Bob joins again")
	wire.messages.clear()
	server.disconnect_connection(2)
	check(not server.party.in_party("bob") and not server.party.in_party("alice"),"Bob drops; Alice is alone again, no party")
	check(wire.system(1).has("Bob 脱离团队！"),"Alice hears Bob left")
	# Leaving by hand and disbanding.
	server.handle(2,{"type":"login","name":"bob","pin":"2222"})
	report(server,2,100,Vector2i(600,500))
	report(server,3,100,Vector2i(600,501))
	server.handle(2,{"type":"party_join","facing":EAST})
	server.handle(3,{"type":"party_join","facing":4})
	check(server.party.members("alice")==["alice","bob","cid"],"a party of three again")
	check(server.handle(3,{"type":"party_leave"}).ok and server.party.members("alice")==["alice","bob"],"Cid leaves with 离开队伍")
	check(server.handle(1,{"type":"party_disband"}).ok and server.party.parties.is_empty(),"Alice disbands with 解散队伍")
	check(not server.handle(2,{"type":"party_disband"}).ok,"only a leader disbands")
	server.shut_down()
	server.queue_free()
	await process_frame

## A real game client as a member: the 加入队伍 button, the party list, the
## walking lock, following the leader and being pulled into its battle.
func client() -> void:
	var accounts := dir.path_join("client-accounts.json")
	var server = ProfileHub.new(accounts)
	server.backups = false
	server.share_dir = ""
	root.add_child(server)
	check(server.start(),"a hub for the client")
	var ws = WsServer.new(server,0,"127.0.0.1")
	root.add_child(ws)
	check(ws.start()==OK,"it listens")
	var url := "ws://127.0.0.1:%d" % ws.port
	# Alice (the admin, driven directly) and Bob's character.
	server.handle(900001,{"type":"create_profile","name":"Alice","pin":"1111"})
	server.handle(900002,{"type":"create_profile","name":"Bob","pin":"2222"})
	server.disconnect_connection(900002)
	server.handle(900001,{"type":"party_switch","on":true})
	var game_script = load("res://scripts/game.gd")
	game_script.server_url_override = url
	var game = load("res://scenes/main.tscn").instantiate()
	game_script.server_url_override = ""
	game.profile_persistence = false
	root.add_child(game)
	check(await Wait.until(self,func():return is_instance_valid(game.login_screen) and game.login_screen.visible),"Bob's game opens on the 登录 screen")
	game.login_screen.find_child("Profile_Bob",true,false).pressed.emit()
	game.login_screen.pin.text = "2222"
	game.login_screen.login_button.pressed.emit()
	check(await Wait.until(self,func():return not game.data.is_empty() and game.link.online),"Bob is in the world")
	await Wait.settle(self,game)
	check(is_instance_valid(game.party_panel) and game.party_panel.available() and not game.party_panel.in_party(),"the party panel knows Bob can party, and is in none")
	check(game.classic_hud.find_child("PartyButton",true,false)!=null and game.party_panel.button_caption()=="加入队伍。","the bar's 加入队伍 button says 加入队伍。")
	# 人物面部 over the network: an eye step then a mouth step, before the
	# server's reply comes back, keeps both.
	var chooser: Control = game.character_selection
	chooser.open_menu()
	await Wait.until(self,func():return chooser.visible)
	var before := int(server.backends.bob.session.snapshot().get("face",0))
	chooser.find_child("Face_眼睛_next",true,false).pressed.emit()
	chooser.find_child("Face_嘴巴_next",true,false).pressed.emit()
	var want := ((int(before/5)+1)%5)*5+(before%5+1)%5
	check(await Wait.until(self,func():return int(server.backends.bob.session.snapshot().get("face",0))==want),"a quick eye step then mouth step both reach the server (%d, want %d)" % [int(server.backends.bob.session.snapshot().get("face",0)),want])
	chooser.close_menu()
	# MENU opens 设置, whose 组队 switch starts on and reaches the server.
	game.classic_hud.find_child("GameSettingsButton",true,false).pressed.emit()
	var switch: CheckBox = game.settings_menu.find_child("SettingsPartySwitch",true,false)
	check(game.settings_menu.visible and switch!=null and switch.button_pressed,"MENU opens 设置 with 接受其他人加入队伍 on")
	switch.button_pressed = false
	check(await Wait.until(self,func():return not server.party.accepts("bob")),"unticking it turns Bob's 组队 switch off on the server")
	switch.button_pressed = true
	check(await Wait.until(self,func():return server.party.accepts("bob")),"and ticking it turns it back on")
	game.settings_menu.close_menu()
	# Alice stands right in front of Bob.
	var map_id := int(game.data.map_id)
	var ahead: Vector2i = game.cell+game.SCREEN_DIRECTIONS[(int(game.player.facing)+4)%8]
	report(server,900001,map_id,ahead)
	# 右键转向: a right click behind Bob turns him away, one on Alice back.
	var facing_before := int(game.player.facing)
	var standing: Vector2i = game.cell
	var behind: Vector2i = game.cell-(ahead-game.cell)*3
	game._input_events.turn_toward(game.project(Vector2(behind)))
	check(int(game.player.facing)==(facing_before+4)%8 and not game.moving and game.cell==standing,"a right click behind turns Bob around without walking")
	check(await Wait.until(self,func():return server.presence._facing.get("bob",-1)==(facing_before+4)%8),"and the server's presence has his new facing")
	game._input_events.turn_toward(game.project(Vector2(ahead)))
	check(int(game.player.facing)==facing_before,"a right click on Alice turns him back to her")
	game.classic_hud.find_child("PartyButton",true,false).pressed.emit()
	check(await Wait.until(self,func():return game.party_panel.is_member()),"pressing 加入队伍 joins Alice")
	check(await Wait.until(self,func():return game.party_panel.list.visible and game.party_panel.list.find_child("LeaveParty",true,false)!=null),"the party list shows, with 离开队伍")
	var hint: Control = game.adventure_hint
	check(game.party_panel.list.position.y>=game.helper_button.position.y+game.helper_button.size.y and (not hint.visible or game.party_panel.list.position.y>=hint.position.y+hint.size.y),"the party list sits below 游戏助手 and the Lv line, not over them")
	var free := Vector2i(-1,-1)
	for d in game.SCREEN_DIRECTIONS:
		if game.can_step(game.cell,game.cell+d):free = game.cell+d
	check(free.x>=0 and game.party_locked() and not game.request_step(free) and game.message.text==game.PARTY_LOCKED_TEXT,"Bob cannot step to a free cell on his own in the party")
	check(not game.load_area_id(1002,Vector2i(16,15)) and int(game.data.map_id)==map_id,"nor change the map")
	# Alice steps away: Bob follows onto her old cell.
	report(server,900001,map_id,ahead+(ahead-game.cell))
	check(await Wait.until(self,func():return game.cell==ahead and not game.moving),"Alice steps on; Bob's game walks after her (%s)" % str(game.cell))
	# Alice meets enemies: Bob fights beside her (LAN phase 4a).
	server.handle(900001,{"type":"begin_battle"})
	check(await Wait.until(self,func():return game.battle_view.visible),"Alice's battle pulls Bob in")
	server.backends.alice.abandon_battle()
	check(await Wait.until(self,func():
		game.return_from_battle()
		return not game.battle_view.visible),"it ends for him too and he returns to the map")
	# 队伍频道 from the chat panel.
	check(await Wait.until(self,func():return game.chat_panel.channel_button.visible),"the chat shows a 频道 button in a party")
	game.chat_panel.toggle_channel()
	check(game.chat_panel.party_channel() and game.chat_panel.channel_button.text=="队伍","it switches to 队伍")
	game.chat_panel._submit("出发")
	check(await Wait.until(self,func():return game.chat_panel.lines.any(func(line):return str(line.text)=="[队伍] Bob：出发")),"a 队伍 line comes back to Bob")
	# 记录 opens and closes; the chat row comes back down to where it was.
	var row: Control = game.chat_panel.find_child("Row",true,false)
	await process_frame
	var row_y := row.global_position.y
	game.chat_panel.toggle_history()
	await process_frame
	await process_frame
	check(row.global_position.y==row_y,"with 记录 open the chat row stays put (history grows upwards)")
	game.chat_panel.toggle_history()
	await process_frame
	await process_frame
	check(row.global_position.y==row_y,"and it stays after 记录 closes (%d, was %d)" % [int(row.global_position.y),int(row_y)])
	# Alice walks into another map; Bob is carried along.
	server.handle(900001,{"type":"report_position","map_id":1002,"cell":[16,15],"map_changed":true,"client":"alice-device"})
	check(await Wait.until(self,func():return int(game.data.map_id)==1002 and not game.area_transition_busy),"Bob is carried into map 1002 after Alice")
	await Wait.settle(self,game)
	# The leader logs out: the party disbands and Bob stays where he stands.
	var stood: Vector2i = game.cell
	var stood_map := int(game.data.map_id)
	server.disconnect_connection(900001)
	check(await Wait.until(self,func():return not game.party_panel.in_party()),"the leader going offline disbands the party")
	for i in range(30):await process_frame
	check(game.cell==stood and int(game.data.map_id)==stood_map,"Bob stays where he stood (%s on %d, was %s on %d)" % [str(game.cell),int(game.data.map_id),str(stood),stood_map])
	check(server.backends.bob.automation.position_cell==stood,"and the server keeps him there (%s)" % str(server.backends.bob.automation.position_cell))
	var location: Dictionary = server.backends.bob.session.snapshot().location
	check(int(location.map_id)==stood_map,"and his saved location is that map too (%s)" % str(location))
	check(not game.party_locked() and game.chat_panel.lines.any(func(line):return str(line.text)=="团队已解散！"),"Bob walks freely again and saw 团队已解散！")
	game.queue_free()
	await process_frame
	ws.stop()
	server.shut_down()
	server.queue_free()
	await process_frame
