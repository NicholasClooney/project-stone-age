extends SceneTree
## LAN phase 4a (docs/development/lan-profiles.md "Phase 4a"): one battle for
## the whole 组队 party. Everyone enters with their own stats and pets, each
## player commands their own slot and the turn waits for everyone, the 45 s
## timer auto-attacks for whoever did not command, a player without a device
## is auto-played, escape takes out one player, 队伍共享经验 on and off
## against the original's formula (battle.c BATTLE_AddExpItem), settlement
## and pending locks per member, a partial and a total defeat, and a real
## game client as a member.
##
## The functional core runs for real: the hub, real backends and
## GameSessions, the party rules, the party battle with its seeded rng. Only
## the shell is faked: the clocks (presence and the turn timer), connections
## as plain ids; the client part uses a real localhost WebSocket.
const ProfileHub = preload("res://server/profile_hub.gd")
const WsServer = preload("res://server/ws_server.gd")
const PartyBattleSession = preload("res://server/party_battle_session.gd")
const Wait = preload("res://tests/support/wait.gd")
const EAST := 5
var failures := 0
var now := 10000
var battle_now := 500000
var dir := ""
var _hubs := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clock() -> int:
	return now

func battle_clock() -> int:
	return battle_now

func seconds() -> float:
	return now/1000.0

static func remove_tree(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):return
	for sub in DirAccess.get_directories_at(folder):remove_tree(folder.path_join(sub))
	for file in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)

func run() -> void:
	dir = "user://lan-party-battle-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	formula()
	await flow()
	await leader_escape()
	await rewards(true)
	await rewards(false)
	await partial_defeat()
	await total_defeat()
	await wild_gold()
	await client()
	remove_tree(dir)
	print("LAN PARTY BATTLE: %d failures" % failures)
	quit(1 if failures else 0)

## battle.c:4749-4770 as written (EXPGET_MAXLEVEL 5, EXPGET_DIV 15).
static func original_exp(exp: int, level: int, enemy_level: int) -> int:
	var b_level := level-enemy_level
	var nowexp := 0
	if b_level<=5:
		nowexp = exp
	else:
		b_level = 5+15-b_level
		if b_level>15:b_level = 15
		if b_level<=0:nowexp = 1
		else:nowexp = exp*b_level/15
		if nowexp<1:nowexp = 1
	return nowexp

func formula() -> void:
	var same := true
	for level in range(1,40):
		for enemy_level in [1,3,10]:
			for exp in [1,7,20,300]:
				if PartyBattleSession.gap_exp(exp,level,enemy_level)!=original_exp(exp,level,enemy_level):same = false
	check(same,"the level gap follows battle.c's EXPGET_MAXLEVEL/EXPGET_DIV exactly")
	check(PartyBattleSession.gap_exp(20,6,1)==20 and PartyBattleSession.gap_exp(20,7,1)==18 and PartyBattleSession.gap_exp(20,30,1)==1,"5 levels above: whole; 6 above: 14/15; far above: 1")

class Wire extends RefCounted:
	var messages: Array = []
	func take(connection: int, message: Dictionary) -> void:
		messages.append([connection,message])
	func of(connection: int, type: String) -> Array:
		return messages.filter(func(item):return item[0]==connection and str(item[1].type)==type).map(func(item):return item[1])
	func last_party(connection: int) -> Dictionary:
		var views := of(connection,"party")
		return views[-1] if not views.is_empty() else {}

## A hub with Alice (1, the admin, leader), Bob (2) and Cid (3) in one party
## on the village map. Returns [server, wire].
func party_hub(names: Array = ["Alice","Bob","Cid"]) -> Array:
	_hubs += 1
	# Saves sit beside the accounts file: every scenario starts from new characters.
	var folder := dir.path_join("hub-%d" % _hubs)
	DirAccess.make_dir_recursive_absolute(folder)
	var server = ProfileHub.new(folder.path_join("accounts.json"),seconds)
	server.tick = false
	server.backups = false
	server.share_dir = ""
	server.presence_clock = clock
	server.battle_clock = battle_clock
	root.add_child(server)
	server.start()
	var wire := Wire.new()
	server.outgoing.connect(wire.take)
	var cells := [Vector2i(81,90),Vector2i(80,90),Vector2i(81,91)]
	for i in range(names.size()):
		server.handle(i+1,{"type":"create_profile","name":names[i],"pin":"%d%d%d%d" % [i+1,i+1,i+1,i+1]})
		server.handle(i+1,{"type":"report_position","map_id":1000,"cell":[cells[i].x,cells[i].y],"client":"c%d" % (i+1)})
	server.handle(2,{"type":"party_join","facing":EAST})
	if names.size()>2:server.handle(3,{"type":"party_join","facing":2})
	return [server,wire]

