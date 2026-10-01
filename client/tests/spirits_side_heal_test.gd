extends SceneTree
## 全体补血 (training.side_heal, default 50): in automatic battles a worn
## 恩惠的精灵 heals the whole side as soon as anyone on it is below that
## percent (exactly at it is not). Solo 自动练级, a party leader's run and
## members' 组队自动战斗 presets; one 恩惠 a turn in a party (the leader's
## command, then the automatic slots in slot order); without 恩惠 the stop
## line logic stays; 气力 counts when 精灵不耗气力 is off; the setting saves;
## the 自动练级 window has the control.
##
## Functional core for real: backends, the hub, GameSessions, seeded battles
## and the real runners stepped by hand. Faked: clocks and connections.
const ProfileHub = preload("res://server/profile_hub.gd")
const Backend = preload("res://server/backend.gd")
const TroopArt = preload("res://server/troop_art.gd")
const Policy = preload("res://scripts/battle_auto_policy.gd")
const Session = preload("res://server/game_session.gd")
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
	dir = "user://spirits-side-heal-test-%d" % OS.get_process_id()
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	policy()
	settings()
	solo()
	await party()
	await ui()
	remove_tree(dir)
	print("SPIRITS SIDE HEAL: %d failures" % failures)
	quit(1 if failures else 0)

const TEO := {"body":{"kind":"recovery","target":8,"mp":0,"field":1}}
const FREYA := {"body":{"kind":"recovery","target":1,"mp":0,"field":0}}

func policy() -> void:
	var state := {"player_hp":50,"player_max_hp":100,"player_mp":100,"spirits":TEO}
	check(Policy.spirit_choice(state,10,false,50).is_empty(),"exactly 50 % does not cast 恩惠")
	state.player_hp = 49
	check(Policy.spirit_choice(state,10,false,50)=={"action":"spirit:body","target":20},"49 % casts 恩惠 on the whole side")
	check(Policy.spirit_choice(state,10,false,0).is_empty(),"threshold 0 turns 全体补血 off")
	check(Policy.spirit_choice(state,10,true,50,true).is_empty(),"another caster already casting 恩惠 this turn: none")
	state.player_hp = 100
	state.pet = {"hp":10,"max_hp":100}
	state.pet_hp = 10
	state.pet_max_hp = 100
	check(not Policy.spirit_choice(state,10,false,50).is_empty(),"the pet below counts")
	state.pet_hp = 0
	check(Policy.spirit_choice(state,10,false,50).is_empty(),"a fallen pet does not (恩惠 does not revive)")
	state.erase("pet")
	state.ride_pet = 0
	state.pets = [{"hp":30,"max_hp":100}]
	check(not Policy.spirit_choice(state,10,false,50).is_empty(),"the mount below counts")
	state.pets = [{"hp":100,"max_hp":100}]
	state.allies = [{"hp":40,"max_hp":100},{"hp":1,"max_hp":100,"escaped":true}]
	state.ally_pets = [{},{}]
	check(not Policy.spirit_choice(state,10,true,50).is_empty(),"a teammate below counts")
	state.allies[0].hp = 100
	check(Policy.spirit_choice(state,10,true,50).is_empty(),"an escaped teammate does not")
	state.ally_pets = [{"hp":20,"max_hp":100},{}]
	check(not Policy.spirit_choice(state,10,true,50).is_empty(),"a teammate's pet below counts")
	# Without 恩惠 the stop line logic stays: 滋润 only at the line.
	var freya := {"player_hp":40,"player_max_hp":100,"player_mp":100,"spirits":FREYA}
	check(Policy.spirit_choice(freya,10,false,50).is_empty(),"without 恩惠, 40 % (above the 10 % line) casts nothing")
	freya.player_hp = 9
	check(Policy.spirit_choice(freya,10,false,50)=={"action":"spirit:body","target":0},"and at the line 滋润 heals as before")
	# 气力: a 20 气力 恩惠 with 19 left is not cast.
	var costly := {"player_hp":10,"player_max_hp":100,"player_mp":19,"spirits":{"body":{"kind":"recovery","target":8,"mp":20,"field":1}}}
	check(Policy.spirit_choice(costly,10,false,50).is_empty(),"with 精灵不耗气力 off and 19 气力 the 20 气力 恩惠 is not cast")

