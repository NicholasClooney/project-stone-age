extends SceneTree
## LAN phase 2 (docs/development/lan-profiles.md): the presence feed and
## 一般频道 on the server (server/presence.gd, through the profile hub), and
## the client's model of the other players (network/presence_model.gd).
##
## The functional core runs for real: the hub, real backends taking
## report_position, the presence diffing, the chat rate limit and the model's
## interpolation. Only the shell is faked: the clock, connections (plain ids,
## as in profile_hub_test) and frame time (step() with chosen deltas).
const Presence = preload("res://server/presence.gd")
const ProfileHub = preload("res://server/profile_hub.gd")
const PresenceModel = preload("res://network/presence_model.gd")
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
	dir = "user://lan-presence-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	feed()
	chat()
	await hub()
	model()
	remove_tree(dir)
	print("LAN PRESENCE: %d failures" % failures)
	quit(1 if failures else 0)

func profile(id: String, map_id: int, cell: Vector2i, connections: Array, battle := false) -> Dictionary:
	return {"id":id,"name":id.capitalize(),"level":3,"look":{"c":"100020","face":2,"ride":-1,"rn":""},"map":map_id,"cell":cell,"battle":battle,"connections":connections}

## Messages for one connection out of a tick's [[connection, message]].
static func to(news: Array, connection: int) -> Array:
	return news.filter(func(item):return item[0]==connection).map(func(item):return item[1])