## Test characters: level, hp, attack, speed, and a pet (level, attack,
## speed) as the active pet when given.
func setup(server, id: String, level: int, hp: int, attack: int, speed: int, pet: Array = []) -> void:
	var session = server.backends[id].session
	var player: Dictionary = session._profile.player
	player.level = level
	player.hp = hp
	player.max_hp = hp
	player.attack = attack
	player.defence = 0
	player.speed = speed
	if pet.is_empty():return
	session.grant_starter_pets()
	session.select_pet(0)
	var own: Dictionary = session._profile.pets[0]
	own.level = int(pet[0])
	own.attack = int(pet[1])
	own.speed = int(pet[2])
	own.hp = 500
	own.max_hp = 500
	own.defence = 0

func live(server, id: String) -> Dictionary:
	return server.backends[id].battle.snapshot()

func entry_of(server, id: String) -> Dictionary:
	return server.party_battles.fighting.get(id,{})

## A battle_command from connection `connection`, naming its battle, turn and slot.
func send(server, connection: int, action: String, extra: Dictionary = {}) -> Dictionary:
	var state := live(server,server.profile_of(connection))
	var command := {"type":"battle_command","action":action,"target":-1,"battle_id":state.battle_id,"turn":state.turn,"slot":state.party_slot}
	command.merge(extra,true)
	return server.handle(connection,command)

func pet(server, connection: int, command: String) -> Dictionary:
	var state := live(server,server.profile_of(connection))
	return server.handle(connection,{"type":"battle_pet_command","command":command,"battle_id":state.battle_id,"turn":state.turn,"slot":state.party_slot})

func actors(frames: Array) -> Array:
	return frames.map(func(frame):return "%s%d" % [str(frame.actor),int(frame.get("ally_index",-1)) if str(frame.actor).begins_with("ally") else -1])

func close(server) -> void:
	server.shut_down()
	server.queue_free()
	await process_frame

