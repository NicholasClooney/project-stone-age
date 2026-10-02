extends SceneTree
const Backend=preload("res://server/backend.gd")
const Borrow=preload("res://server/training_borrow.gd")
const Selection=preload("res://server/training_troops.gd")
const Settings=preload("res://scripts/automation_settings.gd")
const Background=preload("res://scripts/battle_background.gd")
const Wait=preload("res://tests/support/wait.gd")
const MAP=100
const CELL=Vector2i(637,493)
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func fresh(strong: bool=true):
	var b=Backend.new();root.add_child(b);b.set_process(false);b.automation.client_attached=false
	b.encounter_rng.seed=9;b.training_pool_rng.seed=9
	b.handle({"type":"grant_starter_pets"});b.session.select_pet(0)
	if strong:
		b.handle({"type":"gm_raise_level","index":-1,"target":120})
		for stat in ["strength","toughness"]:b.handle({"type":"gm_set_base_stat","index":-1,"stat":stat,"value":500})
		b.handle({"type":"gm_heal"})
	b.automation.position_map=MAP;b.automation.position_cell=CELL
	return b
## Reaching an outcome and successfully opening a battle are separate facts.
func training_outcome(b) -> bool:
	return await Wait.until(self,func():
		if b.battle_open or not b.automation.running:return true
		b.automation.step()
		return b.battle_open or not b.automation.running)
func enter(b) -> bool:
	return await training_outcome(b) and b.battle_open
func pending_forecast(b) -> bool:
	var reached: bool=await Wait.until(self,func():
		if not b.automation.training_borrow_pending.is_empty() or not b.automation.running:return true
		b.automation.step()
		return not b.automation.training_borrow_pending.is_empty() or not b.automation.running)
	return reached and not b.automation.training_borrow_pending.is_empty()
func settled(b) -> bool:
	return await Wait.until(self,func():
		if not b.battle.snapshot().active:return true
		b.automation.step()
		return not b.battle.snapshot().active)
func begin(b, borrow: bool=true, local: bool=true, target: int=120) -> bool:
	var pet_id: String=b.session.snapshot().pets[0].pet_id
	return b.automation.start_pet_training(pet_id,target,{}, {"xp":10,"borrow_troops":borrow,"select_troops":local,"hp":1,"spirit":false,"limit":100})
func dispose(b) -> void:
	b.automation.stop("test end");b.queue_free();await process_frame
