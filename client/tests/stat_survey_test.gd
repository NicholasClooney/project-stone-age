extends SceneTree
## 属性条件 最高 − x and 摸底 (server/automation.gd, scripts/pet_stat_filter.gd):
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
	await absolute_mode()
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
	check(helper.launch(catalog,area,filter,true,survey_filter,run_seed,0,2,{92:RULE}),"the helper starts a survey")
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
	var wanted: Array = Automation.choose_by_rule(expected,RULE).map(key)
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
func fake_helper() -> String:
	var path := ProjectSettings.globalize_path("user://fast-hunt-idle.sh")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string("#!/bin/sh\necho 'progress 0 0 0 -9 0 -1 -1' > \"$2\"\nsleep 30\n")
	file.close()
	OS.execute("chmod",["+x",path])
	return path

func input_threshold(automation, metric_index: int) -> String:
	var path: String = automation.fast_hunt.input_path
	if path.is_empty() or not FileAccess.file_exists(path):return ""
	var in_filters := false
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.begins_with("stat_filters "):in_filters = true
		elif in_filters and line.begins_with("92 "):return line.split(" ")[3+metric_index*3+1]
	return ""

func uncaught(session, roll: int) -> Array:
	return session.release_events.filter(func(e):return bool(e.get("uncaught",false)) and int(e.roll)==roll and str(e.source)=="门槛已提高")