## Entering, per-slot commands and waiting, the timer, a lost device, an escape.
func flow() -> void:
	var made := party_hub()
	var server = made[0]
	var wire: Wire = made[1]
	setup(server,"alice",5,5000,1,30,[1,1,5])
	setup(server,"bob",5,5000,1,20,[1,1,4])
	setup(server,"cid",5,5000,1,15,[1,1,3])
	var bob_pet := str(server.backends.bob.session._profile.pets[0].name)
	wire.messages.clear()
	var fight: Dictionary = server.handle(1,{"type":"begin_battle","enemy_count":3})
	check(fight.ok and ["alice","bob","cid"].all(func(id):return server.backends[id].battle_open),"the leader meets enemies: all three are in the battle")
	var entry := entry_of(server,"alice")
	check(entry.get("ids",[])==["alice","bob","cid"] and entry_of(server,"cid")==entry,"one battle, the leader in slot 0, the members after")
	var pendings: Array = ["alice","bob","cid"].map(func(id):return server.backends[id].session._pending)
	check(pendings.all(func(pending):return bool(pending.get("party",false)) and str(pending.party_battle_id)==str(entry.id)),"each GameSession holds its own pending record for the party battle")
	check(pendings.all(func(pending):return str(pending.battle_id).begins_with("battle-")) and pendings.map(func(pending):return pending.enemies.size())==[3,3,3],"with its own battle id and the shared troop")
	var refused: Dictionary = server.handle(2,{"type":"buy_item","item":"potion"})
	check(not refused.ok,"Bob's shop is refused until his settlement")
	var bob_start: Array = wire.of(2,"battle_started")
	var bob_view: Dictionary = bob_start[0].state if not bob_start.is_empty() else {}
	check(int(bob_view.get("party_slot",-1))==1 and int(bob_view.get("player_hp",0))==5000 and str(bob_view.get("pet_name",""))==bob_pet,"Bob's devices see the battle from his slot: his own hp and pet")
	check(bob_view.get("allies",[]).map(func(ally):return ally.name)==["Alice","Cid"] and not bool(bob_view.get("can_capture",true)),"the leader and Cid beside him; no capture in a party battle")
	var cid_start: Array = wire.of(3,"battle_started")
	check(not cid_start.is_empty() and int(cid_start[0].state.party_slot)==2 and cid_start[0].state.allies.map(func(ally):return ally.name)==["Alice","Bob"],"Cid's from slot 2")
	check(live(server,"alice").allies.map(func(ally):return ally.name)==["Bob","Cid"] and int(live(server,"alice").party_slot)==0,"Alice's, as leader, from slot 0")
	# Each player commands their own slot; the turn waits for everyone.
	wire.messages.clear()
	check(send(server,1,"attack",{"target":0}).ok and int(live(server,"alice").turn)==0,"Alice's command alone does not resolve the turn")
	var status: Array = wire.of(2,"battle_state")
	var party: Dictionary = status[-1].state.party if not status.is_empty() else {}
	check(not party.is_empty() and bool(party.members[0].sent) and not bool(party.members[1].sent) and int(party.seconds)==45,"Bob's devices see Alice has sent and he has not, 45 s on the clock")
	var wrong: Dictionary = send(server,2,"attack",{"slot":2})
	check(not wrong.ok and bool(wrong.get("stale",false)),"a command naming another slot is dropped")
	var capture: Dictionary = send(server,2,"capture")
	check(not capture.ok and str(capture.reason).contains("捕捉"),"capture is refused in a party battle (4b): %s" % str(capture.get("reason","")))
	check(not send(server,2,"switch").ok,"and so is switching pets")
	check(send(server,2,"attack",{"target":1}).ok and int(live(server,"bob").turn)==0,"Bob's in: still waiting for Cid")
	check(pet(server,3,"standby").ok,"Cid sets his own pet's command")
	wire.messages.clear()
	check(send(server,3,"defend").ok and int(live(server,"alice").turn)==1,"Cid's command completes the turn")
	check([1,2,3].all(func(connection):return wire.of(connection,"battle_turn").size()==1),"every device gets the resolved turn")
	var alice_turn: Dictionary = wire.of(1,"battle_turn")[0].state
	var bob_turn: Dictionary = wire.of(2,"battle_turn")[0].state
	var cid_turn: Dictionary = wire.of(3,"battle_turn")[0].state
	var alice_actors := actors(alice_turn.turn_frames)
	check(alice_actors.has("player-1") and alice_actors.has("ally0") and alice_actors.has("ally1") and alice_actors.has("pet-1") and alice_actors.has("ally_pet0"),"Alice's turn animates everyone: %s" % str(alice_actors))
	var bob_actors := actors(bob_turn.turn_frames)
	check(bob_actors.count("player-1")==alice_actors.count("ally0") and bob_actors.count("ally0")==alice_actors.count("player-1"),"on Bob's screen he is the player and Alice ally 0: %s" % str(bob_actors))
	check(str(bob_turn.last_player_command)=="attack" and str(cid_turn.last_player_command)=="defend" and str(cid_turn.last_pet_command)=="standby","each device replays its own commands")
	check(alice_turn.turn_frames.any(func(frame):return str(frame.actor)=="ally_pet" and int(frame.ally_index)==1 and str(frame.outcome)=="standby"),"Cid's pet stood by as he told it")
	# The turn timer: 45 s, then whoever did not command attacks.
	wire.messages.clear()
	send(server,1,"defend")
	server.party_battles.tick()
	battle_now += 44000
	server.party_battles.tick()
	check(int(live(server,"alice").turn)==1,"44 s on: still waiting")
	battle_now += 1000
	server.party_battles.tick()
	check(int(live(server,"alice").turn)==2,"45 s: the turn resolves")
	var timed: Dictionary = wire.of(1,"battle_turn")[-1].state
	check(timed.events.any(func(line):return str(line).contains("Bob超时")) and timed.events.any(func(line):return str(line).contains("Cid超时")),"the turn says who timed out")
	check(timed.turn_frames.any(func(frame):return str(frame.actor)=="ally" and int(frame.ally_index)==0 and str(frame.outcome) in ["hit","miss","critical"]),"Bob attacked for his missed turn")
	check(server.party.members("alice").size()==3,"nobody is dropped from the party for a missed turn")
	# Cid's device drops: the AI plays him, he stays in party and battle.
	server.disconnect_connection(3)
	check(server.party.in_party("cid") and server.party_battles.in_battle("cid"),"Cid's device drops: he stays in the battle and the party")
	send(server,1,"defend")
	check(send(server,2,"defend").ok and int(live(server,"alice").turn)==3,"the turn no longer waits for Cid")
	check(live(server,"alice").turn_frames.any(func(frame):return str(frame.actor)=="ally" and int(frame.ally_index)==1),"the AI attacked for Cid")
	# Bob escapes: only he leaves the battle.
	var bob_id := str(server.backends.bob.session._pending.battle_id)
	for attempt in range(5):
		if not bool(live(server,"bob").active):break
		send(server,1,"defend")
		send(server,2,"escape")
	var bob_after := live(server,"bob")
	check(not bool(bob_after.active) and str(bob_after.outcome)=="escaped" and bool(live(server,"alice").active),"Bob gets away; the battle goes on without him")
	check(server.backends.bob.session._pending.is_empty() and bob_id in server.backends.bob.session._profile.completed_battles,"Bob is settled on his own save at once")
	check(server.party.is_member("bob") and not server.party_battles.in_battle("bob"),"he stays in the party")
	check(server.handle(2,{"type":"battle_close"}).ok and not server.backends.bob.battle_open,"his device closes his battle")
	check(server.handle(2,{"type":"buy_item","item":"potion"}).ok,"and his shop works again")
	check(not send(server,2,"attack").ok,"a command from Bob no longer reaches the battle")
	# Alice fights on (Cid by the AI) to the end.
	var gold_before := int(server.backends.alice.session._profile.player.gold)
	for i in range(400):
		if not bool(live(server,"alice").active):break
		send(server,1,"attack")
	check(str(live(server,"alice").outcome)=="win","Alice and Cid's AI win")
	check(server.backends.alice.session._pending.is_empty() and server.backends.cid.session._pending.is_empty() and server.party_battles.battles.is_empty(),"both are settled; the battle is gone")
	check(int(server.backends.alice.session._profile.player.gold)>gold_before,"Alice is paid")
	check(not server.party.in_party("cid") and server.party.is_member("bob"),"Cid, still without a device, leaves the party once it is over; Bob stays")
	check(str(server.backends.bob.battle.snapshot().outcome)=="escaped","Bob's own battle still reads as his escape")
	server.handle(1,{"type":"battle_close"})
	server.handle(1,{"type":"report_position","map_id":1000,"cell":[82,90],"client":"c1"})
	check(server.backends.bob.automation.position_cell==Vector2i(81,90),"Alice walks on and Bob follows her again")
	await close(server)

