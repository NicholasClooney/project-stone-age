extends SceneTree
const Backend=preload("res://server/backend.gd")
const Catalog=preload("res://server/encounter_catalog.gd")
const Selection=preload("res://server/training_troops.gd")
const Settings=preload("res://scripts/automation_settings.gd")
const Art=preload("res://server/troop_art.gd")
const Wait=preload("res://tests/support/wait.gd")
const MAP=100
const CELL=Vector2i(637,493)
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, label: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok:failures+=1
func fresh():
	var b=Backend.new();root.add_child(b);b.set_process(false);b.automation.client_attached=false
	b.handle({"type":"set_automation_settings","settings":{"training":{"borrow_troops":false}}})
	b.handle({"type":"grant_starter_pets"});b.session.select_pet(0)
	b.handle({"type":"gm_raise_level","index":-1,"target":20})
	b.handle({"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":500})
	b.handle({"type":"gm_heal"})
	return b
func finish(plan) -> bool:
	var deadline:=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
	while not plan.ready and Time.get_ticks_msec()<deadline:
		plan.advance(1000);await process_frame
	return plan.ready
func row(plan,id: int) -> Dictionary:
	for r in plan.rows:
		if int(r.group_id)==id:return r
	return {}
func begin(b, enabled: bool=true, preset: String="attack") -> bool:
	return b.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":[CELL.x,CELL.y],"settings":{"select_troops":enabled,"borrow_troops":false,"xp":10,"level":0,"limit":100,"preset":preset,"compact":true,"spirit":false,"hp":1}}).ok
func same(troop: Dictionary, b) -> bool:
	var actors: Array=b.session._pending.get("enemies",[])
	if actors.size()!=troop.get("enemies",[]).size():return false
	for i in range(actors.size()):
		for k in ["source_enemy_id","level","growth_weights","growth_seed","base_stats","generated_drops","reward_xp"]:
			if actors[i].get(k)!=troop.enemies[i].get(k):return false
	return int(b.session._pending.get("group_id",-1))==int(troop.group_id)
