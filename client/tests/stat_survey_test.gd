extends SceneTree
## 属性条件 最高 − x bootstrap and legacy native pool parity (server/automation.gd, scripts/pet_stat_filter.gd):
## the find-pet cycle's thresholds are the best Lv120 values among the player's
## own pets of the species minus x and rise as better pets arrive; with no pet
## of the species it first surveys for a while with no threshold and catches
## what the species' 保留规则 would keep of the candidates.
##
## The functional core runs for real (encounter rolls, Lv120 projection, the
## keep rule, the helper's candidate pool on a bounded run). Only the shell is
## faked: the survey clock, the helper process (a stand-in script) and battles
## (none are opened; the cycle is stepped by hand).
const Backend = preload("res://server/backend.gd")
const Automation = preload("res://server/automation.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const EncounterCatalog = preload("res://server/encounter_catalog.gd")
const Progression = preload("res://server/progression.gd")
const HuntRules = preload("res://scripts/pet_hunt_rules.gd")
const KeepRule = preload("res://scripts/keep_rule.gd")
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const MAP := 300
const CELL := [509,93]
const RULE := {"tiers":2,"per_tier":3,"order":["attack","speed","max_hp"],"champions":2,"champion_stats":["attack","defence","speed","max_hp"]}
var failures := 0
var fake_msec := 5000

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func new_backend():
	var backend = Backend.new()
	backend.handle({"type":"report_position","map_id":MAP,"cell":CELL})
	backend.set_process(false)
	root.add_child(backend)
	backend.automation.client_attached = false
	backend.encounter_rng.seed = 97531
	backend.automation.survey_clock = func():return fake_msec
	return backend

func key(entry: Dictionary) -> String:
	return "%d:%d" % [int(entry.index),int(entry.slot)]

func run() -> void:
	choose()
	await helper_pool()
	await cycle()
	print("STAT SURVEY: %d failures" % failures)
	quit(1 if failures else 0)

## The pick is exactly what 保留规则 keeps, best first.
func choose() -> void:
	var candidates: Array = []
	var stats := [[300,170,150,900],[298,176,152,910],[298,176,152,910],[290,180,154,950],[305,160,140,880],[292,174,150,990],[280,170,150,1200],[296,176,152,905]]
	for i in range(stats.size()):
		var s: Array = stats[i]
		candidates.append({"serial":i,"index":i,"slot":0,"template_id":92,"prediction":{"attack":s[0],"defence":s[1],"speed":s[2],"max_hp":s[3]}})
	var picks: Array = Automation.choose_by_rule(candidates,RULE)
	var pets: Array = candidates.map(func(c):return {"pet_id":"pet-%d" % int(c.serial),"level":120,"attack":c.prediction.attack,"defence":c.prediction.defence,"speed":c.prediction.speed,"max_hp":c.prediction.max_hp})
	var verdict: Dictionary = KeepRule.evaluate(pets,RULE)
	var kept: Array = pets.filter(func(p):return not verdict.reasons[str(p.pet_id)].is_empty()).map(func(p):return int(str(p.pet_id).trim_prefix("pet-")))
	var picked: Array = picks.map(func(p):return int(p.serial))
	var sorted_kept := kept.duplicate();sorted_kept.sort()
	var sorted_picked := picked.duplicate();sorted_picked.sort()
	check(sorted_picked==sorted_kept,"survey picks are what the keep rule keeps (%s)" % str(picked))
	var one: Dictionary = RULE.duplicate();one.per_tier = 1;one.champions = 0
	check(Automation.choose_by_rule(candidates,one).map(func(p):return int(p.serial)).has(1) and not Automation.choose_by_rule(candidates,one).map(func(p):return int(p.serial)).has(2),"of two identical candidates beyond the quota the earlier roll is picked")
	check(picked[0]==1 and picks[0].reasons.has("626档第1"),"best first: 三围合 626, then the rule's order (%s)" % str(picks[0].reasons))
	check(picked.has(6) and picked.has(4),"single-stat champions are picked too (血 1200, 攻击 305)")

## The helper's candidate pool over a bounded run equals the keep rule applied
## to every candidate the GDScript scan sees on the same rolls.
func helper_pool() -> void:
	var backend = new_backend()
	backend.handle({"type":"set_automation_settings","settings":{"hunt":{"keep_rule":{"per_tier":2,"order":["max_hp","speed"],"champions":1,"champion_stats":["defence"]}}}})
	backend.automation.flow_settings_overrides=backend.session.automation_settings()
	var pool_rule:Dictionary=backend.automation.shared_keep_rule()
	var catalog: Dictionary = backend.encounter_catalog.data
	var area: Dictionary = backend.encounter_catalog.area_at(MAP,Vector2i(CELL[0],CELL[1]))
	var data: Dictionary = catalog.duplicate();data.areas = [area]
	var trimmed := EncounterCatalog.new(data)
	var rolls := 20000
	var run_seed := 13579
	var filter := {"template":92,"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"usable":[92],"limit":rolls}
	FastHunt.threads = 2
	var helper := FastHunt.new()
	var survey_filter := func(_id):return StatFilter.defaults(92)
	check(helper.launch(catalog,area,filter,true,survey_filter,run_seed,0,2,{92:pool_rule}),"the helper starts a survey")
	var report := {}
	var deadline := Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		report = helper.poll(true)
		if not report.is_empty() and str(report.kind)!="progress":break
		await process_frame
	check(str(report.get("kind",""))=="limit" and int(report.get("index",0))==rolls,"survey rolls are not hits: the bounded run reaches its limit (%s)" % str(report.get("kind","")))
	var expected: Array = []
	var rng := RandomNumberGenerator.new()
	for i in range(rolls):
		rng.seed = FastHunt.roll_seed(run_seed,i)
		var troop: Dictionary = trimmed.roll(MAP,Vector2i(CELL[0],CELL[1]),rng)
		for slot in range(troop.get("enemies",[]).size()):
			var actor: Dictionary = troop.enemies[slot]
			if not actor.can_capture or int(actor.template_id)!=92 or int(actor.level)!=1:continue
			var p := Progression.project_pet(actor,120)
			expected.append({"serial":i*16+slot,"index":i,"slot":slot,"template_id":92,"prediction":{"attack":int(p.attack),"defence":int(p.defence),"speed":int(p.speed),"max_hp":int(p.max_hp)}})
	var wanted: Array = Automation.choose_by_rule(expected,pool_rule).map(key)
	var got: Array = report.get("candidates",[]).map(key)
	wanted.sort();got.sort()
	check(expected.size()>50 and got==wanted,"the pool (%d of %d candidates) is exactly what the keep rule keeps" % [got.size(),expected.size()])
	var same := true
	for c in report.get("candidates",[]):
		for e in expected:
			if key(e)==key(c) and e.prediction!=c.prediction:same = false
	check(same,"with the same predicted Lv120 stats (血 included)")
	helper.stop()
	backend.queue_free()

## A stand-in for the helper that reports progress and waits to be stopped.
## No timer: first eligible real roll establishes a baseline immediately.
func cycle() -> void:
	var backend = new_backend()
	var automation = backend.automation
	backend.session.grant_starter_pets()
	for list in ["pets","pet_storage"]:
		backend.session._profile[list] = backend.session._profile[list].filter(func(pet):return KeepRule.species_pets({"pets":[pet]},92).is_empty())
	backend.session._profile.active_pet = 0 if not backend.session._profile.pets.is_empty() else -1
	backend.session._profile.ride_pet = -1
	var filter := {"template":92,"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"auto_capture":false,"limit":0,"rate":0,"fast":false,"showcase":false}
	check(backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL,"filter":filter}).ok,"no-background cycle starts without owning this species")
	check(automation.owned_maxima(92).is_empty(),"species has no initial owned baseline")
	var deadline := Time.get_ticks_msec()+30000
	while automation.showcase_queue.is_empty() and automation.hunt_running and Time.get_ticks_msec()<deadline:automation.scan_once()
	check(not automation.showcase_queue.is_empty() and automation.survey.is_empty() and automation.survey_picks.is_empty(),"first qualifying original roll queues immediately without survey")
	if not automation.showcase_queue.is_empty():
		var entry: Dictionary = automation.showcase_queue[0]
		var best: Dictionary = automation.species_maxima(92)
		check(int(best.sum)==int(entry.prediction.attack)+int(entry.prediction.defence)+int(entry.prediction.speed),"real queue supplies same-species baseline")
		check(int(automation.filter_for(92).conditions.sum.value)==int(best.sum)-1,"later candidates use the dynamically raised threshold")
		check(StatFilter.evaluate(entry.prediction,automation.filter_excluding(entry,[])),"first queued candidate is never rejected against itself")
		var absolute: Dictionary = automation.raw_filter_for(92).duplicate(true)
		absolute.threshold_mode="absolute";absolute.mode="all"
		absolute.conditions.sum.value=3000
		automation.flow_stat_filters[92]=absolute
		check(not automation.accepts_prediction(entry.actor),"absolute threshold remains strict, including without a baseline")
	backend.handle({"type":"auto_stop"});backend.queue_free();await process_frame