## The leader escapes: the members fight on; the leader waits for them.
func leader_escape() -> void:
	var made := party_hub(["Alice","Bob"])
	var server = made[0]
	setup(server,"alice",5,5000,1,30)
	setup(server,"bob",5,5000,1,20)
	server.handle(1,{"type":"begin_battle","enemy_count":2})
	for attempt in range(5):
		if not bool(live(server,"alice").active):break
		send(server,1,"escape")
		send(server,2,"defend")
	check(str(live(server,"alice").outcome)=="escaped" and bool(live(server,"bob").active),"Alice gets away; Bob fights on")
	check(server.backends.alice.session._pending.is_empty() and server.party.is_leader("alice"),"Alice is settled and still leads the party")
	server.handle(1,{"type":"battle_close"})
	var moved: Dictionary = server.handle(1,{"type":"report_position","map_id":1000,"cell":[83,90],"client":"c1"})
	check(bool(moved.get("party",false)) and server.backends.alice.automation.position_cell==Vector2i(81,90),"she cannot walk off while Bob still fights")
	var met: Dictionary = server.handle(1,{"type":"wild_encounter","map_id":100,"cell":[600,500]})
	check(not met.ok and str(met.reason).contains("战斗"),"nor meet enemies: %s" % str(met.get("reason","")))
	check(live(server,"bob").allies[0].get("escaped",false),"on Bob's screen Alice is marked gone")
	for i in range(400):
		if not bool(live(server,"bob").active):break
		send(server,2,"attack")
	check(str(live(server,"bob").outcome)=="win" and server.backends.bob.session._pending.is_empty(),"Bob finishes the battle and is settled")
	server.handle(1,{"type":"report_position","map_id":1000,"cell":[82,90],"client":"c1"})
	check(server.backends.alice.automation.position_cell==Vector2i(82,90),"then Alice walks again")
	await close(server)

