extends SceneTree
## 找到N只后停止 (hunt.stop_after) is one count for the whole find-pet run,
## every species alike: qualifiers count, and with no 属性条件 every pet trained
## to Lv.120 counts (stored, then the run goes on); 0 never stops, 1 stops at the
## first to compare. Rejects (未达标已存仓) do not count. The real backend and
## automation judge real Lv.120 pets; only the hunt and capture are skipped.
const Backend = preload("res://server/backend.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const SAVE := "user://hunt-stop-after-test.json"
## Three species hunted at once, like 左迪洛斯 / 巴朵兰恩 / 斑尼迪克.
const PLAIN := 194
const OTHER := 302
const PICKY := 92
var failures := 0
var serial := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clear_save() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))

func set_settings(backend, patch: Dictionary) -> Dictionary:
	return backend.handle({"type":"set_automation_settings","settings":patch})

## A run starting as find_pet does: the profile's settings snapshot and filters.
func begin(backend) -> void:
	var automation = backend.automation
	automation.flow_settings_overrides = backend.session.automation_settings()
	automation.flow_stat_filters = Settings.stat_filters(automation.flow_settings_overrides)
	automation.flow_kept_count = 0;automation.flow_collected_count = 0;automation.flow_stored_count = 0;automation.flow_run_reject_ids = []
	automation.flow_phase = "idle"

## A freshly caught pet of `template` at Lv.120 is judged by the cycle.
func train(backend, template: int, attack: int) -> Dictionary:
	var automation = backend.automation
	var pet: Dictionary = backend.session._profile.pets[0].duplicate(true)
	serial += 1
	pet.pet_id = "pet-run-%d" % serial;pet.template_id = template;pet.species = "original_%d" % template;pet.level = 120
	pet.attack = attack;pet.defence = 150;pet.speed = 120;pet.erase("gm_modified");pet.erase("favorite")
	backend.session._profile.pets.append(pet)
	automation.flow_pet_id = pet.pet_id
	automation.flow_target_survey = false
	automation.flow_target_filter = automation.filter_for(template).duplicate(true)
	automation.flow_phase = "train"
	automation.complete_trained_pet(pet)
	return pet

func stored(backend, pet: Dictionary) -> bool:
	return backend.session.snapshot().pet_storage.any(func(p):return str(p.pet_id)==str(pet.pet_id))

func carried(backend, pet: Dictionary) -> bool:
	return backend.session.snapshot().pets.any(func(p):return str(p.pet_id)==str(pet.pet_id))

