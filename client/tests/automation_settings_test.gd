extends SceneTree
## Automation settings live in the character profile: set_automation_settings
## deep-merges and validates partial updates, null returns a value to its
## default, the overrides persist through a save, older saves get defaults, and
## automation runs use the profile's settings.
const Backend = preload("res://server/backend.gd")
const GameSession = preload("res://server/game_session.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const StatFilter = preload("res://scripts/pet_stat_filter.gd")
const SAVE := "user://automation-settings-test.json"
const MAP := 100
const CELL := [637,493]
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func clear_save() -> void:
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+suffix))

func set_settings(backend, patch: Variant) -> Dictionary:
	return backend.handle({"type":"set_automation_settings","settings":patch})

func overrides(backend) -> Dictionary:
	return backend.session.snapshot().automation_settings

func run() -> void:
	clear_save()
	# ---- defaults come from the data file ----
	var defaults: Dictionary = Settings.defaults()
	check(int(defaults.training.hp)==10 and int(defaults.training.limit)==1000 and int(defaults.hunt.total)==8 and not defaults.has("comment"),"defaults load from data/automation_defaults.json without notes")
	var blue := StatFilter.defaults(92)
	check(blue.mode=="any" and int(blue.stop_after)==0 and blue.conditions.sum.enabled and int(blue.conditions.sum.keep)==15 and int(blue.conditions.attack.keep)==10 and blue.conditions.attack.enabled and int(blue.conditions.attack.minus)==1,"blue dragon keeps its per-species defaults")
	var other := StatFilter.defaults(194)
	check(int(other.stop_after)==1 and not StatFilter.enabled(other) and int(other.conditions.sum.minus)==1 and not other.conditions.sum.has("value"),"other species use the general stat filter")

	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	backend.save_path = SAVE
	check(overrides(backend).is_empty(),"a new character stores no overrides")
	var events := []
	backend.event.connect(func(message: Dictionary):if str(message.type)=="profile":events.append(message))

	# ---- merge ----
	var reply := set_settings(backend,{"training":{"hp":35},"hunt":{"rate":250,"offsets":[1,0,-1,2]}})
	check(reply.ok and overrides(backend)=={"training":{"hp":35},"hunt":{"rate":250,"offsets":[1,0,-1,2]}},"a partial update stores only the changed values")
	check(not events.is_empty() and events[-1].profile.automation_settings.training.hp==35,"the change is published to every client as a profile event")
	reply = set_settings(backend,{"training":{"limit":7},"stat_filters":{"92":{"conditions":{"sum":{"minus":3}}}}})
	var stored := overrides(backend)
	check(reply.ok and int(stored.training.hp)==35 and int(stored.training.limit)==7 and int(stored.hunt.rate)==250,"a second update deep-merges with the first")
	var effective: Dictionary = Settings.stat_filter(stored,92)
	check(int(effective.conditions.sum.minus)==3 and int(effective.conditions.sum.keep)==15 and int(effective.stop_after)==0,"a stat override merges over the species defaults")
	check(stored.stat_filters.keys()==["92"] and stored.stat_filters["92"]=={"conditions":{"sum":{"minus":3}}},"stat filters are keyed by template id")
	check(not bool(set_settings(backend,{"stat_filters":{"92":{"conditions":{"sum":{"value":630}}}}}).get("ok",true)) and not bool(set_settings(backend,{"stat_filters":{"92":{"conditions":{"sum":{"minus":1001}}}}}).get("ok",true)),"fixed thresholds are gone; x is at most 1000")
	check(bool(set_settings(backend,{"stat_filters":{"92":{"conditions":{"sum":{"minus":-5}}}}}).get("ok",false)) and not bool(set_settings(backend,{"stat_filters":{"92":{"conditions":{"sum":{"minus":-101}}}}}).get("ok",true)),"a negative x (最高 + n) is allowed down to −100")
	check(StatFilter.describe_condition("sum",{"enabled":true,"minus":-2},{"sum":627})=="三围合 ≥ 最高 627 + 2 = 629" and StatFilter.describe_condition("sum",{"enabled":true,"minus":1},{"sum":627})=="三围合 ≥ 最高 627 − 1 = 626","a negative x reads as 最高 + n")
	reply = set_settings(backend,{"training":{"hp":10}})
	check(reply.ok and not overrides(backend).training.has("hp"),"setting a value back to its default drops the override")

	# ---- validation ----
	var before := overrides(backend)
	for bad in [{"training":{"hp":0}},{"training":{"hp":"20"}},{"training":{"xp":3}},{"training":{"preset":"flee"}},{"training":{"speed":4}},
			{"hunt":{"offsets":[3,0,0,0]}},{"hunt":{"offsets":[0,0]}},{"hunt":{"level_one":1}},{"stat_filters":{"blue":{"mode":"any"}}},
			{"stat_filters":{"92":{"conditions":{"luck":{"enabled":true}}}}},{"stat_filters":{"92":{"mode":"most"}}},{"capture":{"pet_id":123}},
			{"device":{"battle_speed":2}},{"training":{"hp":20},"hunt":{"rate":-1}},"all",[]]:
		reply = set_settings(backend,bad)
		if reply.ok or str(reply.reason).is_empty():check(false,"rejects %s" % JSON.stringify(bad))
	check(overrides(backend)==before,"junk is rejected with a reason and nothing is half-applied")
	reply = backend.handle({"type":"set_automation_settings"})
	check(not reply.ok and reply.reason=="missing settings","a command without settings is refused")
	reply = set_settings(backend,{"training":{"hp":20.0,"compact":false}})
	check(reply.ok and overrides(backend).training.hp is int and int(overrides(backend).training.hp)==20,"whole-number floats from JSON are stored as integers")

	# ---- reset ----
	reply = set_settings(backend,{"training":{"compact":null}})
	check(reply.ok and not overrides(backend).training.has("compact") and overrides(backend).training.has("hp"),"null resets one value to its default")
	reply = set_settings(backend,{"hunt":null,"stat_filters":{"92":{"conditions":{"sum":null}}}})
	check(reply.ok and not overrides(backend).has("hunt") and not overrides(backend).has("stat_filters"),"null resets a whole section or nested group")

	# ---- persistence ----
	set_settings(backend,{"capture":{"hp":40,"pet_max_level":3},"stat_filters":{"194":{"stop_after":4}}})
	var saved: Dictionary = overrides(backend)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	check(parsed is Dictionary and parsed.has("automation_settings") and int(parsed.automation_settings.capture.hp)==40,"the backend saves the settings with the character")
	var reloaded = Backend.new()
	reloaded.set_process(false)
	root.add_child(reloaded)
	check(reloaded.load_profile(SAVE) and overrides(reloaded)==saved,"loading the save restores the same overrides")
	check(int(Settings.stat_filter(overrides(reloaded),194).stop_after)==4,"per-species settings survive a reload")
	reloaded.queue_free()

	# ---- migration: older saves have no settings, or broken ones ----
	var old: Dictionary = parsed.duplicate(true)
	old.erase("automation_settings")
	var file := FileAccess.open(SAVE,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE+".bak"))
	var session = GameSession.new()
	check(session.load_game(SAVE) and session.snapshot().automation_settings=={} and int(Settings.effective(session.automation_settings()).training.hp)==10,"a save without automation settings loads with the defaults")
	# Fixed thresholds from before 最高 − x are dropped; enabled and keep stay.
	var fixed := Settings.sanitize({"stat_filters":{"92":{"conditions":{"sum":{"value":630,"strict":true,"keep":4},"attack":{"value":300}}},"194":{"conditions":{"defence":{"enabled":true,"value":180}}}}})
	check(fixed=={"stat_filters":{"92":{"conditions":{"sum":{"keep":4}}},"194":{"conditions":{"defence":{"enabled":true}}}}},"old fixed values are dropped when a save is read (%s)" % JSON.stringify(fixed))
	check(int(Settings.stat_filter(fixed,194).conditions.defence.minus)==1,"and the condition becomes 最高 − 1")
	old.automation_settings = {"training":{"hp":55,"xp":7},"hunt":"junk","stat_filters":{"92":{"mode":"any","stop_after":3},"x":{}},"extra":1}
	file = FileAccess.open(SAVE,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	session = GameSession.new()
	check(session.load_game(SAVE) and session.automation_settings()=={"training":{"hp":55},"stat_filters":{"92":{"stop_after":3}}},"invalid stored settings are dropped and valid ones kept")

	# ---- runs use the profile ----
	var runner = Backend.new()
	runner.set_process(false)
	root.add_child(runner)
	for command in [{"type":"gm_raise_level","index":-1,"target":10},{"type":"gm_set_base_stat","index":-1,"stat":"strength","value":100},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":100},{"type":"gm_heal"}]:runner.handle(command)
	runner.automation.client_attached = false
	set_settings(runner,{"training":{"limit":3,"hp":1,"xp":2,"compact":false},"capture":{"hp":60,"pet_max_level":5}})
	reply = runner.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":CELL,"speed":2})
	var used: Dictionary = runner.automation.settings
	check(reply.ok and int(used.limit)==3 and int(used.hp)==1 and int(used.xp)==2 and not used.compact and int(used.capture_hp)==60 and int(used.capture_pet_max_level)==5,"auto_start uses the profile's training and capture settings")
	check(float(used.speed)==2.0 and int(used.level)==120 and runner.session.experience_multiplier==2,"the device's speed and an automatic level target complete the run's settings")
	set_settings(runner,{"capture":{"hp":70},"training":{"limit":9}})
	check(int(runner.automation.settings.capture_hp)==70 and int(runner.automation.settings.limit)==3,"a running battle follows capture changes; training changes wait for the next start")
	runner.handle({"type":"auto_stop"})
	set_settings(runner,{"training":{"level":50}})
	runner.handle({"type":"auto_start","kind":"battle","map_id":MAP,"cell":CELL})
	check(int(runner.automation.settings.level)==50 and int(runner.automation.settings.limit)==9 and float(runner.automation.settings.speed)==2.0,"an explicit level target is used and speed carries over")
	runner.handle({"type":"auto_stop"})
	set_settings(runner,{"hunt":{"rate":321,"limit":5,"total":4,"offsets":[-2,-2,-2,-2],"auto_capture":false,"level_one":false}})
	reply = runner.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":CELL})
	var filter: Dictionary = runner.automation.hunt_filter
	check(reply.ok and int(filter.rate)==321 and int(filter.limit)==5 and int(filter.total)==4 and not filter.auto_capture and not filter.level_one and not filter.usable.is_empty(),"a hunt starts from the profile's hunt settings with the backend's own usable species")
	runner.handle({"type":"auto_stop"})
	set_settings(runner,{"hunt":{"template":999999}})
	reply = runner.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":CELL})
	check(not reply.ok and not runner.automation.hunt_running,"a saved species that does not live here is refused, not replaced")
	set_settings(runner,{"hunt":{"template":null},"stat_filters":{"92":{"conditions":{"sum":{"minus":7}}}}})
	reply = runner.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL})
	check(reply.ok and int(runner.automation.raw_filter_for(92).conditions.sum.minus)==7 and int(runner.automation.flow_hunt_request.rate)==321,"find-pet uses the profile's hunt and stat settings")
	set_settings(runner,{"stat_filters":{"92":{"conditions":{"sum":{"minus":8}}}}})
	check(int(runner.automation.raw_filter_for(92).conditions.sum.minus)==7,"a running cycle keeps the conditions it started with")
	runner.handle({"type":"auto_stop"})

	backend.queue_free();runner.queue_free()
	clear_save()
	await process_frame
	print("AUTOMATION SETTINGS: %d failures" % failures)
	quit(1 if failures else 0)