## 队伍共享经验 on (every living member and pet gets each enemy's exp, the
## level gap per receiver) and off (the original: only the one who hit it).
func rewards(share: bool) -> void:
	var made := party_hub()
	var server = made[0]
	var wire: Wire = made[1]
	setup(server,"alice",1,5000,9999,900,[1,1,5])
	setup(server,"bob",30,5000,9999,800,[20,1,4])
	setup(server,"cid",10,5000,1,1,[3,9999,850])
	var tag := "shared" if share else "kill credit"
	if not share:
		check(not server.handle(2,{"type":"party_share_exp","on":false}).ok,"only the leader switches 队伍共享经验")
		check(server.handle(1,{"type":"party_share_exp","on":false}).ok,"Alice switches it off")
		server.party_tick()
		check(not bool(wire.last_party(2).get("share_exp",true)),"the members' party view shows it off")
	else:
		server.party_tick()
		check(bool(wire.last_party(2).get("share_exp",false)),"队伍共享经验 starts on, in every member's party view")
	var gold: Dictionary = {}
	for id in ["alice","bob","cid"]:gold[id] = int(server.backends[id].session._profile.player.gold)
	server.handle(1,{"type":"begin_battle","enemy_count":2})
	var session = entry_of(server,"alice").session
	check(session.share_exp==share,"the battle takes the switch (%s)" % tag)
	var enemies: Array = session.snapshot().enemies
	pet(server,1,"standby")
	pet(server,2,"standby")
	# Alice goes for enemy 0 and Cid's pet for enemy 1; Bob and Cid hold.
	wire.messages.clear()
	for i in range(40):
		if not bool(live(server,"alice").active):break
		send(server,1,"attack" if int(session.snapshot().enemies[0].hp)>0 else "defend",{"target":0})
		send(server,2,"defend")
		send(server,3,"defend",{"pet_target":1})
	check(str(live(server,"alice").outcome)=="win","they win (%s)" % tag)
	# Who felled each enemy, read off the frames Alice's devices were sent.
	var hp: Array = enemies.map(func(enemy):return int(enemy.hp))
	var killers: Array = ["",""]
	for event in wire.of(1,"battle_turn"):
		for frame in event.state.turn_frames:
			for i in range(2):
				if hp[i]>0 and int(frame.enemies[i].hp)==0:killers[i] = {"player":"alice","pet":"alice_pet","ally":["bob","cid"][int(frame.ally_index)],"ally_pet":["bob_pet","cid_pet"][int(frame.ally_index)]}.get(str(frame.actor),"?")
				hp[i] = int(frame.enemies[i].hp)
	check(killers==["alice","cid_pet"],"Alice felled enemy 0, Cid's pet enemy 1: %s" % str(killers))
	var reward := int(enemies[0].reward_xp)
	var levels := [int(enemies[0].level),int(enemies[1].level)]
	var expected := {}
	for pair in [["alice",1,1],["bob",30,20],["cid",10,3]]:
		var player := 0
		var own_pet := 0
		for i in range(2):
			if share or killers[i]==pair[0]:player += original_exp(reward,int(pair[1]),levels[i])
			if share or killers[i]==str(pair[0])+"_pet":own_pet += original_exp(reward,int(pair[2]),levels[i])
		expected[pair[0]] = [player,own_pet]
	for id in ["alice","bob","cid"]:
		var state: Dictionary = server.backends[id].battle_state
		var got := [int(state.get("xp",-1)),int(state.get("pet_reward_xp",[-1])[0])]
		check(got==expected[id],"%s (%s): player and pet exp %s = the original formula %s" % [id,tag,str(got),str(expected[id])])
		check(server.backends[id].session._pending.is_empty() and str(server.backends[id].session._pending.get("battle_id",""))=="","%s settled; its pending record is gone" % id)
		check(int(server.backends[id].session._profile.player.gold)==int(gold[id])+int(enemies[0].reward_gold)+int(enemies[1].reward_gold),"%s is paid the gold in full, not a share" % id)
	check(int(server.backends.cid.session._profile.player.xp)==int(expected.cid[0]),"Cid's save holds his experience")
	await close(server)