## 最高 + 1 on 攻击 (x = −1), or 三围合 ≥ 最高: a queued hit is judged against
## owned pets and the other pending hits ranked above it, never itself.
func plus_n(automation, session, actor92: Dictionary) -> void:
	var saved: Dictionary = automation.raw_filter_for(92).duplicate(true)
	var plus_one: Dictionary = saved.duplicate(true)
	plus_one.mode = "any"
	for metric in StatFilter.METRICS:plus_one.conditions[metric] = {"enabled":false,"minus":0}
	plus_one.conditions.attack = {"enabled":true,"minus":-1}
	plus_one.conditions.sum = {"enabled":true,"minus":0}
	automation.flow_stat_filters[92] = plus_one
	automation.refresh_maxima()
	var owned: Dictionary = automation.owned_maxima(92)
	var edge := {"attack":int(owned.attack)+1,"defence":1,"speed":1,"max_hp":1}
	automation._showcase_add({"index":10,"slot":2,"run_seed":1234567890123456789,"actor":actor92,"troop":{},"quality":{},"prediction":edge})
	check(automation.showcase_queue.size()==1 and uncaught(session,11).is_empty(),"a hit beating the owned best 攻击 by 1 stays queued though it is the new 最高 (三围合 below)")
	check(int(automation.filter_for(92).conditions.attack.value)==int(owned.attack)+2,"new hits now need 攻击 ≥ %d" % (int(owned.attack)+2))
	var edge2 := {"attack":int(owned.attack)+2,"defence":1,"speed":1,"max_hp":1}
	automation._showcase_add({"index":11,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":edge2})
	check(automation.showcase_queue.size()==1 and automation.showcase_queue[0].prediction==edge2,"a better one drops the first (it no longer beats the best by 1) and stays itself")
	var logged := uncaught(session,11)
	check(logged.size()==1 and str(logged[0].where)=="未捕获" and str(logged[0].run_seed)=="1234567890123456789" and int(logged[0].slot)==2 and str(logged[0].reason).begins_with("门槛已提高（") and logged[0].beaten_by.size()==1 and str(logged[0].beaten_by[0].pet_id)=="第12组","the dropped hit is in 放生记录 with its seed and slot: %s" % str(logged))
	check(str(automation.showcase_log.back().text).contains("第11组"),"the info line names it: %s" % automation.showcase_log.back().text)
	# Two equal best hits: the earlier roll stays, never both dropped.
	automation._showcase_add({"index":12,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":edge2.duplicate()})
	check(automation.showcase_queue.size()==1 and int(automation.showcase_queue[0].index)==11 and uncaught(session,13).size()==1,"of two equal best hits the earlier one stays")
	# The queue ranks by the 保留规则 order (攻击 first by default), not by
	# 三围合: B, with the higher 攻击 but the lower 三围合, leads, and A, which no
	# longer beats B's 攻击 by 1, is let go. At its turn B is judged without
	# itself, against owned pets only.
	automation.showcase_queue = []
	var low_sum := int(owned.sum)-20
	var a := {"attack":int(owned.attack)+1,"defence":low_sum-int(owned.attack)-2,"speed":1,"max_hp":1}
	var b := {"attack":int(owned.attack)+5,"defence":low_sum-int(owned.attack)-10,"speed":1,"max_hp":1}
	automation._showcase_add({"index":20,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":a})
	automation._showcase_add({"index":21,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":b})
	check(automation.showcase_queue.size()==1 and automation.showcase_queue[0].prediction==b and uncaught(session,21).size()==1,"the higher 攻击 leads though its 三围合 is lower; the other no longer qualifies")
	automation.flow_phase = "hunt"
	automation._showcase_capture()
	check(uncaught(session,22).is_empty() and int(automation.flow_target_filter.conditions.attack.value)==int(owned.attack)+1,"at its turn the best is judged against owned pets only: 攻击 ≥ %s" % str(automation.flow_target_filter.conditions.attack.get("value")))
	check(not str(automation.showcase_log.back().text).begins_with("门槛已提高"),"and not let go: %s" % automation.showcase_log.back().text)
	automation.showcase_current = {}
	automation.showcase_queue = []
	automation.flow_stat_filters[92] = saved
	automation.flow_phase = "hunt"

## The find-pet cycle: cold start, survey, picks, then rolling thresholds.
func cycle() -> void:
	var backend = new_backend()
	var automation = backend.automation
	var session = backend.session
	session.grant_starter_pets()
	# No blue dragon of the player's own: nothing to count 最高 from.
	for list in ["pets","pet_storage"]:
		session._profile[list] = session._profile[list].filter(func(pet):return KeepRule.species_pets({"pets":[pet]},92).is_empty())
	session._profile.active_pet = 0 if not session._profile.pets.is_empty() else -1
	session._profile.ride_pet = -1
	backend.handle({"type":"set_automation_settings","settings":{"stat_filters":{"92":{"keep_rule":RULE}}}})
	var filter := {"template":92,"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"auto_capture":false,"limit":0,"rate":0,"fast":false,"showcase":true}
	var reply: Dictionary = backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL,"filter":filter,"settings":{"capture_hp":100}})
	check(reply.ok and automation.flow_phase=="hunt","a find-pet cycle starts (%s)" % str(reply))
	check(automation.owned_maxima(92).is_empty() and StatFilter.needs_survey(automation.raw_filter_for(92),automation.species_maxima(92)),"no blue dragon owned: 最高 − 1 has nothing to count from")
	automation._hunt_process(0.016)
	var status: Dictionary = automation.status().flow.survey
	check(bool(status.active) and is_equal_approx(float(status.remaining),120.0) and status.names==["扬奇洛斯"],"a 2-minute survey starts (%s)" % str(status))
	check(automation.showcase_log.back().kind=="survey" and str(automation.showcase_log.back().text).contains("摸底"),"the info block says so: %s" % automation.showcase_log.back().text)
	for i in range(60):
		if automation.survey.candidates.size()>=12:break
		automation._hunt_process(0.016)
	check(automation.survey.candidates.size()>=12 and automation.showcase_queue.is_empty() and automation.flow_predicted_rejects==0,"survey candidates are collected, not queued or rejected (%d)" % automation.survey.candidates.size())
	fake_msec += 45000
	status = automation.status().flow.survey
	check(is_equal_approx(float(status.remaining),75.0) and int(status.candidates)==automation.survey.candidates.size(),"the status shows the time left and the candidates")
	var candidates: Array = automation.survey.candidates.values()
	fake_msec += 75000
	automation._hunt_process(0.016)
	var wanted: Array = Automation.choose_by_rule(candidates,RULE).map(key)
	var queued: Array = automation.showcase_queue.map(key)
	wanted.sort();queued.sort()
	check(automation.survey.is_empty() and queued==wanted and automation.showcase_queue.all(func(e):return bool(e.get("survey",false))),"when time is up the keep rule's picks are queued for capture (%d)" % queued.size())
	check(str(automation.status().flow.survey.last).begins_with("摸底结束") and automation.showcase_log.back().kind=="survey","the info block tells what was picked: %s" % automation.status().flow.survey.last)
	var picks_best := StatFilter.maxima(automation.showcase_queue.map(func(e):return e.prediction))
	check(automation.species_maxima(92)==picks_best and int(automation.filter_for(92).conditions.sum.value)==int(picks_best.sum)-1,"picks on their way count as 最高: need 三围合 ≥ %d" % (int(picks_best.sum)-1))
	check(automation.thresholds_text().contains("最高 %d − 1 = %d" % [int(picks_best.sum),int(picks_best.sum)-1]),"the status reads %s" % automation.thresholds_text())
	automation._hunt_process(0.016)
	check(automation.survey.is_empty(),"no second survey while picks wait")

	# A pick (or anything) caught raises 最高: the thresholds roll upward.
	var better: Dictionary = automation.showcase_queue[0].actor.duplicate(true)
	better.pet_id = "pet-better";better.level = 120;better.species = "original_92"
	better.attack = int(picks_best.attack)+5;better.defence = int(picks_best.defence)+5;better.speed = int(picks_best.speed)
	session._profile.pet_storage.append(better)
	automation.refresh_maxima()
	check(int(automation.filter_for(92).conditions.sum.value)==int(better.attack)+int(better.defence)+int(better.speed)-1,"a better pet raises the threshold to %d" % automation.filter_for(92).conditions.sum.value)
	# A queued hit below the new threshold is let go at its turn, no battle.
	var low: Dictionary = automation.showcase_queue[0].duplicate(true)
	low.erase("survey");low.prediction = {"attack":1,"defence":1,"speed":1,"max_hp":1}
	automation.showcase_queue.push_front(low)
	automation._showcase_capture()
	check(not backend.battle_open and automation.flow_phase=="hunt" and automation.showcase_log.back().kind=="dropped" and str(automation.showcase_log.back().text).begins_with("门槛已提高"),"a queued hit under the risen threshold is dropped: %s" % automation.showcase_log.back().text)

	# The running helper restarts with the new thresholds.
	FastHunt.helper_override = fake_helper()
	automation.hunt_fast_wanted = true
	automation.hunt_fast_note = ""
	automation._hunt_process(0.016)
	var first_pid: int = automation.fast_hunt.pid
	var before := input_threshold(automation,0)
	check(automation.fast_hunt.running() and float(before)==float(automation.filter_for(92).conditions.sum.value),"the helper scans with 三围合 ≥ %s" % before)
	var best: Dictionary = better.duplicate(true);best.pet_id = "pet-best";best.attack = int(better.attack)+3
	session._profile.pet_storage.append(best)
	automation._hunt_process(0.016)
	var after := input_threshold(automation,0)
	check(automation.fast_hunt.running() and automation.fast_hunt.pid!=first_pid and float(after)==float(before)+3,"a better pet restarts it with 三围合 ≥ %s" % after)
	automation.fast_hunt.stop()
	DirAccess.remove_absolute(FastHunt.helper_override)
	FastHunt.helper_override = ""

	# Queued hits count as 最高 too: a better hit raises the thresholds at once
	# and the queued ones it leaves below them are let go in one line.
	automation.showcase_queue = []
	automation.refresh_maxima()
	var actor92: Dictionary = better.duplicate(true)
	actor92.erase("pet_id")
	var ok_hit := {"attack":int(best.attack),"defence":int(best.defence),"speed":int(best.speed)+1,"max_hp":1}
	automation._showcase_add({"index":1,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":ok_hit})
	check(automation.showcase_queue.size()==1,"a hit above the owned best queues")
	var top_hit := {"attack":int(best.attack)+10,"defence":int(best.defence),"speed":int(best.speed)+10,"max_hp":1}
	automation._showcase_add({"index":2,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":top_hit})
	var top_sum: int = int(top_hit.attack)+int(top_hit.defence)+int(top_hit.speed)
	check(int(automation.species_maxima(92).sum)==top_sum and int(automation.filter_for(92).conditions.sum.value)==top_sum-1,"the queued best counts as 最高: need 三围合 ≥ %d" % (top_sum-1))
	check(automation.showcase_queue.size()==1 and automation.showcase_queue[0].prediction==top_hit,"the queued hit it outclasses is let go at once")
	check(str(automation.showcase_log.back().text).contains("排队中的第2组") and str(automation.showcase_log.back().text).contains("不再够格"),"in one line naming the roll: %s" % automation.showcase_log.back().text)
	automation.showcase_queue = []
	plus_n(automation,session,actor92)

	# Without 后台搜宠 the picks wait for the ordinary capture instead.
	automation.hunt_fast_wanted = false
	session._profile.pet_storage = session._profile.pet_storage.filter(func(pet):return KeepRule.species_pets({"pets":[pet]},92).is_empty())
	automation.showcase_queue = []
	automation.flow_showcase = false
	automation.refresh_maxima()
	automation._survey_process()
	check(not automation.survey.is_empty(),"with no blue dragon again a new survey starts")
	for i in range(5000):
		if automation.survey.candidates.size()>=3:break
		automation.scan_once()
	fake_msec += 120000
	automation._survey_process()
	check(automation.survey.is_empty() and not automation.survey_picks.is_empty() and automation.showcase_queue.is_empty(),"without 后台搜宠 the picks wait in survey_picks (%d)" % automation.survey_picks.size())

	# A survey pick counts as found even under the threshold.
	var caught: Dictionary = better.duplicate(true);caught.pet_id = "pet-survey";caught.attack = 10;caught.defence = 10;caught.speed = 10
	session._profile.pets.append(caught)
	session._profile.active_pet = session._profile.pets.size()-1
	automation.flow_pet_id = "pet-survey";automation.flow_phase = "train"
	automation.flow_target_filter = StatFilter.resolve(automation.raw_filter_for(92),{"sum":999,"attack":999})
	automation.flow_target_survey = true
	var collected: int = automation.flow_collected_count
	automation.complete_trained_pet(caught)
	check(automation.flow_collected_count==collected+1 and automation.flow_last_result.contains("摸底选中"),"a survey pick is stored as found: %s" % automation.flow_last_result)
	backend.handle({"type":"auto_stop"})
	backend.queue_free()
	await process_frame

func input_has_survey(automation) -> bool:
	for line in FileAccess.get_file_as_string(automation.fast_hunt.input_path).split("\n"):
		if line.begins_with("survey "):return true
	return false

func set_filter(backend, patch: Dictionary) -> void:
	backend.handle({"type":"set_automation_settings","settings":{"stat_filters":{"92":patch}}})

## 绝对：≥ 数值: fixed thresholds with no pet of the species and no 摸底; a
## running cycle follows the player's edits (mode and values) at once.
func absolute_mode() -> void:
	var backend = new_backend()
	var automation = backend.automation
	var session = backend.session
	session.grant_starter_pets()
	for list in ["pets","pet_storage"]:
		session._profile[list] = session._profile[list].filter(func(pet):return KeepRule.species_pets({"pets":[pet]},92).is_empty())
	session._profile.active_pet = 0 if not session._profile.pets.is_empty() else -1
	session._profile.ride_pet = -1
	set_filter(backend,{"keep_rule":RULE,"threshold_mode":"absolute"})
	var filter := {"template":92,"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"auto_capture":false,"limit":0,"rate":0,"fast":false,"showcase":true}
	var reply: Dictionary = backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL,"filter":filter,"settings":{"capture_hp":100}})
	check(reply.ok and automation.flow_phase=="hunt","an absolute find-pet cycle starts (%s)" % str(reply))
	var chosen: Dictionary = automation.filter_for(92)
	check(automation.owned_maxima(92).is_empty() and int(chosen.conditions.sum.value)==624 and int(chosen.conditions.attack.value)==293,"absolute: no blue dragon owned, still 三围合 ≥ 624 or 攻击 ≥ 293")
	automation._hunt_process(0.016)
	check(automation.survey.is_empty() and not bool(automation.status().flow.survey.active),"no 摸底 in absolute mode")
	check(automation.thresholds_text()=="扬奇洛斯：三围合 ≥ 624，或 攻击 ≥ 293","the status reads %s" % automation.thresholds_text())

	# The helper gets the fixed values and no survey section.
	FastHunt.helper_override = fake_helper()
	automation.hunt_fast_wanted = true
	automation.hunt_fast_note = ""
	automation._hunt_process(0.016)
	var pid: int = automation.fast_hunt.pid
	check(automation.fast_hunt.running() and float(input_threshold(automation,0))==624.0 and float(input_threshold(automation,1))==293.0 and not input_has_survey(automation),"the helper scans with ≥ 624 / ≥ 293 and no 摸底")

	# Queued hits are judged against the fixed values only: a better hit
	# raises nothing, so a lower one that passes stays.
	var actor92 := {}
	for i in range(5000):
		var troop: Dictionary = automation.roll_at(i)
		for enemy in troop.get("enemies",[]):
			if int(enemy.template_id)==92 and actor92.is_empty():actor92 = enemy.duplicate(true)
		if not actor92.is_empty():break
	var fair := {"attack":294,"defence":170,"speed":150,"max_hp":900}
	var great := {"attack":320,"defence":190,"speed":160,"max_hp":1000}
	automation._showcase_add({"index":1,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":fair})
	automation._showcase_add({"index":2,"slot":0,"run_seed":1,"actor":actor92,"troop":{},"quality":{},"prediction":great})
	check(automation.showcase_queue.size()==2 and int(automation.filter_for(92).conditions.attack.value)==293,"a better queued hit does not raise fixed values: both stay queued")

	# A raised value applies to the running cycle at once: the helper restarts
	# with it and the queued hit now below it is let go.
	set_filter(backend,{"conditions":{"attack":{"value":300},"sum":{"value":640}}})
	check(automation.showcase_queue.size()==1 and automation.showcase_queue[0].prediction==great and automation.showcase_log.any(func(line):return str(line.kind)=="dropped" and str(line.text).contains("第2组")),"raising 攻击 to 300 lets the queued 294 go")
	check(automation.showcase_log.any(func(line):return str(line.kind)=="settings" and str(line.text).contains("三围合 ≥ 640")),"the info block says the edit applies now")
	automation._hunt_process(0.016)
	check(automation.fast_hunt.running() and automation.fast_hunt.pid!=pid and float(input_threshold(automation,0))==640.0 and float(input_threshold(automation,1))==300.0,"the helper restarts with ≥ 640 / ≥ 300")

	# Back to relative with no blue dragon: 摸底 starts; to absolute again ends it.
	set_filter(backend,{"threshold_mode":"relative"})
	automation.showcase_queue = []
	automation._hunt_process(0.016)
	check(not automation.survey.is_empty() and input_has_survey(automation),"switched to 最高 − x with no blue dragon: 摸底 starts and the helper surveys")
	set_filter(backend,{"threshold_mode":"absolute"})
	check(automation.survey.is_empty() and str(automation.showcase_log.back().kind)=="settings","switched back to fixed values: the 摸底 ends without picks")
	pid = automation.fast_hunt.pid
	automation._hunt_process(0.016)
	check(automation.fast_hunt.pid!=pid and not input_has_survey(automation) and float(input_threshold(automation,0))==640.0,"and the helper hunts with ≥ 640 again (the values were kept)")

	# The mode is kept over a restart (hunt.resume).
	var state: Dictionary = automation.resume_state()
	check(str(state.get("flow",{}).get("flow_stat_filters",{}).get(92,{}).get("threshold_mode",""))=="absolute","the resume state keeps threshold_mode")
	automation.fast_hunt.stop()
	DirAccess.remove_absolute(FastHunt.helper_override)
	FastHunt.helper_override = ""
	backend.handle({"type":"auto_stop"})
	backend.queue_free()
	await process_frame
