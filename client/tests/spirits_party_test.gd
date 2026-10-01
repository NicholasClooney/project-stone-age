extends SceneTree
## The healing 精灵 in LAN party battles and in automation
## (docs/reverse-engineering/magic-and-mp.md, docs/development/lan-profiles.md):
## a member heals the leader and revives a fallen teammate from its own 气力,
## each device sees the cast from its own seat, 气力 is settled on each save;
## 自动练级 (solo and a party leader's) casts a spirit before a 回复药 and falls
## back to the 回复药 (or a stop) without 气力; a member's 组队自动战斗 preset
## heals the lowest teammate; between troops a field spirit comes first.
##
## Functional core for real: the hub, backends, GameSessions, the party battle
## with its seeded rng and the real runners (stepped by hand). Faked: the
## clocks and connections (plain ids).
const ProfileHub = preload("res://server/profile_hub.gd")
const Backend = preload("res://server/backend.gd")
const TroopArt = preload("res://server/troop_art.gd")
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
	dir = "user://spirits-party-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	solo_run()
	await manual_party()
	await party_automation()
	remove_tree(dir)
	print("SPIRITS PARTY: %d failures" % failures)
	quit(1 if failures else 0)

# ---- solo 自动练级 ---------------------------------------------------------------

func choose_seed(backend, count: int) -> int:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(10000):
		rng.seed = seed_value
		var valid := true
		for i in range(count):
			var troop: Dictionary = backend.encounter_catalog.roll(FIELD,CELL,rng)
			if troop.is_empty() or not TroopArt.can_render(troop.enemies):valid = false;break
		if valid:return seed_value
	return -1