## Cid falls, the others win: as the original (battle.c BATTLE_Exit), he gets
## up with 1 HP where he stands, stays in the party, earns nothing.
func partial_defeat() -> void:
	var made := party_hub()
	var server = made[0]
	setup(server,"alice",5,5000,1,30)
	setup(server,"bob",5,5000,1,20)
	setup(server,"cid",5,1,1,15)
	var location: Dictionary = server.backends.cid.session._profile.location.duplicate()
	var before: Dictionary = server.backends.cid.session._profile.player.duplicate(true)
	server.handle(1,{"type":"begin_battle","enemy_count":2})
	var session = entry_of(server,"alice").session
	# Alice and Bob hold back until the enemies have felled Cid.
	for i in range(400):
		if not bool(live(server,"alice").active):break
		var standing: bool = session.slot_standing(2)
		send(server,1,"defend" if standing else "attack")
		send(server,2,"defend" if standing else "attack")
		if standing:send(server,3,"attack")
	check(str(live(server,"alice").outcome)=="win" and session.slot_hp(2)==0,"Cid fell; Alice and Bob won")
	var cid: Dictionary = server.backends.cid.session._profile
	check(int(cid.player.hp)==1 and cid.location==location,"Cid gets up with 1 HP where he stood, not in the village")
	check(int(cid.player.xp)==int(before.xp) and int(cid.player.gold)==int(before.gold),"and earns no experience or gold")
	check(int(cid.player.get("charm",60))<int(before.get("charm",60)),"his fall costs charm, as a defeat does")
	check(server.party.members("alice")==["alice","bob","cid"],"he stays in the party")
	var view := live(server,"cid")
	check(str(view.outcome)=="win" and bool(view.get("party_fallen",false)),"his screen shows the party's win and that he fell")
	check(server.handle(3,{"type":"battle_close"}).ok and server.backends.cid.session._profile.location==location,"closing it leaves him where he is")
	check(int(server.backends.alice.battle_state.get("xp",0))>0 and server.backends.alice.session._pending.is_empty(),"Alice is rewarded")
	await close(server)

## Everyone falls: every player goes to the village, recovered (the solo rule).
func total_defeat() -> void:
	var made := party_hub()
	var server = made[0]
	for id in ["alice","bob","cid"]:setup(server,id,5,1,1,10)
	server.handle(1,{"type":"begin_battle","enemy_count":3})
	for i in range(400):
		if not bool(live(server,"alice").active):break
		for connection in [1,2,3]:
			var state := live(server,server.profile_of(connection))
			if bool(state.active) and int(state.player_hp)>0:send(server,connection,"attack")
		server.party_battles.tick()
	check(str(live(server,"alice").outcome)=="defeat","the whole party falls")
	for id in ["alice","bob","cid"]:
		var profile: Dictionary = server.backends[id].session._profile
		check(str(live(server,id).outcome)=="defeat" and int(profile.location.map_id)==1000 and int(profile.location.x)==80 and int(profile.player.hp)==int(profile.player.max_hp),"%s goes to the village, recovered" % id)
		check(server.backends[id].session._pending.is_empty(),"%s settled" % id)
		check(server.backends[id].automation.position_map==1000 and server.backends[id].automation.position_cell==Vector2i(80,90),"%s's server position is the village too" % id)
	check(server.party.members("alice").size()==3,"the party stays together")
	await close(server)

