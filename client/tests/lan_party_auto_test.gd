extends SceneTree
## LAN phase 4c (docs/development/lan-profiles.md "Phase 4c"): automation in a
## party. The leader runs 自动练级 and every troop it meets is a party battle
## the members enter; a member with 组队自动战斗 commands at once from its own
## preset (a 回复药 at its 停机线); a member without it still gets the 45 s
## timer; capture, hunts and the find-pet cycle stay refused; the leader's run
## stops on its own 停机线 and each member's, when it stops, a member leaves,
## is kicked, the party disbands or the leader disconnects; it spends no frame
## budget while waiting on a member; it resumes alone after a restart; and a
## real game client as a member switches 自动战斗 and 快速战斗 and sees the
## status line instead of the battle view.
##
## The functional core runs for real: the hub, real backends and
## GameSessions, the party rules, the party battle with its seeded rng and
## the real 自动练级 runner (stepped by hand). Only the shell is faked: the
## clocks (presence and the turn timer), connections as plain ids; the client
## part uses a real localhost WebSocket.
const ProfileHub = preload("res://server/profile_hub.gd")
const WsServer = preload("res://server/ws_server.gd")
const Wait = preload("res://tests/support/wait.gd")
const EAST := 5
const FIELD := 100
const CELL := Vector2i(600,500)
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
	dir = "user://lan-party-auto-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	await selection_context()
	await refusals()
	await leader_run()
	await healing()
	await stops()
	await budget()
	await resume()
	await client()
	remove_tree(dir)
	print("LAN PARTY AUTO: %d failures" % failures)
	quit(1 if failures else 0)

class Wire extends RefCounted:
	var messages: Array = []
	func take(connection: int, message: Dictionary) -> void:
		messages.append([connection,message])
	func of(connection: int, type: String) -> Array:
		return messages.filter(func(item):return item[0]==connection and str(item[1].type)==type).map(func(item):return item[1])

func new_hub(folder: String):
	var server = ProfileHub.new(folder.path_join("accounts.json"),seconds)
	server.tick = false
	server.backups = false
	server.share_dir = ""
	server.presence_clock = clock
	server.battle_clock = battle_clock
	root.add_child(server)
	server.start()
	return server

## A hub with Alice (1, leader), Bob (2) and Cid (3) in one party on the
## village map; then Alice walks out to the field and the others follow.
## Every player is strong enough to win quickly and survive. [server, wire].
func party_hub(names: Array = ["Alice","Bob","Cid"]) -> Array:
	_hubs += 1
	var folder := dir.path_join("hub-%d" % _hubs)
	DirAccess.make_dir_recursive_absolute(folder)
	var server = new_hub(folder)
	var wire := Wire.new()
	server.outgoing.connect(wire.take)
	var cells := [Vector2i(81,90),Vector2i(80,90),Vector2i(81,91)]
	for i in range(names.size()):
		server.handle(i+1,{"type":"create_profile","name":names[i],"pin":"%d%d%d%d" % [i+1,i+1,i+1,i+1]})
		server.handle(i+1,{"type":"report_position","map_id":1000,"cell":[cells[i].x,cells[i].y],"client":"c%d" % (i+1)})
	server.handle(2,{"type":"party_join","facing":EAST})
	if names.size()>2:server.handle(3,{"type":"party_join","facing":2})
	for id in server.backends:setup(server,id)
	server.handle(1,{"type":"report_position","map_id":FIELD,"cell":[CELL.x,CELL.y],"map_changed":true,"client":"c1"})
	return [server,wire]

func setup(server, id: String, hp: int = 5000) -> void:
	server.backends[id].session.set_automation_settings({"training":{"borrow_troops":false}}) # Local turn/healing fixtures; borrowed LAN is tested separately.
	var session = server.backends[id].session
	var player: Dictionary = session._profile.player
	player.level = 5
	player.hp = hp
	player.max_hp = 5000
	player.attack = 400
	player.defence = 50
	player.speed = 40

func automation(server, id: String):
	return server.backends[id].automation