func run() -> void:
	clear_save()
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	backend.save_path = SAVE
	backend.session.grant_starter_pets()
	var automation = backend.automation
	# 斑尼迪克 has 属性条件 (攻击 ≥ 290); the other two none.
	set_settings(backend,{"stat_filters":{str(PICKY):{"mode":"any","threshold_mode":"absolute","conditions":{"sum":{"enabled":false},"attack":{"enabled":true,"value":290}}},
		str(PLAIN):{"conditions":{"sum":{"enabled":false}}},str(OTHER):{"conditions":{"sum":{"enabled":false}}}}})
	check(not automation.filter_for(PLAIN).conditions.values().any(func(c):return c.enabled) and automation.filter_for(PICKY).conditions.attack.enabled,"the run has one species with conditions and two without")

	# ---- 0: the user's case, a plain species no longer stops the run ----
	set_settings(backend,{"hunt":{"stop_after":0}})
	begin(backend)
	check(automation.collect_target_text()=="不限" and str(automation.status().flow.collect_target)=="不限","the status shows 不限 for 0")
	var first := train(backend,PLAIN,280)
	check(automation.flow_phase=="restart" and stored(backend,first) and automation.flow_collected_count==1,"0: the first plain pet at Lv.120 is stored and the run goes on (%s · %s)" % [automation.flow_phase,automation.flow_reason])
	check(automation.flow_last_result.begins_with("已满120级已存仓"),"and the result says it was kept (%s)" % automation.flow_last_result)
	var stored_plain: Dictionary = backend.session.snapshot().pet_storage.filter(func(p):return str(p.pet_id)==str(first.pet_id))[0]
	check(not stored_plain.get("auto_hunt",false) and not stored_plain.get("auto_qualified",false),"a kept plain pet is never pruned as a reject and not labelled 达标")
	for turn in range(5):train(backend,[PLAIN,OTHER,PICKY][turn%3],295)
	check(automation.flow_phase=="restart" and automation.flow_collected_count==6,"0 keeps going over every species (%d kept)" % automation.flow_collected_count)
	var reject := train(backend,PICKY,200)
	check(automation.flow_phase=="restart" and automation.flow_collected_count==6 and automation.flow_last_result.begins_with("未达标已存仓") and stored(backend,reject),"a reject is stored but not counted")

	# ---- 2: stops after two kept pets, across species ----
	set_settings(backend,{"hunt":{"stop_after":2}})
	begin(backend)
	check(automation.collect_target_text()=="2","the status shows the run-wide target")
	var one := train(backend,PLAIN,280)
	check(automation.flow_phase=="restart" and stored(backend,one),"2: the first (plain) pet is stored and the run goes on")
	train(backend,PICKY,200)
	check(automation.flow_phase=="restart" and automation.flow_collected_count==1,"a reject in between does not count")
	var two := train(backend,PICKY,300)
	check(automation.flow_phase=="compare" and automation.flow_collected_count==2 and stored(backend,two),"the second, a qualifier of another species, ends the run at comparison")
	check(automation.flow_reason.begins_with("收集完成：本轮找到2只达标宠物"),"with the collect text (%s)" % automation.flow_reason)
	check(str(automation.stop_events.back().reason).begins_with("收集完成：本轮找到2只"),"and the stop record")
	set_settings(backend,{"hunt":{"stop_after":2}})
	begin(backend)
	train(backend,OTHER,280);train(backend,PLAIN,280)
	check(automation.flow_phase=="compare" and automation.flow_reason.begins_with("收集完成：本轮找到2只宠物"),"two plain pets of two species end it too (%s)" % automation.flow_reason)

	# ---- 1: the classic stop at the first, plain or qualified ----
	set_settings(backend,{"hunt":{"stop_after":null}})
	check(int(Settings.effective(backend.session.automation_settings()).hunt.stop_after)==0,"0 (keep going) is the default")
	set_settings(backend,{"hunt":{"stop_after":1}})
	begin(backend)
	var classic := train(backend,PLAIN,280)
	check(automation.flow_phase=="compare" and carried(backend,classic) and automation.flow_reason.begins_with("新伙伴已达到120级"),"1: the first plain pet stays carried and the run stops to compare")
	begin(backend)
	var good := train(backend,PICKY,300)
	check(automation.flow_phase=="compare" and carried(backend,good) and automation.flow_reason.begins_with("已达标"),"1: a qualifier stops as before")
	begin(backend)
	train(backend,PICKY,200)
	check(automation.flow_phase=="restart" and automation.flow_collected_count==0,"1: a reject is stored and the run goes on, as before")

	# ---- a running cycle follows the player's change, and keeps it over a restart ----
	automation.flow_phase = "restart"
	set_settings(backend,{"hunt":{"stop_after":3}})
	check(automation.run_stop_after()==3 and automation.status().flow.collect_target=="3","a running cycle takes the new count at once")
	check("flow_settings_overrides" in automation.RESUME_FLOW_FIELDS and int(Settings.effective(automation.flow_settings_overrides).hunt.stop_after)==3,"the count is part of the run's settings the resume file keeps")
	automation.flow_phase = "idle"

	# ---- an older client's per-species count is accepted and ignored ----
	var reply := set_settings(backend,{"stat_filters":{str(PLAIN):{"stop_after":0}}})
	check(reply.ok and not backend.session.automation_settings().get("stat_filters",{}).get(str(PLAIN),{}).has("stop_after") and automation.run_stop_after()==3,"an older client's per-species stop count changes nothing")

	backend.queue_free()
	clear_save()
	await process_frame
	print("HUNT STOP AFTER: %d failures" % failures)
	quit(1 if failures else 0)
