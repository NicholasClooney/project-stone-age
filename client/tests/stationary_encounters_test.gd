extends SceneTree
const Backend = preload("res://server/backend.gd")
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, note: String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func fixture():
	var b = Backend.new()
	b.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	b.encounter_rng.seed = 918
	return b
func start(b) -> bool:return b.handle({"type":"stationary_encounters","enabled":true}).ok
func tick(b, delta := 0.5):
	b.handle({"type":"stationary_keepalive"})
	b._process(delta)
func meet(b):
	for i in range(200):
		if b.battle_open:break
		tick(b)
	check(b.battle_open,"ordinary pressure eventually opens a real wild battle")
func finish(b, outcome: String):
	# Control actor strength, but resolve actual battle actions and settlement.
	b.battle._config.player_attack = 100000
	b.battle._config.player_defence = 100000
	if outcome=="defeat":
		b.battle._state.player_hp = 1;b.battle._config.player_defence = 0
		for enemy in b.battle._state.enemies:enemy.attack = 100000
	for i in range(100):
		if not b.battle.snapshot().active:break
		if outcome=="escaped":b.handle({"type":"battle_escape_dev"})
		else:
			var target := 0
			for j in range(b.battle._state.enemies.size()):
				if b.battle._state.enemies[j].hp>0:target=j;break
			b.handle({"type":"battle_command","action":"defend" if outcome=="defeat" else "attack","target":target})
	check(b.battle.snapshot().outcome==outcome,"real combat resolves "+outcome)
func run():
	var b = fixture()
	check(not b.stationary.running,"default off")
	check(not b.handle({"type":"stationary_encounters","enabled":1}).ok,"strict boolean")
	b.handle({"type":"report_position","map_id":1000,"cell":[80,90]})
	check(not start(b) and not b.stationary.snapshot(b).available,"safe village unavailable")
	b.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	b.handle({"type":"no_random_encounters","enabled":true})
	check(start(b) and not b.session._profile.no_random_encounters,"start turns no-encounters off")
	b.handle({"type":"no_random_encounters","enabled":true})
	check(not b.stationary.running,"no-encounters stops stationary")
	check(start(b),"restart")
	var reference = fixture()
	var events := [0]
	b.event.connect(func(_e):events[0]+=1)
	for i in range(200):
		if b.battle_open:break
		var before: int = b.encounter_rng.state
		tick(b,0.25)
		check(b.encounter_rng.state==before,"half interval consumes no RNG")
		tick(b,0.25)
		reference.handle({"type":"field_step","map_id":100,"cell":[637,493],"encounter":true})
		check(b.encounter_rng.state==reference.encounter_rng.state and b.encounter_catalog.pressure==reference.encounter_catalog.pressure,"each cadence exactly matches original pressure/RNG")
	check(b.battle_open and b.battle_state.enemies==reference.battle_state.enemies,"same seed produces exact original troop")
	check(events[0]<10,"misses/heartbeat do not broadcast high-frequency profiles")
	reference.free()
	b.stationary.settled(b,{"battle_id":"unrelated","outcome":"win"},true)
	check(not b.stationary.saved_win,"foreign battle cannot authorize continuation")
	finish(b,"win")
	check(b.stationary.running and b.stationary.saved_win,"successful same-battle win continues")
	var rng: int = b.encounter_rng.state
	tick(b)
	check(b.encounter_rng.state==rng,"result window blocks next encounter")
	check(b.handle({"type":"battle_close"}).ok,"successful result closes")
	tick(b)
	check(b.stationary.running and b.stationary.battle_id.is_empty(),"saved and closed win returns to cadence")
	b.handle({"type":"snapshot"});b.handle({"type":"ping"})
	check(b.stationary.running,"read-only commands do not stop")
	b.handle({"type":"report_position","map_id":100,"cell":[637,493]})
	check(b.stationary.running,"unchanged position does not stop")
	b.handle({"type":"report_position","map_id":100,"cell":[638,493]})
	check(not b.stationary.running,"movement stops")
	b.free()
	for outcome in ["escaped","defeat"]:
		b=fixture();start(b);meet(b);finish(b,outcome)
		check(not b.stationary.running,outcome+" stops after settlement")
		b.free()
	b=fixture();start(b);meet(b)
	b.save_path="user://missing-stationary-directory/save.json"
	finish(b,"win")
	check(not b.stationary.running and b.stationary.reason.contains("保存失败"),"save failure stops before another battle")
	b.free()
	b=fixture();start(b);meet(b);finish(b,"win")
	b.save_path="user://missing-stationary-directory/close.json"
	b.handle({"type":"battle_close"});tick(b)
	check(not b.stationary.running,"close save failure prevents restart despite earlier saved win")
	b.free()
	b=fixture();start(b);meet(b)
	b.battle._state.active=false
	b.stationary.tick(b,0.01)
	check(not b.stationary.running,"terminal but uncommitted settlement cannot remain silently running")
	b.free()

	for conflict in ["running","hunt_running"]:
		b=fixture();b.automation.set(conflict,true)
		check(not start(b),"refuses automation "+conflict)
		b.automation.set(conflict,false);start(b);b.automation.set(conflict,true)
		b.stationary.tick(b,0.01)
		check(not b.stationary.running,"server detects newly started "+conflict)
		b.free()
	b=fixture();b.automation.flow_phase="hunt"
	check(not start(b),"find-pet flow conflicts")
	b.automation.flow_phase="";b.quest_auto.running=true
	check(not start(b),"quest automation conflicts")
	b.quest_auto.running=false
	start(b)
	var path:="user://stationary-reload.json"
	check(b.session.save_game(path) and b.load_profile(path) and not b.stationary.running,"load existing save never restores running mode")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	b.free()
	b=fixture();b.stationary_party_member=func():return true
	check(not start(b),"party leader/member both refused")
	b.stationary_party_member=Callable();start(b);b.stationary_party_member=func():return true
	b.stationary.tick(b,0.01)
	check(not b.stationary.running,"joining party stops without trusting client")
	b.free()
	for command in [{"type":"stationary_pause"},{"type":"quest_talk","npc_id":"missing"},{"type":"auto_start","kind":"invalid"}]:
		b=fixture();start(b);b.handle(command)
		check(not b.stationary.running,"operation stops: "+command.type);b.free()
	b=fixture();start(b);b._process(5.1)
	check(not b.stationary.running,"lost client lease stops after five seconds")
	start(b);b.handle({"type":"stationary_keepalive","_quest_connection":987});b._process(5.1)
	check(not b.stationary.running,"other connection cannot renew owner lease")
	start(b);b.stationary.lease=100
	var before_pressure: int=b.encounter_catalog.pressure
	b._process(2.0)
	check(b.battle_open or b.encounter_catalog.pressure==before_pressure+1 or b.encounter_catalog.pressure==int(b.encounter_catalog.area_at(100,Vector2i(637,493)).probability_min)+1,"large frame never catches up multiple steps")
	check(not b.session.snapshot().has("stationary"),"temporary running state never saved")
	b.free()
	print("STATIONARY ENCOUNTERS: %d failures"%failures)
	quit(1 if failures else 0)