func start_run(server) -> Dictionary:
	return server.handle(1,{"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y],"speed":8})

func entry_of(server, id: String) -> Dictionary:
	return server.party_battles.fighting.get(id,{})

func send(server, connection: int, action: String) -> Dictionary:
	var state: Dictionary = server.backends[server.profile_of(connection)].battle.snapshot()
	return server.handle(connection,{"type":"battle_command","action":action,"target":-1,"battle_id":state.battle_id,"turn":state.turn,"slot":state.party_slot})

## Steps the leader's run until `done` (or `limit` steps). Manual members in
## `manual` send attacks whenever their slot is waiting; the party's turn
## timer is ticked like the hub's frame.
func drive(server, done: Callable, manual: Array = [], limit: int = 600) -> bool:
	for i in range(limit):
		if done.call():return true
		automation(server,"alice").step()
		for connection in manual:
			var id: String = server.profile_of(connection)
			var entry := entry_of(server,id)
			if not entry.is_empty() and entry.ids.find(id) in entry.session.waiting_slots():send(server,connection,"attack")
		server.party_battles.tick()
	return done.call()

func close(server) -> void:
	server.shut_down()
	server.queue_free()
	await process_frame

# ---- scenarios ------------------------------------------------------------------

## Capture, hunts, the find-pet cycle and pet training stay refused for
## everyone in a party; members cannot start 自动练级 themselves; the leader
## may, with the 普通攻击 preset only.
func refusals() -> void:
	var made := party_hub()
	var server = made[0]
	check(server.backends.bob.automation.position_map==FIELD and server.backends.cid.automation.position_map==FIELD,"the members follow the leader to the field")
	for kind in ["hunt","find_pet"]:
		var leader: Dictionary = server.handle(1,{"type":"auto_start","kind":kind,"map_id":FIELD,"cell":[CELL.x,CELL.y]})
		var member: Dictionary = server.handle(2,{"type":"auto_start","kind":kind,"map_id":FIELD,"cell":[CELL.x,CELL.y]})
		check(not leader.ok and not member.ok and str(leader.reason).contains("自动抓宠、找宠和后台搜宠") and str(member.reason)==str(leader.reason),"%s is refused for leader and member alike: %s" % [kind,str(leader.get("reason",""))])
	check(not server.handle(1,{"type":"auto_start","kind":"capture_battle","target":0}).ok,"自动抓宠 in a battle is refused")
	var train: Dictionary = server.handle(1,{"type":"auto_start","kind":"pet_train","pet_id":"x"})
	check(not train.ok and str(train.reason).contains("带宠升级"),"带宠升级 is refused: %s" % str(train.get("reason","")))
	var member: Dictionary = server.handle(2,{"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y]})
	check(not member.ok and str(member.reason).contains("「自动战斗」"),"a member cannot start 自动练级; the reason points to 自动战斗: %s" % str(member.get("reason","")))
	server.handle(1,{"type":"set_automation_settings","settings":{"training":{"preset":"capture"}}})
	var capture: Dictionary = start_run(server)
	check(not capture.ok and str(capture.reason).contains("普通攻击"),"the leader's 自动练级 with the capture preset is refused: %s" % str(capture.get("reason","")))
	server.handle(1,{"type":"set_automation_settings","settings":{"training":{"preset":"attack"}}})
	var started := start_run(server)
	check(started.ok and automation(server,"alice").running,"with 普通攻击 the leader's 自动练级 starts %s" % str(started))
	check(server.party.members("alice").size()==3,"the party stays together")
	await close(server)

## The leader's run meets troops; everyone enters each battle; Bob (自动战斗)
## never holds a turn up; Cid (by hand) gets the 45 s timer; the run goes on
## to the next troop and the members are in it too.
func selection_context() -> void:
	var made:=party_hub()
	var server=made[0]
	var backend=server.backends.alice
	backend.session.grant_starter_pets();backend.session.select_pet(0);backend.session.gm_raise_level(0,20)
	var actual: Dictionary=backend.training_reward_context.call()
	check(actual.get("party",false) and actual.players==3 and actual.active_pets==1 and actual.share_exp,"training estimate reads the real three-player party and participating pet")
	var chooser=preload("res://server/training_troops.gd").new()
	chooser.prepare(backend.encounter_catalog,100,Vector2i(637,493),backend.session.snapshot(),{"xp":10},false,false,actual)
	var deadline:=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
	while not chooser.ready and Time.get_ticks_msec()<deadline:chooser.advance(1000);await process_frame
	var row: Dictionary={}
	for value in chooser.rows:
		if int(value.group_id)==88:row=value
	check(not row.is_empty() and is_equal_approx(float(row.expected_xp),1.5),"real shared party uses target Lv20 gap rule: each Lv1 enemy awards 1 at 10x, mean count1.5")
	server.handle(1,{"type":"party_share_exp","on":false})
	check(start_run(server).ok,"unshared-party training begins validation")
	var run=automation(server,"alice")
	run.step()
	check(not run.running and not backend.battle_open and run.stop_reason.contains("按击杀归属"),"unshared party pauses selection clearly rather than inventing pre-battle kill credit")
	await close(server)

func leader_run() -> void:
	var made := party_hub()
	var server = made[0]
	var wire: Wire = made[1]
	var set: Dictionary = server.handle(2,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	check(set.ok and not server.party_auto("bob").is_empty() and server.party_auto("cid").is_empty(),"Bob turns on 组队自动战斗 (a profile setting); Cid does not")
	check(start_run(server).ok,"Alice starts 自动练级")
	var alice = automation(server,"alice")
	check(drive(server,func():return server.backends.alice.battle_open),"her run meets a troop")
	var entry := entry_of(server,"alice")
	check(entry.get("ids",[])==["alice","bob","cid"],"it is a party battle with Bob and Cid in it")
	check(server.backends.bob.battle_open and server.backends.cid.battle_open,"both members' backends hold it")
	var session = entry.session
	check(session.auto_slots.has(1) and session.auto_policies.has(1) and not session.auto_slots.has(2),"Bob's slot plays from his preset; Cid's does not")
	alice.step()
	check(session.has_command(0) and session.waiting_slots()==[2],"Alice's run sent her command at once; the turn waits only for Cid")
	check(alice.party_waiting() and not alice.busy(),"the run waits for Cid and spends no frame budget meanwhile")
	var turn := int(session._state.turn)
	for i in range(20):alice.step()
	check(int(session._state.turn)==turn and int(alice.turns)==1,"stepping on changes nothing while it waits")
	battle_now += 44000
	server.party_battles.tick()
	check(int(session._state.turn)==turn,"after 44 s the turn still waits")
	battle_now += 1000
	server.party_battles.tick()
	var events: Array = server.backends.cid.battle.snapshot().events
	check(int(session._state.turn)==turn+1 or not bool(session._state.active),"at 45 s the timer resolves it")
	check(events.any(func(line):return str(line).contains("超时未下指令，自动攻击")) and not events.any(func(line):return str(line).contains("Bob超时")),"Cid timed out; Bob, commanding from his preset, never does: %s" % str(events))
	check(str(session._last_actions.get(1,""))=="attack","Bob's slot attacked")
	# Cid answers by hand from now on; the battle ends and the run meets the next troop.
	check(drive(server,func():return not bool(session._state.active),[3]),"the battle is won")
	check(drive(server,func():return int(alice.battles)>=1 and server.backends.alice.battle_open,[3]),"the run closes it and meets the next troop")
	var second := entry_of(server,"alice")
	check(second.get("ids",[])==["alice","bob","cid"] and second!=entry,"Bob and Cid are in the new battle too, though their devices never closed the last one")
	check(wire.of(2,"battle_closed").size()>=1 and wire.of(2,"battle_started").size()>=2,"Bob's devices saw the last battle close and the new one start")
	check(int(alice.earned_xp)>0,"the run counts the experience of its party battles (%d)" % int(alice.earned_xp))
	check(int(server.backends.bob.session._profile.player.xp)>0 and int(server.backends.cid.session._profile.player.xp)>0,"and each member was paid on their own save")
	# Bob at his 停机线 with a 回复药: his preset drinks it.
	var bob_line := int(server.backends.bob.automation.profile_settings().hp)
	var ally: Dictionary = second.session._state.allies[0]
	ally.hp = 1
	var potions := int(ally.get("potions",0))
	check(potions>0 and bob_line==10,"Bob carries 回复药 (%d) and a 10 %% 停机线" % potions)
	check(str(second.session._auto_command(1).action)=="item","at his line his preset uses a 回复药")
	ally.hp = 4000
	check(str(second.session._auto_command(1).action)=="attack","above it, it attacks")
	server.handle(1,{"type":"auto_stop"})
	await close(server)

## Between troops the leader's run checks every member at their own 停机线:
## an auto member drinks 回复药 first; a member who is still at the line (a
## fallen member got up with 1 HP) stops the run, as the leader's own does.
func healing() -> void:
	var made := party_hub()
	var server = made[0]
	server.handle(2,{"type":"set_automation_settings","settings":{"party":{"auto":true}}})
	give_pet(server,"bob",true)
	give_pet(server,"cid",false)
	check(start_run(server).ok,"Alice starts 自动练级")
	var alice = automation(server,"alice")
	# Between troops: Bob (自动战斗) and Cid (by hand) got up with 1 HP.
	var bob: Dictionary = server.backends.bob.session._profile
	var cid: Dictionary = server.backends.cid.session._profile
	bob.player.max_hp = 100
	bob.player.hp = 1
	bob.inventory.potion = 2
	bob.pets[0].hp = 1
	cid.player.max_hp = 100
	cid.player.hp = 1
	cid.inventory.potion = 1
	check(drive(server,func():return server.backends.alice.battle_open,[3]),"the party is healed and the run meets a troop anyway")
	check(int(bob.inventory.potion)==1 and int(bob.player.hp)==31 and int(cid.inventory.potion)==0 and int(cid.player.hp)==31,"each drank one 回复药 out of battle (1 → 31 HP, above their 10 % line)")
	check(int(bob.pets[0].hp)==int(bob.pets[0].max_hp) and int(bob.inventory.healing_charm)==1,"Bob's 恢复护符 healed his pet, and is not used up")
	# In the battle: the 恢复护符 works for its owner; 镜子的精灵 stays refused.
	var session = entry_of(server,"alice").session
	var refused := send(server,3,"heal_pet")
	check(not refused.ok and str(refused.reason)=="没有恢复护符。","Cid, without a 恢复护符, cannot use one: %s" % str(refused.get("reason","")))
	var mirror := send(server,3,"mirror_self")
	check(not mirror.ok and str(mirror.reason).contains("镜子的精灵"),"镜子的精灵 is still refused in a party battle")
	session._state.ally_pets[0].hp = 100
	check(bool(server.backends.bob.battle.snapshot().healing_available) and str(session._auto_command(1).action)=="heal_pet","Bob's pet at half hp or less: his preset uses the 恢复护符, as solo 自动练级 does")
	# Cid has sent his command already; Alice, at her 停机线, is the last.
	session._state.player_hp = 1
	var potions := int(session._state.potions)
	alice.step()
	check(alice.running and str(alice.turn_text).contains("喝回复药") and str(session._last_actions.get(0,""))=="item","Alice at her 停机线 in the battle drinks a 回复药 instead of stopping the party")
	check(int(session._state.potions)==potions-1,"one 回复药 fewer")
	var lines: Array = server.backends.bob.battle.snapshot().events
	check(lines.any(func(line):return str(line).begins_with("恢复护符：你为")),"and Bob's charm healed his pet in that turn: %s" % str(lines))
	session._state.player_hp = 5000
	check(drive(server,func():return not server.backends.alice.battle_open,[3]),"the battle ends and closes")
	# Cid got up with 1 HP again and has no 回复药 left: only then the run stops.
	server.backends.alice.session._profile.player.hp = 5000
	bob.player.hp = 100
	cid.player.hp = 1
	cid.inventory.potion = 0
	alice.step()
	check(not alice.running and str(alice.stop_reason)=="队友Cid：玩家体力达到停机线，回复药已用完","nothing heals Cid: the run stops and says why: %s" % str(alice.stop_reason))
	await close(server)

## A pet (the starter's first) as the battle pet, 500 hp, and a 恢复护符 or none.
func give_pet(server, id: String, charm: bool) -> void:
	server.backends[id].session.set_automation_settings({"training":{"borrow_troops":false}}) # Local turn/healing fixtures; borrowed LAN is tested separately.
	var session = server.backends[id].session
	session.grant_starter_pets()
	session.select_pet(0)
	var pet: Dictionary = session._profile.pets[0]
	pet.hp = 500
	pet.max_hp = 500
	pet.attack = 50
	session._profile.inventory.healing_charm = 1 if charm else 0

## The run stops when the leader stops it, a member leaves or is kicked, the
## party disbands, or the leader's last device disconnects.
func stops() -> void:
	var made := party_hub()
	var server = made[0]
	var wire: Wire = made[1]
	var alice = automation(server,"alice")
	start_run(server)
	server.handle(1,{"type":"auto_stop"})
	check(not alice.running,"the leader stops it")
	start_run(server)
	check(drive(server,func():return server.backends.alice.battle_open),"a battle is open")
	server.handle(3,{"type":"party_leave"})
	check(not alice.running and str(alice.stop_reason)=="Cid离开了队伍，自动练级已停止。","Cid leaves: the run stops (%s)" % str(alice.stop_reason))
	check(wire.of(1,"auto_event").any(func(message):return str(message.detail.kind)=="battle_stopped"),"Alice's devices hear it stopped")
	server.backends.alice.abandon_battle()
	await close(server)
	made = party_hub()
	server = made[0]
	alice = automation(server,"alice")
	start_run(server)
	server.handle(1,{"type":"party_kick","id":"bob"})
	check(not alice.running and str(alice.stop_reason).contains("踢出了Bob"),"a kick stops it: %s" % str(alice.stop_reason))
	start_run(server)
	check(alice.running,"it starts again with Cid")
	server.handle(1,{"type":"party_disband"})
	check(not alice.running and str(alice.stop_reason)=="队伍已解散，自动练级已停止。","disbanding stops it")
	await close(server)
	made = party_hub()
	server = made[0]
	alice = automation(server,"alice")
	start_run(server)
	server.disconnect_connection(1)
	check(not alice.running and str(alice.stop_reason)=="队长已离线，自动练级已停止。","the leader's last device disconnecting stops it")
	check(not server.party.in_party("bob"),"and disbands the party, as in phase 3")
	await close(server)
	# The whole party falls: the run ends, everyone is in the village.
	made = party_hub()
	server = made[0]
	alice = automation(server,"alice")
	for connection in [1,2,3]:server.handle(connection,{"type":"set_automation_settings","settings":{"training":{"hp":1}}})
	for id in ["alice","bob","cid"]:
		setup(server,id,10)
		server.backends[id].session._profile.player.max_hp = 10
		server.backends[id].session._profile.player.attack = 1
		server.backends[id].session._profile.player.defence = 0
	start_run(server)
	check(drive(server,func():return not alice.running,[2,3],3000),"a run whose party is too weak ends (after %d battles)" % int(alice.battles))
	check(str(alice.stop_reason)=="全队倒下，自动练级已停止。","with 「全队倒下」: %s" % str(alice.stop_reason))
	check(["alice","bob","cid"].all(func(id):return server.backends[id].automation.position_map==1000),"everyone is back in the village")
	await close(server)

## With every member on 自动战斗 nothing waits: compact frames run battle after
## battle within the frame budget; and the budget is only counted while the
## run has something to do.
func budget() -> void:
	var made := party_hub()
	var server = made[0]
	for connection in [2,3]:server.handle(connection,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	check(start_run(server).ok,"Alice starts compact 自动练级 with two auto members")
	var alice = automation(server,"alice")
	check(server.share_budget()==1 and alice.busy(),"the run takes the frame budget")
	for frame in range(60):
		alice.tick_battle(0.016)
		server.party_battles.tick()
		if int(alice.battles)>=3:break
	check(int(alice.battles)>=3 and alice.running,"compact frames fight several party battles without waiting on any device (%d)" % int(alice.battles))
	check(int(server.backends.bob.session._profile.player.xp)>0,"the members are paid each time")
	server.handle(3,{"type":"set_automation_settings","settings":{"party":{"auto":false}}})
	check(drive(server,func():return alice.party_waiting()),"with Cid back to commanding by hand the run soon waits for him")
	check(server.share_budget()==0,"a waiting run does not count as busy")
	server.handle(1,{"type":"auto_stop"})
	server.backends.alice.abandon_battle()
	await close(server)

## A server restart ends the party (it is not saved); the leader's 自动练级
## resumes on its own at its spot, as any 自动练级 does.
func resume() -> void:
	var made := party_hub()
	var server = made[0]
	var folder: String = server.accounts.path.get_base_dir()
	check(start_run(server).ok,"Alice starts 自动练级 in the party")
	await close(server)
	var restarted = new_hub(folder)
	var backend = restarted.backends.get("alice")
	check(backend!=null and not backend.automation.pending_resume.is_empty(),"after a restart her run is waiting to resume")
	if backend!=null:
		backend.automation.try_resume()
		check(backend.automation.running and not restarted.party.in_party("alice"),"and goes on alone: the party is gone (%s)" % str(backend.automation.stop_reason))
		backend.automation.stop("test")
	restarted.shut_down()
	restarted.queue_free()
	await process_frame

## A real game client as the member Bob: 自动战斗 and 快速战斗 in his party
## list, the status line instead of the battle view, 查看战斗, and the finished
## battle closed by his device.
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
	setup(server,"alice")
	setup(server,"bob")
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
	var panel = game.party_panel
	check(await Wait.until(self,func():return panel.list.find_child("PartyAuto",true,false)!=null),"his party list has 自动战斗 and 快速战斗")
	var auto_box: CheckBox = panel.list.find_child("PartyAuto",true,false)
	var compact_box: CheckBox = panel.list.find_child("PartyCompact",true,false)
	# The panel syncs the switches from the profile a frame after building them.
	check(await Wait.until(self,func():return not auto_box.button_pressed and compact_box.button_pressed and compact_box.disabled),"自动战斗 off; 快速战斗 on by default, waiting for 自动战斗")
	auto_box.button_pressed = true
	check(await Wait.until(self,func():return not server.party_auto("bob").is_empty() and not compact_box.disabled and compact_box.button_pressed),"自动战斗 reaches his profile on the server, with 快速战斗 on")
	var effective := func():return bool(preload("res://scripts/automation_settings.gd").effective(server.backends.bob.session._profile.automation_settings).party.compact)
	compact_box.button_pressed = false
	check(await Wait.until(self,func():return not panel.party_setting("compact") and not effective.call() and not compact_box.button_pressed),"he can turn 快速战斗 off")
	compact_box.button_pressed = true
	check(await Wait.until(self,func():return panel.party_setting("compact") and effective.call() and compact_box.button_pressed),"and on again")
	server.handle(900001,{"type":"begin_battle","enemy_count":2})
	var view = game.battle_view
	check(await Wait.until(self,func():return game.state.battle_open and panel.auto_line.visible),"Alice meets enemies: Bob sees the status line")
	check(not view.visible and panel.auto_text.text.begins_with("组队战斗 · 自动 · 第 1 回合"),"not the battle view: %s" % panel.auto_text.text)
	check(server.party_battles.fighting.bob.session.auto_slots.has(1),"his slot commands itself from his preset")
	var state: Dictionary = server.backends.alice.battle.snapshot()
	server.handle(900001,{"type":"battle_command","action":"attack","target":0,"battle_id":state.battle_id,"turn":state.turn,"slot":0})
	check(await Wait.until(self,func():return panel.auto_text.text.contains("第 2 回合") or not bool(game.state.battle.get("active",true))),"Alice's command alone resolves the turn; his line follows it: %s" % panel.auto_text.text)
	panel.watch_button.pressed.emit()
	check(await Wait.until(self,func():return view.visible and not panel.auto_line.visible),"查看战斗 opens this battle in the battle view")
	if bool(game.state.battle.get("active",false)):
		check(await Wait.until(self,func():return view.command_phase=="waiting" and view.hint.text=="自动战斗中…"),"which shows 自动战斗中… instead of his command bar")
	server.backends.alice.abandon_battle()
	check(await Wait.until(self,func():
		game.return_from_battle()
		return not view.visible and not game.state.battle_open),"that battle ends and he returns to the map")
	server.handle(900001,{"type":"begin_battle","enemy_count":1})
	check(await Wait.until(self,func():return game.state.battle_open and panel.auto_line.visible and not view.visible),"the next battle is compact again")
	server.backends.alice.abandon_battle()
	check(await Wait.until(self,func():return not game.state.battle_open and not panel.auto_line.visible),"when it ends his device closes it by itself")
	check(not server.backends.bob.battle_open,"on the server too")
	game.queue_free()
	await process_frame
	ws.stop()
	server.shut_down()
	server.queue_free()
	await process_frame