## The presence feed: same map only, diffs, throttling, battle, leaving.
func feed() -> void:
	var presence = Presence.new()
	var a := profile("a",1000,Vector2i(10,10),[1])
	var b := profile("b",1000,Vector2i(20,20),[2,3])
	var c := profile("c",2000,Vector2i(5,5),[4])
	var news: Array = presence.tick(now,[a,b,c])
	var for_a := to(news,1)
	check(for_a.size()==1 and for_a[0].full and for_a[0].map_id==1000 and for_a[0].players.size()==1 and for_a[0].players[0].id=="b","A is told about B, on the same map, and not about C")
	var entry: Dictionary = for_a[0].players[0]
	check(entry.name=="B" and entry.lv==3 and entry.c=="100020" and entry.face==2 and entry.ride==-1 and entry.cell==[20,20] and not entry.b,"an entry carries name, level, look, cell and the battle flag: %s" % str(entry))
	check(to(news,2).size()==1 and to(news,3).size()==1 and to(news,2)[0].players[0].id=="a","both of B's devices are told about A")
	check(to(news,4).size()==1 and to(news,4)[0].full and to(news,4)[0].players.is_empty(),"C, alone on its map, gets an empty list")
	check(presence.tick(now,[a,b,c]).is_empty(),"nothing changed, nothing is sent")
	b.cell = Vector2i(21,20)
	now += 50
	check(presence.tick(now,[a,b,c]).is_empty(),"within %d ms nothing is sent (throttle)" % Presence.TICK_MSEC)
	now += Presence.TICK_MSEC
	news = presence.tick(now,[a,b,c])
	check(news.size()==1 and to(news,1).size()==1,"a step reaches only the other players on the map")
	var step: Dictionary = to(news,1)[0]
	check(not step.full and step.players.size()==1 and step.players[0].keys().size()==3 and step.players[0].cell==[21,20] and step.players[0].f==Presence.step_facing(Vector2i(20,20),Vector2i(21,20)),"only the cell and facing change: %s" % str(step))
	check(Presence.step_facing(Vector2i(5,5),Vector2i(5,5))==-1 and Presence.step_facing(Vector2i(5,5),Vector2i(6,4))==4 and Presence.step_facing(Vector2i(5,5),Vector2i(4,6))==0,"facing follows the client's screen directions")
	# A battle marks B, and the mark holds a moment after it closes.
	b.battle = true
	now += Presence.TICK_MSEC
	news = presence.tick(now,[a,b,c])
	check(to(news,1).size()==1 and to(news,1)[0].players[0].get("b")==true,"a battle sets 战斗中")
	b.battle = false
	now += Presence.TICK_MSEC
	check(presence.tick(now,[a,b,c]).is_empty(),"back-to-back battles do not flicker the mark")
	now += Presence.BATTLE_HOLD_MSEC
	news = presence.tick(now,[a,b,c])
	check(to(news,1).size()==1 and to(news,1)[0].players[0].get("b")==false,"it clears %d ms after the battle" % Presence.BATTLE_HOLD_MSEC)
	# B's look changes: a mount.
	b.look = {"c":"100020","face":2,"ride":100330,"rn":"金虎"}
	now += Presence.TICK_MSEC
	var mount: Dictionary = to(presence.tick(now,[a,b,c]),1)[0].players[0]
	check(mount.ride==100330 and mount.rn=="金虎" and not mount.has("cell"),"mounting sends only the mount")
	# B goes to C's map.
	b.map = 2000
	b.cell = Vector2i(6,6)
	now += Presence.TICK_MSEC
	news = presence.tick(now,[a,b,c])
	check(to(news,1).size()==1 and to(news,1)[0].left==["b"] and to(news,1)[0].players.is_empty(),"A hears B left")
	check(to(news,2)[0].full and to(news,2)[0].map_id==2000 and to(news,2)[0].players[0].id=="c","B's devices get the new map's full list")
	check(to(news,4).size()==1 and to(news,4)[0].players[0].id=="b" and to(news,4)[0].players[0].has("name"),"C is told about B in full")
	# B disconnects both devices.
	b.connections = []
	presence.forget(2)
	presence.forget(3)
	now += Presence.TICK_MSEC
	news = presence.tick(now,[a,b,c])
	check(to(news,4).size()==1 and to(news,4)[0].left==["b"],"a player with no device left disappears")
	# A position that is not known yet shows nobody.
	var d := profile("d",-1,Vector2i.ZERO,[5])
	now += Presence.TICK_MSEC
	news = presence.tick(now,[a,b,c,d])
	check(to(news,5).size()==1 and to(news,5)[0].players.is_empty() and to(news,1).is_empty(),"a player before its first position report sees nobody and is not seen")
	# A reconnecting device is sent the full list again.
	presence.forget(1)
	news = presence.tick(now,[a,c],true)
	check(to(news,1).size()==1 and to(news,1)[0].full and to(news,1)[0].players.is_empty(),"a forgotten connection gets a full (here empty) list, clearing what it showed")
	# Bandwidth: a step message is small.
	var bytes := JSON.stringify(step).length()
	check(bytes<120,"a one-player step is %d bytes of JSON" % bytes)

## 一般频道: the speaker's map only, their own devices marked, limits.
func chat() -> void:
	var presence = Presence.new()
	var a := profile("a",1000,Vector2i(10,10),[1,2])
	var b := profile("b",1000,Vector2i(20,20),[3])
	var c := profile("c",2000,Vector2i(5,5),[4])
	var said: Dictionary = presence.say(now,a,[a,b,c],"  你好\n大家  ")
	check(said.reply.ok and said.reply.text=="你好 大家","a line is trimmed and kept on one line: %s" % said.reply.text)
	var heard: Array = said.deliveries.map(func(item):return item[0])
	check(heard==[1,2,3],"everyone on the map hears it, the speaker's devices too (%s); C on another map does not" % str(heard))
	var own: Dictionary = said.deliveries[0][1]
	check(own.type=="chat" and own.mine and own.name=="A" and own.id=="a" and own.map_id==1000 and not said.deliveries[2][1].mine,"the speaker's devices see it as theirs")
	check(not presence.say(now,a,[a,b,c],"   ").reply.ok,"an empty line is refused")
	check(not presence.say(now,a,[a,b,c],"字".repeat(Presence.CHAT_MAX_CHARS+1)).reply.ok and presence.say(now,b,[a,b,c],"字".repeat(Presence.CHAT_MAX_CHARS)).reply.ok,"a line holds up to %d characters" % Presence.CHAT_MAX_CHARS)
	check(presence.say(now+100,a,[a,b,c],"二").reply.ok and presence.say(now+200,a,[a,b,c],"三").reply.ok,"three lines in a row are fine")
	var fast: Dictionary = presence.say(now+300,a,[a,b,c],"四")
	check(not fast.reply.ok and str(fast.reply.reason).contains("太快") and fast.deliveries.is_empty(),"the fourth within %d s is refused: %s" % [Presence.CHAT_WINDOW_MSEC/1000,fast.reply.reason])
	check(presence.say(now+300,b,[a,b,c],"我还可以").reply.ok,"the limit is per player")
	check(presence.say(now+Presence.CHAT_WINDOW_MSEC+1,a,[a,b,c],"五").reply.ok,"after the window A talks again")
	check(not presence.say(now,profile("d",-1,Vector2i.ZERO,[5]),[a,b,c],"hi").reply.ok,"no map yet, no chat")