func lan_borrow(seed_value: int, accepted: bool) -> void:
	var folder:="user://borrow-lan-%d-%d"%[OS.get_process_id(),seed_value]
	DirAccess.make_dir_recursive_absolute(folder)
	var hub=preload("res://server/profile_hub.gd").new(folder.path_join("accounts.json"))
	hub.tick=false;hub.backups=false;hub.share_dir="";root.add_child(hub);hub.start()
	for i in range(2):
		hub.handle(i+1,{"type":"create_profile","name":["Alice","Bob"][i],"pin":["1111","2222"][i]})
		hub.handle(i+1,{"type":"report_position","map_id":1000,"cell":[81-i,90],"client":"p%d"%i})
	check(hub.handle(2,{"type":"party_join","facing":5}).ok,"real LAN party joins for borrowing")
	for id in hub.backends:
		var backend=hub.backends[id]
		backend.handle({"type":"gm_raise_level","index":-1,"target":120})
		for stat in ["strength","toughness"]:backend.handle({"type":"gm_set_base_stat","index":-1,"stat":stat,"value":500})
		backend.handle({"type":"gm_heal"})
	hub.handle(2,{"type":"set_automation_settings","settings":{"party":{"auto":true,"compact":true}}})
	var lead=hub.backends.alice
	lead.training_pool_rng.seed=seed_value
	lead.session.grant_starter_pets();lead.session.select_pet(0);lead.session.gm_raise_level(0,119);lead.session.gm_heal()
	hub.handle(1,{"type":"report_position","map_id":MAP,"cell":[CELL.x,CELL.y],"map_changed":true,"client":"p0"})
	var context: Dictionary=lead.training_reward_context.call()
	check(context.players==2 and context.active_pets==1 and context.member_ids==["alice","bob"],"borrow forecast and estimate use actual two-player one-pet roster")
	check(hub.handle(1,{"type":"auto_start","kind":"battle","map_id":MAP,"cell":[CELL.x,CELL.y],"settings":{"level":0,"xp":10,"limit":1,"spirit":false,"hp":1,"select_troops":true,"borrow_troops":true}}).ok,"LAN shared training starts borrowing")
	check(await pending_forecast(lead),"LAN reaches the pending borrowed forecast before member changes")
	check(hub.backends.bob.session.set_character("100010"),"real member character changes while borrowed forecast is pending")
	lead.automation.step()
	check(not lead.battle_open and not lead.automation.running and lead.automation.stop_reason.contains("发生变化"),"LAN refuses stale member configuration before borrowed battle")
	check(hub.handle(1,{"type":"auto_start","kind":"battle","map_id":MAP,"cell":[CELL.x,CELL.y],"settings":{"level":0,"xp":10,"limit":1,"spirit":false,"hp":1,"select_troops":true,"borrow_troops":true}}).ok,"LAN recomputes actual changed member before restart")
	check(await training_outcome(lead),"LAN forecast reaches a bounded outcome seed%d"%seed_value)
	if not accepted:
		var forecast: Dictionary=lead.automation.training_borrow_forecast.summary()
		check(not lead.battle_open and not lead.automation.running and forecast.ready and not forecast.ok and forecast.wins==3 and lead.automation.stop_reason.contains("预测"),"seed20 real LAN forecast wins only3/5 and correctly refuses the unsafe troop")
		hub.shut_down();hub.queue_free();await process_frame
		return
	check(lead.battle_open and lead.party_battle() and lead.battle.snapshot().has("training_borrow"),"actual shared LAN opens forecast-approved borrowed original troop")
	if lead.battle_open:
		var expected:=0
		for enemy in lead.session._pending.enemies:expected+=preload("res://server/party_battle_session.gd").gap_exp(int(enemy.reward_xp)*10,119,int(enemy.level))
		var done: bool=await Wait.until(self,func():
			if not lead.battle.snapshot().active:return true
			lead.automation.step();hub.party_battles.tick()
			return not lead.battle.snapshot().active)
		check(done and lead.battle_state.get("settled",false) and int(lead.battle_state.pet_reward_xp[0])==expected,"actual LAN settlement matches source reward ×10 then real target-level gap")
	hub.shut_down();hub.queue_free();await process_frame