func settings() -> void:
	var session := Session.new()
	check(int(preload("res://scripts/automation_settings.gd").runner_settings(session.automation_settings(),1).side_heal)==50,"全体补血 defaults to 50 %")
	check(session.set_automation_settings({"training":{"side_heal":30}}),"it is set per character (training.side_heal)")
	check(not session.set_automation_settings({"training":{"side_heal":101}}),"above 100 is refused")
	var path := dir.path_join("settings.json")
	session.save_game(path)
	var loaded := Session.new()
	check(loaded.load_game(path) and int(loaded.automation_settings().training.side_heal)==30,"and saved with the character")

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

func solo() -> void:
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	for command in [{"type":"gm_raise_level","index":-1,"target":10},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":100},{"type":"gm_heal"},{"type":"gm_grant_spirits"},{"type":"equip_item","item":"teo_robe"}]:
		backend.handle(command)
	backend.encounter_rng.seed = choose_seed(backend,3)
	backend.automation.client_attached = false
	backend.session._profile.player.max_hp = 1000
	backend.session._profile.player.hp = 1000
	check(backend.handle({"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y],"settings":{"select_troops":false,"compact":false,"limit":5,"hp":10,"speed":8.0,"preset":"attack","level":120}}).ok,"solo 自动练级 starts wearing 提欧Lv1服2")
	backend.automation.step()
	check(backend.battle_open,"it meets a troop")
	var battle = backend.battle
	battle._state.player_max_hp = 1000
	battle._state.player_hp = 500
	backend.automation.step()
	var state: Dictionary = battle.snapshot()
	check(int(state.turn)==1 and str(state.last_player_command)=="attack","at exactly 50 % it attacks")
	battle._state.player_hp = 490
	backend.automation.step()
	state = battle.snapshot()
	check(int(state.turn)==2 and str(state.last_player_command)=="spirit:body" and "恩惠的精灵" in str(state.events),"at 49 %% it casts 恩惠 (above the 10 %% stop line): %s" % str(state.events))
	# 精灵不耗气力 off: the 20 气力 counts.
	backend.automation.stop("test")
	backend.handle({"type":"battle_escape_dev"})
	backend.close_battle()
	backend.handle({"type":"set_free_spirits","on":false})
	backend.session._profile.player.mp = 19
	backend.session._profile.player.hp = 1000
	backend.handle({"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y],"settings":{"select_troops":false,"compact":false,"limit":5,"hp":10,"speed":8.0,"preset":"attack","level":120}})
	backend.automation.step()
	battle = backend.battle
	battle._state.player_max_hp = 1000
	battle._state.player_hp = 400
	backend.automation.step()
	state = battle.snapshot()
	check(backend.battle_open and int(state.turn)==1 and str(state.last_player_command)=="attack" and int(state.player_mp)==19,"with 精灵不耗气力 off and 19 气力 it attacks instead")
	backend.automation.stop("test")
	backend.queue_free()

# ---- a LAN party ------------------------------------------------------------------

func party_hub() -> Array:
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
	var names := ["Alice","Bob","Cid"]
	var cells := [Vector2i(81,90),Vector2i(80,90),Vector2i(81,91)]
	for i in range(3):
		server.handle(i+1,{"type":"create_profile","name":names[i],"pin":"%d%d%d%d" % [i+1,i+1,i+1,i+1]})
		server.handle(i+1,{"type":"report_position","map_id":1000,"cell":[cells[i].x,cells[i].y],"client":"c%d" % (i+1)})
	server.handle(2,{"type":"party_join","facing":EAST})
	server.handle(3,{"type":"party_join","facing":2})
	for id in server.backends:
		var player: Dictionary = server.backends[id].session._profile.player
		player.level = 12
		player.hp = 5000
		player.max_hp = 5000
		player.attack = 1
		player.defence = 50
		player.speed = 40
		player.gold = 100000
	return [server]

func wear(server, id: String, item: String) -> void:
	server.backends[id].session.buy_item(item)
	server.backends[id].session.equip_item(item)

func party() -> void:
	var server = party_hub()[0]
	for id in ["alice","bob","cid"]:wear(server,id,"teo_robe")
	for connection in [2,3]:server.handle(connection,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	check(int(server.party_auto("bob").get("side",0))==50,"a member's preset carries its own 全体补血 (50)")
	server.handle(1,{"type":"report_position","map_id":FIELD,"cell":[CELL.x,CELL.y],"map_changed":true,"client":"c1"})
	check(server.handle(1,{"type":"auto_start","kind":"battle","map_id":FIELD,"cell":[CELL.x,CELL.y],"speed":8}).ok,"Alice starts 自动练级")
	var alice = server.backends.alice.automation
	for i in range(50):
		if server.backends.alice.battle_open:break
		alice.step()
	var session = server.party_battles.fighting.get("alice",{}).get("session")
	check(session!=null,"the party meets a troop")
	# Members only: Cid's pet-less side is fine, Bob is at 49 %.
	session._state.allies[0].hp = 2450
	var bob: Dictionary = session._auto_command(1)
	check(str(bob.action)=="spirit:body" and str(bob.ref.kind)=="side","Bob's preset casts 恩惠 when he is below 50 %")
	session._commands[1] = bob
	check(str(session._auto_command(2).action)=="attack","Cid, after Bob in slot order, does not cast a second 恩惠 that turn")
	session._commands.clear()
	session._state.allies[0].hp = 2500
	check(str(session._auto_command(1).action)=="attack","at exactly 50 % nobody casts")
	# The leader's run: a teammate below the line is enough; the members then skip.
	session._state.allies[1].hp = 1000
	var turn := int(session._state.turn)
	alice.step()
	check(int(session._state.turn)==turn+1 and str(session._last_actions.get(0,""))=="spirit:body" and str(session._last_actions.get(1,""))=="attack" and str(session._last_actions.get(2,""))=="attack","Alice's run casts 恩惠 for Cid at 20 %; Bob and Cid attack that turn")
	check(int(session._state.allies[1].hp)>1000,"Cid is healed (体力 %d)" % int(session._state.allies[1].hp))
	server.handle(1,{"type":"auto_stop"})
	server.handle(1,{"type":"battle_escape_dev"})
	# Without 恩惠 a member keeps the stop line logic (滋润 on the lowest).
	server.shut_down()
	server.queue_free()
	await process_frame
	server = party_hub()[0]
	wear(server,"bob","freya_robe")
	server.handle(2,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	server.handle(1,{"type":"begin_battle","enemy_count":3})
	session = server.party_battles.fighting.get("alice",{}).get("session")
	session._state.player_hp = 2000
	check(str(session._auto_command(1).action)=="attack","without 恩惠, Alice at 40 % (above Bob's 10 % line) gets nothing")
	session._state.player_hp = 400
	var fallback: Dictionary = session._auto_command(1)
	check(str(fallback.action)=="spirit:body" and str(fallback.ref.kind)=="player","and at the line Bob's 滋润 heals her, as before")
	server.handle(1,{"type":"battle_escape_dev"})
	server.shut_down()
	server.queue_free()
	await process_frame

func ui() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.profile_persistence = false
	root.add_child(game)
	await process_frame
	var helper = game.training_helper
	helper.open_menu()
	await process_frame
	check(helper.side_heal!=null and int(helper.side_heal.value)==50 and helper.side_heal.get_parent()==helper.panel,"the 自动练级 window shows 全体补血 at 50 %")
	check("全体补血" in helper.side_heal.tooltip_text and "恩惠" in helper.side_heal.tooltip_text,"its tooltip explains it")
	helper.side_heal.value = 35
	helper.apply_settings()
	check(int(game.automation_settings().training.side_heal)==35,"Apply saves it on the character (%d)" % int(game.automation_settings().training.side_heal))
	helper.close_menu()
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null;game.queue_free()
	await process_frame
	await create_timer(0.5).timeout
