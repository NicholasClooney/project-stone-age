extends SceneTree
## LAN phase 3 (docs/development/lan-profiles.md): 组队 on the map. The
## party rules (server/party.gd: joining the player in front, the 组队
## switch, 5 at most, leaving, 踢出, disbanding), members following the leader
## in a line and across map changes, encounters for the leader only, the
## automation refused in a party, 队伍频道, the presence feed's party field,
## and disconnects.
##
## The functional core runs for real: the party rules, the hub, real backends
## taking report_position, field_step, battles and auto_start. Only the shell
## is faked: the clock, and connections as plain ids (as in profile_hub_test).
const Party = preload("res://server/party.gd")
const ProfileHub = preload("res://server/profile_hub.gd")
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
	check(not views.is_empty() and views.me=="alice" and views.leader=="" and not views.accept,"after a login the next tick tells a device its party view: no party, switch off")
	report(server,1,1000,Vector2i(81,90))
	report(server,2,1000,Vector2i(80,90))
	report(server,3,1000,Vector2i(81,91))
	report(server,4,2000,Vector2i(5,5))
	var joined: Dictionary = server.handle(2,{"type":"party_join","facing":EAST,"seq":3})
	check(not joined.ok and joined.type=="rejected" and joined.seq==3 and str(joined.reason).contains("组队开关"),"Bob cannot join Alice before she switches 组队 on")
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
	# Automation: refused in a party, for members and the leader.
	var auto: Dictionary = server.handle(2,{"type":"auto_start","kind":"battle"})
	check(not auto.ok and str(auto.reason).contains("组队中"),"a member cannot start 自动练级: %s" % str(auto.get("reason","")))
	check(not server.handle(1,{"type":"auto_start","kind":"hunt"}).ok and not server.backends.alice.automation.hunt_running,"nor can the leader start a hunt")
	check(not server.handle(4,{"type":"auto_start","kind":"nothing"}).reason.contains("组队中"),"Dan, alone, is not refused for a party")
	# The leader's battle is its own; members wait and see 队长战斗中.
	wire.messages.clear()
	var fight: Dictionary = server.handle(1,{"type":"begin_battle"})
	check(fight.ok and server.backends.alice.battle_open and not server.backends.bob.battle_open and not server.backends.cid.battle_open,"Alice's encounter is her own solo battle; Bob and Cid are not pulled in")
	now += 1000
	server.presence_tick()
	check(bool(wire.last_party(2).get("battle",false)) and bool(wire.last_party(3).get("battle",false)),"the members' view says 队长战斗中")
	server.backends.alice.abandon_battle()
	now += 1000
	server.presence_tick()
	check(not bool(wire.last_party(2).get("battle",true)),"and clears when her battle closes")
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
