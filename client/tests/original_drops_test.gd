extends SceneTree
## Real catalog, sessions, backend and party host. Only clocks/connections are fixtures.
const Catalog = preload("res://server/encounter_catalog.gd")
const Backend = preload("res://server/backend.gd")
const Hub = preload("res://server/profile_hub.gd")
const Session = preload("res://server/game_session.gd")
var failures := 0
var folder := "user://original-drops-test"
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1
func _initialize() -> void:call_deferred("run")
func rng_for(boundary: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(100000):
		rng.seed = seed_value
		if rng.randi_range(0,999)==boundary:
			rng.seed = seed_value
			return rng
	check(false,"boundary RNG seed found")
	return rng
func wood(catalog, drops: bool = true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	for seed_value in range(100):
		rng.seed = seed_value
		var enemy: Dictionary = catalog.actor(563,rng)
		if (not enemy.generated_drops.is_empty())==drops:return enemy
	check(false,"source RNG creates requested wood drop")
	return {}
func backend():
	var b = Backend.new()
	root.add_child(b)
	b.set_process(false)
	b.session._profile.inventory.potion = 0
	check(b.session.gm_set_base_stat(-1,"strength",10000),"real GM stat setup")
	return b
func open_wood(b, drops: bool = true) -> Dictionary:
	var config: Dictionary = b.session.start_wild_battle_config({"area_id":267,"group_id":414,"enemies":[wood(b.encounter_catalog,drops)]})
	check(not config.is_empty(),"source wood accepted by real GameSession")
	return b.open_battle(config)
func finish(b, action: String = "attack") -> Dictionary:
	var state: Dictionary = b.battle.snapshot()
	for i in range(100):
		if not bool(state.active):break
		state = b.battle_command({"action":action,"target":0})
	check(not state.active,"real resolver finishes wood battle")
	return state
func run() -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var catalog = Catalog.new()
	var source: Dictionary = catalog.data.enemies["563"]
	check(source.drops.size()==1 and int(source.drops[0].slot)==0 and int(source.drops[0].item_id)==2468 and int(source.drops[0].probability)==700 and int(source.drops[0].denominator)==1000,"original drop columns are imported without scaling")
	check(catalog.roll_drops(source,rng_for(699))==[2468],"_FIX_ITEMPROB 699 grants wood")
	check(catalog.roll_drops(source,rng_for(700)).is_empty(),"_FIX_ITEMPROB 700 rejects wood")
	var rng := RandomNumberGenerator.new()
	check(catalog.roll(1099,Vector2i(24,42),rng).is_empty(),"wood-only area has no fallback without permit")
	check(catalog.roll(1099,Vector2i(24,42),rng,[2478]).group_id==414,"authoritative permit admits original wood group")
	var gated: Dictionary = catalog.data.groups["414"]
	var original_exclude := int(gated.excludes_item)
	gated.excludes_item = 2478
	check(catalog.roll(1099,Vector2i(24,42),rng,[2478]).is_empty(),"exclusion also uses held inventory")
	gated.excludes_item = original_exclude
	var area: Dictionary = catalog.area_at(1099,Vector2i(24,42))
	var event_now := int(area.event_now)
	area.event_now = 18
	check(catalog.roll(1099,Vector2i(24,42),rng,[2478]).is_empty(),"inventory does not unlock deferred event conditions")
	area.event_now = event_now
	var excluded_every_time := true
	var wood_seen := false
	var ordinary_seen := false
	for i in range(100):
		var no_permit: Dictionary = catalog.roll(200,Vector2i(516,238),rng)
		excluded_every_time = excluded_every_time and int(no_permit.get("group_id",-1))!=414
		var permitted: Dictionary = catalog.roll(200,Vector2i(516,238),rng,[2478])
		wood_seen = wood_seen or int(permitted.get("group_id",-1))==414
		ordinary_seen = ordinary_seen or int(permitted.get("group_id",-1))!=414
	check(excluded_every_time,"mixed area excludes wood without permit")
	check(wood_seen and ordinary_seen,"permit preserves weighted ordinary encounters")
	var gate_backend = backend()
	check(not gate_backend.wild_encounter(1099,Vector2i(24,42)).ok,"Backend uses its own empty inventory to exclude wood")
	gate_backend.session._profile.original_items = [2478]
	# Find a server RNG seed that produces the source wood drop through the
	# real production roll; no replacement catalog or art-gate bypass.
	for seed_value in range(100):
		gate_backend.encounter_rng.seed = seed_value
		var rolled: Dictionary = gate_backend.encounter_catalog.roll(1099,Vector2i(24,42),gate_backend.encounter_rng,[2478])
		if not rolled.enemies[0].generated_drops.is_empty():
			gate_backend.encounter_rng.seed = seed_value
			break
	var admission: Dictionary = gate_backend.wild_encounter(1099,Vector2i(24,42))
	check(bool(admission.ok),"production Backend with permit opens original wood battle with real art")
	if bool(admission.ok):
		check(int(admission.troop.enemies[0].source_enemy_id)==563 and int(admission.troop.enemies[0].sprite)==100468,"production encounter selects original wood enemy and sprite")
		var hp := int(gate_backend.battle.snapshot().player_hp)
		var waiting: Dictionary = gate_backend.battle_command({"action":"defend","target":0})
		check(int(waiting.player_hp)==hp and waiting.turn_frames.any(func(f):return f.actor=="enemy" and f.outcome=="wait"),"production wood enemy waits without damaging player")
		var settled: Dictionary = finish(gate_backend)
		check(settled.outcome=="win" and gate_backend.session.snapshot().original_items==[2478,2468],"production wood kill awards original wood and preserves permit")
	gate_backend.queue_free()
	await process_frame
	var forged_actor := wood(catalog)
	forged_actor.generated_drops = [999999]
	check(Session.new().start_wild_battle_config({"enemies":[forged_actor]}).is_empty(),"pending validates generated item ids against original source slots")
	forged_actor = wood(catalog)
	forged_actor.generated_drops.append(2468)
	check(Session.new().start_wild_battle_config({"enemies":[forged_actor]}).is_empty(),"pending rejects multiple grants from one original item slot")
	await solo()
	await command_authority()
	await resume()
	await party(false,false)
	await party(true,false)
	await party(false,true)
	clean(folder)
	print("ORIGINAL DROPS: %d failures"%failures)
	quit(1 if failures else 0)
func solo() -> void:
	for full in [false,true]:
		var b = backend()
		b.session._profile.original_items = [2478,2476]
		while Session.bag_slots(b.session.snapshot())<(15 if full else 14):b.session._profile.original_items.append(100)
		var before: Dictionary = b.session.snapshot()
		open_wood(b)
		var hp := int(b.battle.snapshot().player_hp)
		var waiting: Dictionary = b.battle_command({"action":"defend","target":0})
		check(int(waiting.player_hp)==hp and waiting.turn_frames.any(func(f):return f.actor=="enemy" and f.outcome=="wait"),"source wait-only wood neither attacks nor damages")
		# Forged result loot never overrides the enemy's generated pending record.
		b.battle._state.enemies[0].generated_drops = [999999]
		var state := finish(b)
		var after: Dictionary = b.session.snapshot()
		check(state.settled and int(state.xp)==0 and state.drop_summary.size()==1,"zero XP still has independent drop settlement summary")
		check(b.full_snapshot().battle.drop_summary==state.drop_summary,"remote snapshot retains drop summary independently of XP")
		check(after.original_items.count(2468)==(0 if full else 1),"full bag destroys wood; one empty slot receives one unstacked item")
		check(999999 not in after.original_items,"result drop ids cannot forge inventory")
		check(after.original_events==before.original_events and after.original_items.count(2478)==1 and after.original_items.count(2476)==1,"logging keeps original flags, permit and axe")
		check(not b.session.apply_battle_result(state),"repeated session settlement is refused")
		b._after_turn(state)
		check(b.session.snapshot().original_items==after.original_items,"repeated backend settlement never duplicates wood")
		b.queue_free()
		await process_frame
	var b = backend()
	open_wood(b,false)
	check(finish(b).drop_summary.is_empty() and 2468 not in b.session.snapshot().original_items,"failed generation roll never retries at victory")
	b.queue_free()
	await process_frame
func command_authority() -> void:
	var b = backend()
	var injected := wood(b.encounter_catalog)
	injected.generated_drops = [999999]
	var issued: Dictionary = b.handle({"type":"start_wild_battle_config","troop":{"enemies":[injected]}})
	check(bool(issued.ok) and b.session._pending.enemies[0].get("generated_drops",[]).is_empty(),"admin fixture cannot submit pre-rolled client loot")
	var config: Dictionary = issued.config
	config.enemies[0].generated_drops = [2468]
	check(bool(b.handle({"type":"open_battle","config":config}).ok),"authority-issued config opens through command path")
	check(finish(b).drop_summary.is_empty() and b.session.snapshot().original_items.is_empty(),"open command cannot replace issued source loot metadata")
	b.queue_free()
	await process_frame
	b = backend()
	check(b.session.grant_starter_pets() and b.session.select_pet(0),"real solo companion selected")
	check(b.session.gm_set_base_stat(0,"strength",10000),"real solo companion prepared")
	open_wood(b)
	var state := finish(b,"defend")
	check(state.outcome=="win" and b.session.snapshot().original_items==[2468],"solo pet kill awards owner exactly one wood")
	b.queue_free()
	await process_frame
	b = backend()
	open_wood(b)
	state = finish(b,"escape")
	check(state.outcome=="escaped" and state.drop_summary.is_empty() and b.session.snapshot().original_items.is_empty(),"escaping live wood never grants its generated item")
	b.queue_free()
	await process_frame
func resume() -> void:
	for drops in [false,true]:
		var b = backend()
		b.save_path = folder.path_join("resume-%s.json"%str(drops))
		b.resume_path = folder.path_join("resume-%s.resume.json"%str(drops))
		b.session._profile.original_items = [2478]
		check(b.save(),"real test profile saved before battle")
		open_wood(b,drops)
		b.battle_command({"action":"defend","target":0})
		var pending: Dictionary = b.session._pending.duplicate(true)
		var checkpoint: Dictionary = b._wood_battle_resume()
		if drops:b.shut_down()
		else:b.keep_resume_file()
		check(FileAccess.file_exists(b.resume_path),"periodic or clean shutdown checkpoint persists to server resume file")
		var restored = backend()
		restored.save_path = b.save_path
		restored.resume_path = b.resume_path
		check(restored.load_profile(b.save_path),"real saved profile loads at restart")
		restored.load_resume()
		check(restored.battle_open and restored.session._pending==pending,"server restart retains pending already-rolled loot")
		check(int(restored.battle.snapshot().turn)==1,"restart retains resolver turn")
		var result := finish(restored)
		check(restored.session.snapshot().original_items.count(2468)==(1 if drops else 0),"resume never rerolls successful or failed wood drop")
		check(not restored.session.apply_battle_result(result),"restored settlement remains single use")
		restored.close_battle()
		check(not restored._restore_wood_battle(checkpoint),"already completed battle cannot replay through an old resume checkpoint")
		b.queue_free();restored.queue_free()
		await process_frame
func party(pet_kill: bool, full: bool) -> void:
	var tag := "pet" if pet_kill else ("full" if full else "player")
	var path := folder.path_join(tag)
	DirAccess.make_dir_recursive_absolute(path)
	var hub = Hub.new(path.path_join("accounts.json"),func():return 10.0)
	hub.tick = false;hub.backups = false;hub.share_dir = ""
	hub.presence_clock = func():return 10000
	hub.battle_clock = func():return 500000
	root.add_child(hub)
	hub.start()
	for i in range(2):
		hub.handle(i+1,{"type":"create_profile","name":"Wood%d"%i,"pin":"1111"})
		hub.handle(i+1,{"type":"report_position","map_id":1000,"cell":[80+i,90],"client":"wood%d"%i})
	var joined: Dictionary = hub.handle(2,{"type":"party_join","facing":1})
	check(bool(joined.get("ok",false)),"real adjacent member joins leader party")
	var leader = hub.backends[hub.profile_of(1)]
	var member = hub.backends[hub.profile_of(2)]
	leader.session._profile.original_items = [2478]
	leader.session._profile.inventory.potion = 0
	member.session._profile.inventory.potion = 0
	if full:
		while Session.bag_slots(member.session.snapshot())<15:member.session._profile.original_items.append(100)
	if pet_kill:
		check(member.session.grant_starter_pets(),"real member pets granted")
		check(member.session.select_pet(0),"real member pet selected")
		check(member.session.gm_set_base_stat(0,"strength",10000),"real pet prepared to kill wood")
	else:check(member.session.gm_set_base_stat(-1,"strength",10000),"real member prepared to kill wood")
	var config: Dictionary = leader.session.start_wild_battle_config({"area_id":267,"group_id":414,"enemies":[wood(leader.encounter_catalog)]})
	leader.open_battle(config)
	check(leader.party_battle(),"real party host joins source wood battle")
	if not leader.party_battle():
		hub.queue_free()
		await process_frame
		return
	var entry: Dictionary = hub.party_battles.fighting[hub.profile_of(1)]
	for i in range(100):
		if not leader.battle.snapshot().active:break
		for connection in [1,2]:
			var own = leader if connection==1 else member
			var state: Dictionary = own.battle.snapshot()
			hub.handle(connection,{"type":"battle_command","battle_id":state.battle_id,"turn":state.turn,"slot":state.party_slot,"action":"defend" if connection==1 or pet_kill else "attack","target":0})
	check(leader.battle_state.settled and member.battle_state.settled,"each real party session settles once")
	check(leader.session.snapshot().original_items==[2478],"leader receives no copy of member kill loot")
	check(member.session.snapshot().original_items.count(2468)==(0 if full else 1),"killer or pet owner alone receives wood without permit; full bag does not transfer")
	check(entry.session.drop_claims_for(0).is_empty() and entry.session.drop_claims_for(1).size()==1,"authority assigns exactly one loot claim to member slot")
	var count: int = member.session.snapshot().original_items.count(2468)
	hub.party_battles._push(entry)
	check(member.session.snapshot().original_items.count(2468)==count,"repeated party push cannot grant again")
	hub.shut_down();hub.queue_free()
	await process_frame
func clean(path: String) -> void:
	for sub in DirAccess.get_directories_at(path):clean(path.path_join(sub))
	for file in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