func run() -> void:
	check(Settings.defaults().training.borrow_troops,"borrow defaults on independently of local selection")
	for value in [1,"true",[],{}]:check(not Settings.apply_patch({}, {"training":{"borrow_troops":value}}).ok,"borrow setting rejects non-bool %s"%str(value))
	var b=fresh();var p: Dictionary=b.session.snapshot()
	var pool: Array=Borrow.available(b.encounter_catalog,b.session.world_catalog,p)
	check(pool.size()==4,"four fully audited original groups are available with actual imported maps and sprites")
	var ids:=[]
	for row in pool:
		ids.append(int(row.group_id))
		check(row.enemies.all(func(e):return int(e.level_min)>=80 and int(e.level_max)<=105 and int(e.enemy_line)>0 and int(e.enemybase_line)>0),"group %d has original levels and exact source rows"%int(row.group_id))
	check(ids==[767,779,781,753],"pool contains both Bora and dark cave, no rare/task fabricated groups")
	var group: Dictionary=b.encounter_catalog.data.groups["767"]
	var original_requires:=int(group.requires_item);group.requires_item=18559
	check(not Borrow.available(b.encounter_catalog,b.session.world_catalog,p).any(func(r):return int(r.group_id)==767),"authoritative item gate excludes unowned borrowed group")
	p.original_items=[18559]
	check(Borrow.available(b.encounter_catalog,b.session.world_catalog,p).any(func(r):return int(r.group_id)==767),"actual held inventory admits gated group")
	group.requires_item=original_requires
	var area: Dictionary=b.encounter_catalog.area_at(500,Vector2i(537,500));var old_event:=int(area.event_now);area.event_now=7
	check(not Borrow.available(b.encounter_catalog,b.session.world_catalog,p).any(func(r):return int(r.group_id)==767),"event-conditioned group is never borrowed without supported event state")
	area.event_now=old_event
	check(Borrow.should_borrow({"kind":"pet","remaining_xp":263},52.5) and not Borrow.should_borrow({"kind":"pet","remaining_xp":260},52.0) and not Borrow.should_borrow({"kind":"player","remaining_xp":214200},52.5),"strict greater-than-five boundary and pet-only recipient")
	var seen:={};var enemies:={}
	for seed_value in range(32):
		var rng:=RandomNumberGenerator.new();rng.seed=seed_value
		var troop: Dictionary=Borrow.roll(b.encounter_catalog,pool,rng,[])
		seen[int(troop.group_id)]=true
		for enemy in troop.enemies:enemies[int(enemy.source_enemy_id)]=true
		var meta: Dictionary=troop.training_borrow
		var bg=Background.new()
		check(int(meta.field) in bg.choices(bg.ground_of(int(meta.ground_bitmap))) and FileAccess.file_exists(str(meta.texture)),"seed %d uses source ground's actual battlefield"%seed_value)
	check(seen.size()==4 and enemies.size()>6,"independent seeds rotate real groups and different original enemy ids")
	var baseline_rng:=RandomNumberGenerator.new();var direct_rng:=RandomNumberGenerator.new()
	baseline_rng.seed=27;direct_rng.seed=27
	var source_area: Dictionary=b.encounter_catalog.area_at(500,Vector2i(537,500))
	var baseline: Dictionary=b.encounter_catalog.roll(500,Vector2i(537,500),baseline_rng,[])
	var candidates:=[]
	for choice in source_area.groups:
		var g: Dictionary=b.encounter_catalog.data.groups[str(int(choice.id))]
		if int(g.requires_item)<0 and int(g.excludes_item)<0:candidates.append(choice)
	var chosen: int=b.encounter_catalog._weighted(candidates,direct_rng)
	check(baseline==b.encounter_catalog.roll_group(source_area,chosen,direct_rng,[]) and baseline_rng.state==direct_rng.state,"extracted roll_group preserves original area roll enemies/growth/dropdraw and exact RNG")
	check(b.encounter_catalog.roll_group(source_area,753,direct_rng,[]).is_empty(),"direct group roll refuses a different area's group instead of changing encounter source")
	var local_rng: int=b.encounter_rng.state;var pressure:=37;b.encounter_catalog.pressure=pressure
	var location: Dictionary=b.session.snapshot().location.duplicate(true)
	b.training_pool_rng.seed=9
	check(begin(b) and await enter(b) and b.battle_open,"default flags enter a forecast-approved borrowed battle")
	check(b.encounter_rng.state==local_rng and b.encounter_catalog.pressure==pressure and b.automation.origin_map==MAP and b.automation.origin_cell==CELL and b.session.snapshot().location==location,"borrow does not move player, origin, local pressure or hunt/walking RNG")
	var pending: Dictionary=b.session._pending.duplicate(true)
	check(not b.battle.snapshot().get("training_borrow",{}).is_empty() and b.battle.snapshot().training_borrow==pending.training_borrow,"source map and ground metadata travel through actual battle snapshot")
	var xp:=0
	for enemy in pending.enemies:xp+=int(enemy.reward_xp)*10
	var old_variable: float=float(b.session.snapshot().pets[0].variable_ai)
	var old_gold:=int(b.session.snapshot().player.gold)
	check(await settled(b) and b.battle_state.get("settled",false) and b.battle_state.xp==xp and b.battle_state.pet_reward_xp[0]==xp,"real borrowed Battle/Session settlement pays exact original XP times ten")
	check(int(b.session.snapshot().player.gold)-old_gold==1200 and b.battle_state.gold==1200,"real original BATTLEGOLD pays once at player pre-battle level, not per enemy")
	check(int(b.battle_state.pets[0].hp)==0 and int(b.battle_state.pet_reward_xp[0])>0,"actual trained pet falls but still receives original XP with protection")
	check(float(b.session.snapshot().pets[0].variable_ai)>=old_variable,"real protected fall causes no loyalty-variable loss")
	b.automation.step() # closes settled battle
	b.automation.step() # restores actual carried pets before next battle
	check(b.session.snapshot().pets.all(func(pet):return int(pet.hp)==int(pet.max_hp)),"next encounter preparation restores all actual carried pets to full HP")
	check(not b.session.apply_battle_result(b.battle_state) and b.session.snapshot().player.gold==old_gold+1200,"replayed settlement cannot award XP/gold/drops twice")
	await dispose(b)

	var off=fresh();check(begin(off,false,true) and await enter(off) and off.battle_open and off.battle.snapshot().get("training_borrow",{}).is_empty(),"borrow off still uses real local top30 selector")
	await dispose(off)
	var independent=fresh();check(begin(independent,true,false) and await enter(independent) and independent.battle_open and not independent.battle.snapshot().get("training_borrow",{}).is_empty(),"borrow on operates independently while local selector is off")
	await dispose(independent)
	var neither=fresh();check(begin(neither,false,false) and await enter(neither) and neither.battle_open and neither.automation.training_skipped==0,"both settings off preserve original first local encounter")
	await dispose(neither)
	var weak=fresh(false);check(begin(weak) and await training_outcome(weak) and not weak.battle_open and weak.automation.stop_reason.contains("预测"),"weak actual squad pauses before strong battle instead of fabricating victory")
	await dispose(weak)

	var saved=fresh();saved.save_path="user://training-borrow-save.json";saved.resume_path="user://training-borrow-resume.json"
	saved.session.set_training_borrow_rng({"seed":"17","state":str(9223372036854775806)})
	check(saved.save() and Borrow.valid_rng(saved.session.training_borrow_rng()),"optional v6 save preserves full 64-bit independent random stream")
	var reload=fresh();check(reload.session.load_game(saved.save_path) and reload.session.training_borrow_rng()==saved.session.training_borrow_rng(),"actual save load restores exact seed and state without JSON precision loss")
	check(begin(saved) and await enter(saved) and saved.battle_open,"resume fixture opens actual borrowed battle")
	var after_roll: Dictionary=saved.session.training_borrow_rng()
	var interrupted_gold:=int(saved.session.snapshot().player.gold)
	var interrupted_level:=int(saved.session.snapshot().pets[0].level)
	saved.shut_down()
	var resumed=fresh();resumed.save_path=saved.save_path;resumed.resume_path=saved.resume_path
	check(resumed.session.load_game(saved.save_path),"shutdown saves authoritative character without unfinished rewards")
	resumed.load_resume();resumed.automation.try_resume()
	check(int(resumed.session.snapshot().player.gold)==interrupted_gold and int(resumed.session.snapshot().pets[0].level)==interrupted_level,"unfinished borrowed battle grants no resume XP or stone")
	check(resumed.session.training_borrow_rng()==after_roll and resumed.automation.running,"resume keeps consumed pool stream and actual target uid")
	check(await enter(resumed) and resumed.battle_open and resumed.session.training_borrow_rng()!=after_roll,"resume draws next original troop, never reuses the unfinished reward roll")
	await dispose(saved);await dispose(reload);await dispose(resumed)

	# Actual progress and catalog expectation produce an exact integer boundary
	# at 100x (10x local 52.5 yields a half-XP boundary that cannot equal an
	# integer saved remaining XP). No rewards or enemy values are substituted.
	for extra_xp in [945,944]:
		var boundary=fresh();boundary.session.gm_raise_level(0,119)
		boundary.session._gain_xp(boundary.session._profile.pets[0],extra_xp)
		var uid: String=boundary.session.snapshot().pets[0].pet_id
		check(boundary.automation.start_pet_training(uid,120,{}, {"xp":100,"borrow_troops":true,"select_troops":true,"hp":1,"spirit":false}),"actual boundary training starts")
		await enter(boundary)
		var selection=boundary.automation.training_selection
		check(is_equal_approx(selection.local_best_expected(),525.0) and int(selection.participant.remaining_xp)==3570-extra_xp,"boundary derives local XP from real catalog and remaining XP from actual progression")
		check(boundary.battle_open and boundary.battle.snapshot().has("training_borrow")== (extra_xp==944),"=5 stays local, 2626/525>5 borrows; actual battle")
		await dispose(boundary)

	var changed=fresh();check(begin(changed),"forecast identity guard fixture starts")
	check(await pending_forecast(changed),"identity fixture reaches the pending forecast")
	changed.session.clone_squad_enabled=not changed.session.clone_squad_enabled
	changed.automation.step()
	check(not changed.battle_open and not changed.automation.running and changed.automation.stop_reason.contains("发生变化"),"clone change during bounded forecast refuses stale config")
	await dispose(changed)
	var uid_changed=fresh();check(begin(uid_changed),"actual trained UID guard starts")
	check(await pending_forecast(uid_changed),"identity fixture reaches the pending forecast")
	uid_changed.session.select_pet(1);uid_changed.automation.step()
	check(not uid_changed.battle_open and not uid_changed.automation.running and uid_changed.automation.stop_reason.contains("发生变化"),"switching actual active pet UID refuses stale borrowed config")
	await dispose(uid_changed)
	var prefs=fresh();check(prefs.handle({"type":"set_automation_settings","settings":{"training":{"borrow_troops":false}}}).ok,"role stores independent borrow-off preference")
	check(prefs.session.save_game("user://borrow-prefs.json"),"borrow-off actual role save")
	var loaded=fresh();check(loaded.session.load_game("user://borrow-prefs.json") and not Settings.effective(loaded.session.automation_settings()).training.borrow_troops,"borrow-off survives real save load")
	var other=fresh();check(Settings.effective(other.session.automation_settings()).training.borrow_troops,"another character retains borrow default on")
	await dispose(prefs);await dispose(loaded);await dispose(other)

	var failed_save=fresh();failed_save.save_path="user://borrow-missing-%d/save.json"%OS.get_process_id()
	check(begin(failed_save) and await training_outcome(failed_save) and not failed_save.battle_open and failed_save.automation.stop_reason.contains("无法保存"),"real save failure pauses borrowed roll before forecasting/opening or rewards")
	await dispose(failed_save)
	var no_pool=fresh();var art=preload("res://server/troop_art.gd");var saved_art: Dictionary=art._validation.duplicate()
	for sprite in ["100378","100341","100383"]:art._validation[sprite]=false
	check(begin(no_pool) and await training_outcome(no_pool) and not no_pool.battle_open and no_pool.automation.stop_reason.contains("没有可用"),"no eligible audited pool pauses clearly before drawing or opening")
	art._validation=saved_art;await dispose(no_pool)
	var spoof=fresh();var spoof_config: Dictionary=spoof.session.start_battle_config()
	spoof_config.training_borrow={"map_id":500,"group_id":767,"texture":"res://wrong-client-background.png"}
	check(spoof.handle({"type":"open_battle","config":spoof_config}).ok and not spoof.battle.snapshot().has("training_borrow"),"client-supplied source marker cannot forge an authority borrowed battle")
	await dispose(spoof)
	var capture=fresh()
	check(capture.wild_encounter(MAP,CELL).ok and capture.battle.snapshot().get("training_borrow",{}).is_empty() and capture.session.training_borrow_rng().is_empty(),"ordinary/manual encounter ignores default borrowing and never touches its stream")
	await dispose(capture)
	var flow=fresh();flow.training_pool_rng.seed=3
	var raw: Dictionary=Settings.stat_filter({},113)
	for condition in raw.conditions.values():condition.enabled=false
	check(flow.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y],"filter":{"templates":[113],"total":-8,"offsets":[],"clean_only":false,"fast":false,"showcase":true},"stat_filters":{"113":raw},"settings":{"capture_hp":100,"xp":10}}).ok,"actual showcase capture-to-borrow workflow starts")
	var saw_capture:=false;var saw_borrow:=false;var capture_unchanged:=true
	var deadline:=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
	while flow.automation.flow_active() and Time.get_ticks_msec()<deadline:
		flow._process(0.5)
		if flow.battle_open and flow.automation.flow_phase=="capture":
			saw_capture=true;capture_unchanged=capture_unchanged and not flow.battle.snapshot().has("training_borrow") and flow.session.training_borrow_rng().is_empty()
		if flow.battle_open and flow.automation.flow_phase=="train":saw_borrow=flow.battle.snapshot().has("training_borrow");break
		await process_frame
	check(saw_capture and capture_unchanged and saw_borrow and not flow.automation.flow_pet_id.is_empty(),"real capture leaves pool untouched; caught UID then trains through default-on validated borrowed group")
	await dispose(flow)

	await lan_borrow(0,true)
	await lan_borrow(20,false)
	var counts:=[]
	for seed_value in range(10):
		var run=fresh();run.training_pool_rng.seed=seed_value
		check(begin(run),"real Lv1-to120 ten-times run starts seed%d"%seed_value)
		var total:=0;var borrowed:=0
		while run.automation.running and total<30:
			await enter(run)
			if not run.battle_open:break
			if run.battle.snapshot().has("training_borrow"):borrowed+=1
			await settled(run);total+=1
			run.automation.step()
		var pet: Dictionary=run.session.snapshot().pets[0]
		check(int(pet.level)==120,"actual settlement raises trained pet to120 seed%d"%seed_value)
		print("MEASURE seed=%d total=%d borrowed=%d local=%d level=%d xp=%d"%[seed_value,total,borrowed,total-borrowed,int(pet.level),int(pet.xp)])
		counts.append(total);await dispose(run)
	print("MEASURE_COUNTS %s"%str(counts))
	print("TRAINING BORROW: %d failures"%failures);quit(1 if failures else 0)