func run() -> void:
	check(Settings.defaults().training.select_troops,"training selection is on by default")
	check(not Settings.apply_patch({}, {"training":{"select_troops":1}}).ok and not Settings.apply_patch({}, {"training":{"select_troops":"true"}}).ok,"selection setting strictly requires bool")
	var strict=Backend.new();root.add_child(strict);strict.set_process(false)
	check(not strict.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":[CELL.x,CELL.y],"settings":{"select_troops":1}}).ok,"legacy flat start refuses non-bool selector too")
	strict.queue_free();await process_frame
	var b=fresh();var p: Dictionary=b.session.snapshot()
	var plan=Selection.new();var before_state: int=b.encounter_rng.state;var pressure: int=b.encounter_catalog.pressure
	plan.prepare(b.encounter_catalog,MAP,CELL,p,{"xp":10,"protect":true},false)
	check(await finish(plan),"real local ranking completes as bounded continuations")
	check(b.encounter_rng.state==before_state and b.encounter_catalog.pressure==pressure,"expected ranking never draws encounter RNG or changes pressure")
	check(plan.rows.size()==4 and plan.allowed==[92,89] and is_equal_approx(plan.threshold,37.5),"ceil(30% of four groups)=two; rank actual local expected pet XP")
	check(is_equal_approx(float(row(plan,88).expected_xp),15.0) and is_equal_approx(float(row(plan,89).expected_xp),37.5) and is_equal_approx(float(row(plan,92).expected_xp),52.5),"original level1 reward1, uniform level2/3 and uniform one/two enemies give exact 15/37.5/52.5 at 10x")
	check(plan.participant.kind=="pet" and plan.participant.players==1 and plan.participant.level==1,"ranking uses actual participating target pet and side size")
	var clone_plan=Selection.new();clone_plan.prepare(b.encounter_catalog,MAP,CELL,p,{"xp":100,"protect":true},true);await finish(clone_plan)
	check(clone_plan.participant.players==5 and is_equal_approx(clone_plan.local_best_expected(),525.0),"mirror side does not invent a reward divisor; XP multiplier applies exactly once")
	var tied=Selection.new();tied.prepare(b.encounter_catalog,300,Vector2i(509,93),p,{"xp":10},false);await finish(tied)
	check(tied.rows.size()==3 and tied.allowed.size()==2 and 444 in tied.allowed and 446 in tied.allowed,"ceil(30% of three)=one but equal high-value dragon groups both pass boundary tie")
	check(Selection.context(p,{"xp":99},false).multiplier==1,"unsupported legacy multiplier estimates the authoritative session fallback")
	check(Selection.remaining_xp({"level":1,"xp":0},120)==214200 and Selection.remaining_xp({"level":2,"xp":10},3)==50 and Selection.remaining_xp({"level":120,"xp":0})==0,"remaining XP follows actual level*30 progress and cap")

	var mounted=fresh();mounted.session.set_character("100010");mounted.session.gm_raise_level(1,7);mounted.session.select_pet(-1)
	check(mounted.session.mount_pet(1),"real mount-only recipient setup")
	var mount_plan=Selection.new();mount_plan.prepare(mounted.encounter_catalog,MAP,CELL,mounted.session.snapshot(),{"xp":10},false);await finish(mount_plan)
	check(mount_plan.participant.kind=="mount" and mount_plan.participant.level==7 and is_equal_approx(float(row(mount_plan,88).expected_xp),7.5) and is_equal_approx(float(row(mount_plan,92).expected_xp),31.5),"actual mount level, gap and multiplier-before-60%-rounding determine 7.5/31.5 expected XP")
	mounted.session.experience_multiplier=10;mounted.encounter_rng.seed=9
	check(mounted.wild_encounter(MAP,CELL).ok,"mount-only settlement uses real original troop")
	var mount_reward:=0
	for enemy in mounted.session._pending.enemies:mount_reward+=preload("res://scripts/riding.gd").experience(int(enemy.reward_xp)*10,7,int(enemy.level))
	for turn in range(500):
		if not mounted.battle.snapshot().active:break
		mounted.battle_command({"action":"attack"})
	check(mounted.battle_state.get("settled",false) and int(mounted.battle_state.get("pet_reward_xp",[0,0])[1])==mount_reward,"actual mount-only battle settlement matches per-enemy estimate")
	mounted.queue_free();await process_frame

	# Actual source entries with controlled weights exercise duplicate caps and
	# the original finite 100-attempt roster loop, not a replacement battle core.
	var source: Dictionary=b.encounter_catalog.data.duplicate(true)
	var area: Dictionary=b.encounter_catalog.area_at(MAP,CELL).duplicate(true)
	area.groups=[{"id":88,"weight":1}];source.areas=[area]
	source.groups["88"].enemies=[{"id":119,"weight":9},{"id":122,"weight":1}]
	source.enemies["119"].max_count=1;source.enemies["122"].max_count=1
	var finite=Selection.new();finite.prepare(Catalog.new(source),MAP,CELL,p,{"xp":1},false);await finish(finite)
	var measured: Dictionary=row(finite,88)
	check(is_equal_approx(float(measured.enemy_counts[122]),0.55-0.5*pow(0.9,100)) and is_equal_approx(float(measured.expected_enemies),1.5-0.5*(pow(0.9,100)+pow(0.1,100))),"weighted slots/caps include exact chance of incomplete troop after 100 attempts")
	source.groups["88"].enemies=[{"id":119,"weight":1},{"id":119,"weight":1},{"id":120,"weight":1}]
	source.enemies["120"].max_count=2
	var duplicate=Selection.new();duplicate.prepare(Catalog.new(source),MAP,CELL,p,{"xp":1},false);await finish(duplicate)
	check(is_equal_approx(float(row(duplicate,88).expected_xp),2.25),"duplicate entries multiply per-enemy cap and keep original slot weight")

	var gated=Selection.new();gated.prepare(b.encounter_catalog,500,Vector2i(80,80),p,{"xp":10},false);await finish(gated)
	check(row(gated,788).is_empty(),"real local item-requiring group is absent without owning item")
	p.original_items=[18559];gated.prepare(b.encounter_catalog,500,Vector2i(80,80),p,{"xp":10},false);await finish(gated)
	check(not row(gated,788).is_empty(),"owning actual required item admits its local group")
	check(gated.rows.any(func(r):return int(r.group_id)==92001) and not 92001 in gated.allowed,"rare Lv1 groups remain ordinary local entries, never a fabricated high-level pool")

	# Find a real sequence whose first group is low and a later group high.
	var seed_value: int=-1;var expected_rolls:=[];var states:=[]
	for candidate_seed in range(100):
		var rng:=RandomNumberGenerator.new();rng.seed=candidate_seed
		var rolls:=[];var stream_states:=[]
		for attempt in range(30):
			var troop: Dictionary=b.encounter_catalog.roll(MAP,CELL,rng)
			rolls.append(troop);stream_states.append(rng.state)
			if not troop.is_empty() and int(troop.group_id) in plan.allowed:break
		if rolls.size()>2 and int(rolls.back().group_id) in plan.allowed:
			seed_value=candidate_seed;expected_rolls=rolls;states=stream_states;break
	check(seed_value>=0,"true source RNG supplies low-then-high encounter sequence")
	b.encounter_rng.seed=seed_value
	check(begin(b),"automatic training starts with selection")
	b.automation.training_selection.prepare(b.encounter_catalog,MAP,CELL,b.session.snapshot(),b.automation.settings,b.session.clone_squad_enabled)
	await finish(b.automation.training_selection)
	var deadline:=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
	var tick_start:=Time.get_ticks_usec();b.automation.tick_battle(0.016)
	check(b.automation.training_skipped==1 and Time.get_ticks_usec()-tick_start<1000000,"one compact tick yields after one low group instead of spinning")
	check(not b.battle_open and b.encounter_rng.state==states[0] and b.encounter_catalog.pressure==int(b.encounter_catalog.area_at(MAP,CELL).probability_min),"low roll consumes exact original RNG/pressure and never opens battle")
	while not b.battle_open and b.automation.running and Time.get_ticks_msec()<deadline:
		b.automation.step();await process_frame
	check(b.battle_open and b.automation.training_skipped==expected_rolls.size()-1 and same(expected_rolls.back(),b) and b.encounter_rng.state==states.back(),"first accepted high group keeps exact enemies, growth, drops and encounter RNG")
	var total:=0
	for enemy in b.session._pending.get("enemies",[]):total+=int(enemy.reward_xp)*10
	for turn in range(500):
		if not b.battle.snapshot().active:break
		b.battle_command({"action":"attack"})
	check(b.battle_state.get("settled",false) and int(b.battle_state.get("xp",0))==total and int(b.battle_state.get("pet_reward_xp",[0])[0])==total,"actual Battle/Session victory pays the predicted troop's exact target pet reward")
	b.handle({"type":"auto_stop"});b.queue_free();await process_frame

	var off=fresh();off.encounter_rng.seed=seed_value
	check(begin(off,false),"turning selection off starts normal training")
	off.automation.step()
	check(off.battle_open and same(expected_rolls[0],off) and off.automation.training_skipped==0,"off enters the original first low group unchanged")
	off.handle({"type":"auto_stop"});off.queue_free();await process_frame
	var manual=fresh();manual.encounter_rng.seed=seed_value
	check(manual.wild_encounter(MAP,CELL).ok and same(expected_rolls[0],manual),"ordinary/manual encounter is never filtered by character default")
	check(manual.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":[CELL.x,CELL.y]}).ok and manual.automation.single_battle,"enabling automation in an already-open battle finishes that battle")
	manual.handle({"type":"auto_stop"});manual.queue_free();await process_frame

	var prefs=fresh();prefs.handle({"type":"set_automation_settings","settings":{"training":{"select_troops":false,"borrow_troops":false}}})
	var save:="user://training-troops.json";check(prefs.session.save_game(save),"selection override saves in real character v6 file")
	var restored=fresh();check(restored.session.load_game(save) and not Settings.effective(restored.session.automation_settings()).training.select_troops,"selection override survives real save load")
	var independent=fresh();check(Settings.effective(independent.session.automation_settings()).training.select_troops,"another character retains default selection")
	for node in [prefs,restored,independent]:node.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save));DirAccess.remove_absolute(ProjectSettings.globalize_path(save+".bak"));await process_frame

	# Full actual find-pet cycle: capture low Lv1 first, then pick high groups
	# for that genuinely captured pet's showcase training phase.
	var flow=fresh();flow.handle({"type":"gm_raise_level","index":-1,"target":120});flow.handle({"type":"gm_heal"})
	var raw: Dictionary=Settings.stat_filter({},113)
	for condition in raw.conditions.values():condition.enabled=false
	check(flow.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":[CELL.x,CELL.y],"filter":{"templates":[113],"total":-8,"offsets":[],"clean_only":false,"fast":false,"showcase":true},"stat_filters":{"113":raw},"settings":{"capture_hp":100,"select_troops":true}}).ok,"real showcase flow starts")
	var saw_capture:=false;var saw_training:=false
	deadline=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
	while flow.automation.flow_active() and Time.get_ticks_msec()<deadline:
		flow._process(0.5)
		if flow.battle_open and flow.automation.flow_phase=="capture":saw_capture=saw_capture or int(flow.session._pending.get("group_id",-1))==88
		if flow.battle_open and flow.automation.flow_phase=="train":
			saw_training=int(flow.session._pending.get("group_id",-1)) in flow.automation.training_selection.allowed;break
		await process_frame
	check(saw_capture and saw_training and not flow.automation.flow_pet_id.is_empty(),"selection never blocks low-group capture; actual caught pet's showcase training enters a high group")
	flow.handle({"type":"auto_stop"});flow.queue_free();await process_frame

	var no_group=fresh();var old_art: Dictionary=Art._validation.duplicate()
	Art._validation["100297"]=false;Art._validation["100298"]=false
	no_group.encounter_rng.seed=555;var unchanged: int=no_group.encounter_rng.state
	check(begin(no_group),"no-eligible training starts validation")
	deadline=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
	while no_group.automation.running and Time.get_ticks_msec()<deadline:no_group.automation.tick_battle(0.016);await process_frame
	check(not no_group.automation.running and not no_group.battle_open and no_group.encounter_rng.state==unchanged and no_group.automation.stop_reason.contains("没有可进入"),"no renderable eligible group pauses clearly without roll or battle")
	Art._validation=old_art;no_group.queue_free();await process_frame
	print("TRAINING TROOPS: %d failures" % failures);quit(1 if failures else 0)