class Wire extends RefCounted:
	var messages: Array = []
	func take(connection: int, message: Dictionary) -> void:
		messages.append([connection,message])
	func of(connection: int, type: String) -> Array:
		return messages.filter(func(item):return item[0]==connection and str(item[1].type)==type).map(func(item):return item[1])

## Through the hub: logins, real backends' positions and battles, chat.
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
	check(server.handle(1,{"type":"create_profile","name":"Alice","pin":"1111"}).ok and server.handle(2,{"type":"create_profile","name":"Bob","pin":"2222"}).ok,"two players log in")
	server.presence_tick(true)
	check(wire.messages.all(func(item):return str(item[1].type)!="presence" or item[1].players.is_empty()),"nobody has a position yet: nobody is shown")
	wire.messages.clear()
	server.handle(1,{"type":"report_position","map_id":1000,"cell":[80,90],"client":"a1"})
	server.handle(2,{"type":"report_position","map_id":1000,"cell":[82,90],"client":"b1","map_changed":true})
	now += 1000
	server.presence_tick()
	var alice_sees: Array = wire.of(1,"presence")
	check(alice_sees.size()==1 and alice_sees[0].players.size()==1 and alice_sees[0].players[0].name=="Bob" and alice_sees[0].players[0].cell==[82,90],"Alice sees Bob where his client reported him: %s" % str(alice_sees))
	check(wire.of(2,"presence").size()==1 and wire.of(2,"presence")[0].players[0].name=="Alice","and Bob sees Alice")
	check(wire.of(1,"position").all(func(event):return event.client=="a1") and wire.of(2,"position").all(func(event):return event.client=="b1"),"the same-profile position mirror stays with Alice's own devices")
	wire.messages.clear()
	server.backends.bob.battle_open = true
	now += 1000
	server.presence_tick()
	check(wire.of(1,"presence").size()==1 and wire.of(1,"presence")[0].players[0].b==true and wire.of(2,"presence").is_empty(),"Bob's battle marks him for Alice only")
	server.backends.bob.battle_open = false
	# Chat through the hub.
	wire.messages.clear()
	var said: Dictionary = server.handle(2,{"type":"say","text":"一起去打猎吗？","seq":7})
	check(said.ok and said.type=="ack" and said.seq==7,"say is acknowledged")
	check(wire.of(1,"chat").size()==1 and wire.of(1,"chat")[0].text=="一起去打猎吗？" and not wire.of(1,"chat")[0].mine and wire.of(2,"chat")[0].mine,"Alice hears Bob; Bob's device marks it as his")
	check(not server.handle(3,{"type":"say","text":"hi"}).ok,"a device not logged in cannot talk")
	# A second device of Alice's gets the full list on login.
	wire.messages.clear()
	server.handle(3,{"type":"login","name":"alice","pin":"1111"})
	now += 1000
	server.presence_tick()
	check(wire.of(3,"presence").size()==1 and wire.of(3,"presence")[0].full and wire.of(1,"presence").is_empty(),"a newly logged-in device gets the full list; the others nothing new")
	# Bob leaves.
	wire.messages.clear()
	server.disconnect_connection(2)
	now += 1000
	server.presence_tick()
	check(wire.of(1,"presence").size()==1 and wire.of(1,"presence")[0].left==["bob"],"Bob's disconnect removes him")
	server.shut_down()
	server.queue_free()
	await process_frame