func solo_run() -> void:
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	for command in [{"type":"gm_raise_level","index":-1,"target":10},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":100},{"type":"gm_heal"},{"type":"gm_grant_spirits"},{"type":"equip_item","item":"haru_armor"}]:
		backend.handle(command)
	var session = backend.session
	session.set_free_spirits(false)
	check(session.spirits().has("body") and int(session.player_mp())==100,"the solo player wears 哈鲁Lv1铠2 (治愈) with 气力 100")
	backend.encounter_rng.seed = choose_seed(backend,3)
	backend.automation.client_attached = false
	var player: Dictionary = session._profile.player
	player.max_hp = 1000
	player.hp = 50
	var reply: Dictionary = backend.handle({"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y],"settings":{"select_troops":false,"borrow_troops":false,"compact":false,"limit":5,"hp":20,"speed":8.0,"preset":"attack","level":120}})
	check(reply.ok and backend.automation.running,"自动练级 starts")
	backend.automation.step()
	check(backend.battle_open and int(session._profile.player.hp)>200 and int(session.player_mp())<100,"between troops, at its 20 %% line, the run casts 治愈 outside battle first, then meets the troop (体力 %d, 气力 %d)" % [int(session._profile.player.hp),session.player_mp()])
	var mp_before := int(backend.battle.snapshot().player_mp)
	backend.battle._state.player_hp = 10
	backend.battle._state.player_max_hp = 1000
	backend.automation.step()
	var state: Dictionary = backend.battle.snapshot()
	check(backend.automation.running and int(state.turn)==1 and int(state.player_mp)==mp_before-5 and "治愈的精灵" in str(state.events),"in battle at the line it casts 治愈 instead of stopping (%s)" % str(state.events))
	check("用精灵补血" in backend.automation.turn_text,"the status line says so: %s" % backend.automation.turn_text)
	backend.battle._state.player_hp = 10
	backend.battle._state.player_mp = 4
	backend.automation.step()
	check(not backend.automation.running and backend.automation.stop_reason=="玩家体力达到停机线，气力不足以用精灵","without 5 气力 the solo run stops at the line as before, saying why: %s" % backend.automation.stop_reason)
	backend.handle({"type":"set_automation_settings","settings":{"training":{"spirit":false}}})
	check(not bool(backend.automation.profile_settings().spirit),"用精灵补血 can be turned off (training.spirit)")
	backend.queue_free()

# ---- a LAN party ------------------------------------------------------------------

class Wire extends RefCounted:
	var messages: Array = []
	func take(connection: int, message: Dictionary) -> void:
		messages.append([connection,message])
	func of(connection: int, type: String) -> Array:
		return messages.filter(func(item):return item[0]==connection and str(item[1].type)==type).map(func(item):return item[1])

func party_hub(names: Array = ["Alice","Bob","Cid"]) -> Array:
	_hubs += 1
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
	for id in server.backends:
		server.backends[id].session.set_free_spirits(false)
		var player: Dictionary = server.backends[id].session._profile.player
		player.level = 12
		player.hp = 5000
		player.max_hp = 5000
		player.attack = 1
		player.defence = 50
		player.speed = 40
		player.gold = 100000
	return [server,wire]

## Buys and wears pieces of spirit equipment on `id`'s own save.
func wear(server, id: String, items: Array) -> void:
	for item in items:
		server.backends[id].session.buy_item(item)
		server.backends[id].session.equip_item(item)

func live(server, id: String) -> Dictionary:
	return server.backends[id].battle.snapshot()

func entry_of(server, id: String) -> Dictionary:
	return server.party_battles.fighting.get(id,{})

func send(server, connection: int, action: String, target: int = -1) -> Dictionary:
	var state := live(server,server.profile_of(connection))
	return server.handle(connection,{"type":"battle_command","action":action,"target":target,"battle_id":state.battle_id,"turn":state.turn,"slot":state.party_slot})

func close(server) -> void:
	server.shut_down()
	server.queue_free()
	await process_frame

func manual_party() -> void:
	var made := party_hub()
	var server = made[0]
	var wire: Wire = made[1]
	wear(server,"bob",["freya_robe","koyala_charm"])
	server.backends.alice.session._profile.player.hp = 1000
	var fight: Dictionary = server.handle(1,{"type":"begin_battle","enemy_count":3})
	var entry := entry_of(server,"alice")
	check(fight.ok and entry.get("ids",[])==["alice","bob","cid"],"Alice meets enemies: a party battle for all three")
	var bob_view := live(server,"bob")
	check(bob_view.get("spirits",{}).has("body") and bob_view.spirits.has("amulet") and int(bob_view.player_mp)==100,"Bob's own view shows his 滋润 and 复活 spirits and his 气力 100")
	check(live(server,"alice").get("spirits",{}).is_empty() and int(live(server,"alice").player_mp)==100,"Alice's view shows her own (none), not Bob's")
	# Bob heals Alice: on his screen she is ally 0, target code 2.
	check(send(server,2,"spirit:body",2).ok,"Bob sends 滋润的精灵 on Alice (ally 0 on his screen)")
	send(server,1,"attack",0)
	send(server,3,"attack",0)
	var canonical: Dictionary = entry.session.snapshot()
	check(int(canonical.turn)==1 and int(canonical.player_hp)>1000 and int(canonical.player_hp)<=1071 and int(canonical.allies[0].mp)==92,"the turn resolves: Alice is healed 58..71 (体力 %d) and Bob paid 8 气力" % int(canonical.player_hp))
	var bob_frame: Dictionary = live(server,"bob").turn_frames.filter(func(f):return f.has("spirit"))[0]
	check(bob_frame.actor=="player" and bob_frame.spirit.caster.kind=="player" and bob_frame.spirit.heals[0].kind=="ally" and int(bob_frame.spirit.heals[0].index)==0,"Bob's screen: he cast it, on ally 0 (Alice)")
	var alice_frame: Dictionary = live(server,"alice").turn_frames.filter(func(f):return f.has("spirit"))[0]
	check(alice_frame.actor=="ally" and int(alice_frame.ally_index)==0 and alice_frame.spirit.heals[0].kind=="player","Alice's screen: ally 0 (Bob) healed her")
	var cid_frame: Dictionary = live(server,"cid").turn_frames.filter(func(f):return f.has("spirit"))[0]
	check(cid_frame.spirit.caster.kind=="ally" and int(cid_frame.spirit.caster.index)==1 and cid_frame.spirit.heals[0].kind=="ally" and int(cid_frame.spirit.heals[0].index)==0,"Cid's screen: ally 1 (Bob) healed ally 0 (Alice)")
	check(int(live(server,"bob").player_mp)==92 and int(live(server,"alice").player_mp)==100,"each view's 气力 is its own player's")
	# Cid falls; Bob's 复活精灵 gets him up (Cid is ally 1 on Bob's screen: code 4).
	entry.session._state.allies[1].hp = 0
	entry.session._check_end()
	check(entry.session.waiting_slots()==[0,1],"the fallen Cid is not waited for")
	check(send(server,2,"spirit:amulet",4).ok,"Bob sends 复活精灵 on the fallen Cid")
	send(server,1,"attack",0)
	canonical = entry.session.snapshot()
	check(int(canonical.allies[1].hp)>=90 and int(canonical.allies[1].hp)<=110 and int(canonical.allies[0].mp)==72,"Cid is up with 90..110 体力 (%d); Bob paid 20 气力" % int(canonical.allies[1].hp))
	check(entry.session.slot_standing(2) and not entry.session._fallen.has(2),"Cid stands again and commands next turn")
	# Too little 气力: Bob's command is refused with the reason.
	entry.session._state.allies[0].mp = 3
	var refused := send(server,2,"spirit:body",2)
	check(not refused.ok and str(refused.reason)=="气力不足。","with 3 气力 Bob's 滋润 is refused: %s" % str(refused.get("reason","")))
	entry.session._state.allies[0].mp = 50
	# Everyone leaves: each save keeps its own 气力.
	server.handle(1,{"type":"battle_escape_dev"})
	check(int(server.backends.bob.session._profile.player.mp)==50 and int(server.backends.alice.session._profile.player.mp)==100,"the battle settles Bob's 气力 (50) on his save and Alice's on hers")
	check(wire.of(2,"battle_turn").size()>0,"Bob's devices were sent the turns")
	await close(server)

func party_automation() -> void:
	var made := party_hub()
	var server = made[0]
	wear(server,"alice",["haru_armor"])
	wear(server,"bob",["freya_robe"])
	server.handle(2,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	server.handle(3,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	check(bool(server.party_auto("bob").get("spirit",false)),"Bob's 组队自动战斗 preset carries 用精灵补血 (on by default)")
	server.handle(1,{"type":"report_position","map_id":FIELD,"cell":[CELL.x,CELL.y],"map_changed":true,"client":"c1"})
	# Between troops: Bob at his 10 % line drinks no 回复药 while his 滋润 can heal him.
	var bob: Dictionary = server.backends.bob.session._profile
	bob.player.hp = 100
	bob.inventory.potion = 3
	check(server.handle(1,{"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y],"speed":8}).ok,"Alice starts 自动练级")
	var alice = server.backends.alice.automation
	for i in range(50):
		if server.backends.alice.battle_open:break
		alice.step()
	check(server.backends.alice.battle_open,"the run meets a troop")
	check(int(bob.inventory.potion)==3 and int(bob.player.mp)<100 and int(bob.player.hp)>100,"between troops the party guard healed Bob with his field 滋润 first, no 回复药 (体力 %d, 气力 %d)" % [int(bob.player.hp),int(bob.player.mp)])
	var entry := entry_of(server,"alice")
	var session = entry.session
	# Bob's preset: Alice (ally 0 on his screen) at the line → 滋润 on her.
	session._state.player_hp = 300
	var command: Dictionary = session._auto_command(1)
	check(str(command.action)=="spirit:body" and int(command.target)==2 and str(command.ref.kind)=="player","Bob's preset heals the lowest teammate at the line: Alice (%s)" % str(command))
	session._state.player_hp = 5000
	session._state.allies[1].hp = 200
	command = session._auto_command(1)
	check(str(command.action)=="spirit:body" and str(command.ref.kind)=="ally" and int(command.ref.index)==1,"or Cid when he is the one at the line")
	session._state.allies[1].hp = 5000
	check(str(session._auto_command(1).action)=="attack","nobody at the line: it attacks")
	# The leader's own run at its line: 治愈 before a 回复药, the 回复药 without 气力.
	# The troop is random: keep it standing for the two turns checked below.
	for enemy in session._state.enemies:
		enemy.max_hp = 100000
		enemy.hp = 100000
	session._state.player_hp = 100
	var potions := int(session._state.potions)
	var turn := int(session._state.turn)
	alice.step()
	check(int(session._state.turn)==turn+1 and str(session._last_actions.get(0,""))=="spirit:body" and int(session._state.potions)==potions and int(session._state.player_mp)==95,"Alice's run casts 治愈 at her line, not a 回复药 (the turn resolves: Bob and Cid are automatic)")
	session._state.player_hp = 100
	session._state.player_mp = 2
	alice.step()
	check(int(session._state.turn)==turn+2 and str(session._last_actions.get(0,""))=="item" and int(session._state.potions)==potions-1,"with 2 气力 her run drinks a 回复药 instead")

	server.handle(1,{"type":"auto_stop"})
	await close(server)