## A wild troop: each member's pending pays its own level x 10 (setup.cf
## BATTLEGOLD, BATTLE_GetExpGold for each living player).
func wild_gold() -> void:
	var made := party_hub(["Alice","Bob"])
	var server = made[0]
	setup(server,"alice",3,5000,1,10)
	setup(server,"bob",7,5000,1,10)
	var opened := {}
	for attempt in range(40):
		server.backends.alice.encounter_rng.seed = 1000+attempt
		opened = server.handle(1,{"type":"wild_encounter","map_id":100,"cell":[600,500]})
		if opened.ok:break
	check(opened.ok and server.backends.bob.battle_open,"a wild troop pulls the party in")
	check(int(server.backends.alice.session._pending.get("battle_gold",-1))==30 and int(server.backends.bob.session._pending.get("battle_gold",-1))==70,"each pending pays its own level x 10")
	check(server.backends.bob.session._pending.enemies.map(func(e):return e.species)==server.backends.alice.session._pending.enemies.map(func(e):return e.species),"the same troop for both")
	server.backends.alice.abandon_battle()
	check(server.backends.bob.session._pending.is_empty() and server.party_battles.battles.is_empty(),"ending it without rewards settles everyone")
	await close(server)

## A real game client as a member: its own command bar, 「等待队友…」 after
## sending, the turn countdown, and the turn when the leader commands.
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
	server.handle(900001,{"type":"create_profile","name":"Alice","pin":"1111"})
	server.handle(900002,{"type":"create_profile","name":"Bob","pin":"2222"})
	server.disconnect_connection(900002)
	setup(server,"alice",5,5000,1,30)
	setup(server,"bob",5,5000,1,20)
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
	var map_id := int(game.data.map_id)
	var ahead: Vector2i = game.cell+game.SCREEN_DIRECTIONS[(int(game.player.facing)+4)%8]
	server.handle(900001,{"type":"report_position","map_id":map_id,"cell":[ahead.x,ahead.y],"client":"alice"})
	game.classic_hud.find_child("PartyButton",true,false).pressed.emit()
	check(await Wait.until(self,func():return game.party_panel.is_member()),"Bob joins Alice's party")
	check(await Wait.until(self,func():return game.party_panel.list.find_child("PartyShareExpNote",true,false)!=null),"his party list shows 队伍共享经验 (the leader's switch)")
	server.handle(900001,{"type":"begin_battle","enemy_count":2})
	var view = game.battle_view
	check(await Wait.until(self,func():return view.visible and int(view.state.get("party_slot",-1))==1),"Alice meets enemies: Bob's screen opens the battle from his slot")
	check(int(view.state.player_hp)==5000 and view.state.allies.map(func(ally):return ally.name)==["Alice"],"his own hp in the player's place, Alice beside him")
	check(await Wait.until(self,func():return view.command_panel.visible and not view.is_animating() and view.elapsed>=view.feedback_until),"his command bar comes up")
	check(await Wait.until(self,func():return view.party_status.visible and view.party_status.text.contains("回合剩余")),"with the turn countdown: %s" % view.party_status.text)
	view._request_action("attack")
	view.select_target(view.enemy_actor(0))
	check(await Wait.until(self,func():return server.party_battles.fighting.has("bob") and server.party_battles.fighting.bob.session.has_command(1)),"his attack reaches his own slot")
	check(view.command_phase=="waiting" and not view.command_panel.visible and view.hint.text=="等待队友…","he waits: 「等待队友…」, no command bar")
	check(await Wait.until(self,func():return view.party_status.text.contains("等待队友") and view.party_status.text.contains("（Alice）")),"the status line names who the turn waits for: %s" % view.party_status.text)
	var state: Dictionary = server.backends.alice.battle.snapshot()
	server.handle(900001,{"type":"battle_command","action":"attack","target":0,"battle_id":state.battle_id,"turn":state.turn,"slot":0})
	check(await Wait.until(self,func():return int(view.state.get("turn",0))==1),"Alice commands: the turn resolves on Bob's screen")
	check(await Wait.until(self,func():return view.command_phase=="player" and view.command_panel.visible and not view.is_animating() and view.elapsed>=view.feedback_until),"after it plays, Bob's command bar is back")
	server.backends.alice.abandon_battle()
	check(await Wait.until(self,func():
		game.return_from_battle()
		return not view.visible),"the battle ends and he returns to the map")
	game.queue_free()
	await process_frame
	ws.stop()
	server.shut_down()
	server.queue_free()
	await process_frame