## The client's model: spawn, update, despawn, interpolation.
func model() -> void:
	var m = PresenceModel.new()
	var result: Dictionary = m.apply({"type":"presence","map_id":1000,"full":true,"players":[{"id":"b","name":"Bob","lv":5,"c":"100020","face":1,"ride":-1,"rn":"","cell":[10,10],"f":2,"b":false}]})
	check(result.spawned==["b"] and m.map_id==1000 and m.players.b.pos==Vector2(10,10) and m.players.b.facing==2,"a full list spawns Bob at his cell")
	m.step(0.5)
	check(not m.players.b.walking,"standing still he idles")
	result = m.apply({"type":"presence","map_id":1000,"full":false,"players":[{"id":"b","cell":[11,10],"f":6}]})
	check(result.changed==["b"] and m.players.b.cell==Vector2i(11,10) and m.players.b.pos==Vector2(10,10),"a step changes his target, not where he is drawn")
	m.step(PresenceModel.STEP_TIME/2)
	check(m.players.b.walking and absf(m.players.b.pos.x-10.5)<0.001 and m.players.b.facing==PresenceModel.facing_towards(Vector2(1,0),0),"half a step later he is half way, walking the right way (%s)" % str(m.players.b.pos))
	m.step(PresenceModel.STEP_TIME)
	check(m.players.b.pos==Vector2(11,10) and m.players.b.walking,"he arrives without overshooting and keeps the walk a moment")
	m.step(PresenceModel.WALK_LINGER)
	check(not m.players.b.walking and m.players.b.facing==6,"then stands, facing as the server says")
	m.apply({"type":"presence","map_id":1000,"players":[{"id":"b","cell":[15,10]}]})
	m.step(PresenceModel.STEP_TIME)
	check(m.players.b.pos.x>12.0,"far behind, he catches up faster than walking pace (%.2f)" % m.players.b.pos.x)
	m.apply({"type":"presence","map_id":1000,"players":[{"id":"b","cell":[60,10]}]})
	m.step(0.01)
	check(m.players.b.pos==Vector2(60,10) and not m.players.b.walking,"a warp beyond %d cells jumps" % int(PresenceModel.SNAP_CELLS))
	m.apply({"type":"chat","id":"b","text":"你好"})
	check(m.players.b.speech=="你好","a chat line shows over him")
	m.step(PresenceModel.SPEECH_SECONDS+0.1)
	check(m.players.b.speech=="","for %d s" % int(PresenceModel.SPEECH_SECONDS))
	check(m.apply({"type":"presence","map_id":1000,"players":[{"id":"x","b":true}]}).spawned.is_empty() and not m.players.has("x"),"a partial entry for someone unknown is ignored until a full one comes")
	result = m.apply({"type":"presence","map_id":1000,"players":[],"left":["b"]})
	check(result.despawned==["b"] and m.players.is_empty(),"leaving despawns him")
	m.apply({"type":"presence","map_id":1000,"full":true,"players":[{"id":"b","cell":[1,1],"name":"Bob"}]})
	result = m.apply({"type":"presence","map_id":2000,"players":[{"id":"c","cell":[2,2],"name":"Cid"}]})
	check(result.despawned==["b"] and m.map_id==2000 and m.players.keys()==["c"],"news from another map replaces the list")
	check(PresenceModel.facing_towards(Vector2.ZERO,3)==3 and PresenceModel.facing_towards(Vector2(-1,1),0)==0,"facing keeps its value with no move and matches the screen directions")
