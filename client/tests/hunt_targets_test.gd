extends SceneTree
const Backend = preload("res://server/backend.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const Rules = preload("res://scripts/pet_hunt_rules.gd")
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func run() -> void:
	check(Settings.hunt_filter({"hunt":{"template":113}}).templates==[113],"legacy single target resolves to singleton")
	check(not Settings.hunt_filter({"hunt":{"template":-1}}).has("templates"),"legacy wildcard keeps all-location semantics")
	var normalized := Settings.apply_patch({}, {"hunt":{"templates":[114.0,113,114]}})
	check(normalized.ok and normalized.overrides.hunt.templates==[113,114],"JSON integers normalize and deduplicate")
	for bad in [[113.5],["113"],[-1],[true],null,{}]:
		if bad==null:continue # null intentionally resets override
		check(not Settings.apply_patch({}, {"hunt":{"templates":bad}}).ok,"invalid target set rejected: %s" % str(bad))
	check(Settings.hunt_filter(Settings.sanitize({"hunt":{"templates":[]}})).templates.is_empty(),"empty target set survives save normalization")
	check(Rules.targets({"usable":[113,114],"templates":[113,92]})==[113],"location change intersects choices, never broadens them")
	for chosen in [[],[113],[113,114]]:
		var backend=Backend.new();root.add_child(backend);backend.set_process(false)
		backend.handle({"type":"gm_raise_level","index":-1,"target":120})
		backend.handle({"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":500})
		backend.handle({"type":"gm_heal"})
		var reply: Dictionary=backend.handle({"type":"auto_start","kind":"hunt","map_id":100,"cell":[637,493],"filter":{"templates":chosen,"level_one":true,"total":-8,"offsets":[],"auto_capture":false,"fast":false,"clean_only":false}})
		if chosen.is_empty():check(not reply.ok and not backend.battle_open,"explicit none refuses without battle")
		else:
			check(reply.ok,"selected target set starts real backend hunt")
			for i in range(10000):
				if not backend.automation.hunt_running:break
				backend.automation.scan_once()
			check(backend.battle_open and not backend.automation.hunt_last_hit.is_empty() and int(backend.automation.hunt_last_hit.actor.template_id) in chosen,"real rolled individual enters capture battle only from selected species")
			if backend.battle_open and not backend.automation.hunt_last_hit.is_empty():
				var slot: int=backend.automation.hunt_last_hit.index
				for attempt in range(100):
					backend.battle.submit_action("capture",slot)
					if not backend.battle.snapshot().active:break
				var result: Dictionary=backend.battle.snapshot()
				check(result.outcome=="captured" and backend.session.apply_battle_result(result) and backend.session.snapshot().pets.any(func(p):return int(p.template_id) in chosen),"selected real individual is genuinely captured and settled into character pets")
		backend.handle({"type":"auto_stop"});backend.queue_free();await process_frame
	var other=Backend.new();root.add_child(other);other.set_process(false)
	check(not other.handle({"type":"auto_start","kind":"hunt","map_id":300,"cell":[509,93],"filter":{"templates":[113,114]}}).ok,"real map change does not substitute the local dragon for saved choices")
	for malformed in [null,[113.5],["113"],{}]:
		check(not other.handle({"type":"auto_start","kind":"hunt","map_id":100,"cell":[637,493],"filter":{"templates":malformed}}).ok,"backend refuses malformed run-only target set")
	other.queue_free();await process_frame
	var save_path := "user://hunt-targets-migration.json"
	var original=preload("res://server/game_session.gd").new()
	for old_hunt in [{"template":113},{"template":-1},{"templates":[]},{"templates":[113,114]}]:
		var profile: Dictionary=original.snapshot().duplicate(true)
		profile.automation_settings={"hunt":old_hunt}
		var file:=FileAccess.open(save_path,FileAccess.WRITE);file.store_string(JSON.stringify(profile));file.close()
		var loaded=preload("res://server/game_session.gd").new()
		check(loaded.load_game(save_path),"v6 real character save loads target migration")
		var resolved: Dictionary=Settings.hunt_filter(loaded.automation_settings())
		check((not resolved.has("templates") if old_hunt.get("template",-2)==-1 else resolved.get("templates")==old_hunt.get("templates",[113])),"real save preserves legacy all, single, none, multi semantics")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path+".bak"))
	var queued=Backend.new();root.add_child(queued);queued.set_process(false)
	var started: Dictionary=queued.handle({"type":"auto_start","kind":"hunt","map_id":100,"cell":[637,493],"filter":{"templates":[113,114],"level_one":true,"total":-8,"offsets":[],"auto_capture":false,"fast":false,"clean_only":false}})
	check(started.ok,"queue/resume fixture uses real hunt core")
	var saved: Dictionary={"filter":queued.automation.hunt_filter.duplicate(true),"run_seed":queued.automation.hunt_run_seed,"rolls":0,"inspected":0,"best":-9}
	for id in [113,114]:
		var raw: Dictionary=Settings.stat_filter({},id)
		for condition in raw.conditions.values():condition.enabled=false
		queued.automation.flow_stat_filters[id]=raw
	var entry: Dictionary={}
	var seen := []
	for index in range(1000):
		var troop: Dictionary=queued.automation.roll_at(index)
		var slot: int=-1 if troop.is_empty() else queued.automation.first_match(troop)
		if slot<0:continue
		queued.automation._showcase_enqueue(index,slot,troop,Rules.quality(troop.enemies[slot],queued.encounter_catalog.data))
		if not queued.automation.showcase_queue.is_empty():entry=queued.automation.showcase_queue[0]
		if not int(troop.enemies[slot].template_id) in seen:seen.append(int(troop.enemies[slot].template_id))
		if seen.size()==2:break
	check(not entry.is_empty() and queued.automation._queue_templates()==[113,114],"real selected hits enter both per-species queues")
	var first: Dictionary=queued.automation._take_queued()
	queued.automation._showcase_add(first)
	var second: Dictionary=queued.automation._take_queued()
	check(int(first.actor.template_id)!=int(second.actor.template_id),"round robin serves distinct selected species")
	queued.automation._showcase_add(second)
	check(queued.automation._survey_wanted().is_empty(),"disabled species attributes do not invent survey targets")
	queued.handle({"type":"set_automation_settings","settings":{"hunt":{"templates":[]}}})
	check(queued.automation.showcase_queue.is_empty() and queued.automation._hunt_templates().is_empty(),"deselect clears pending queue and scan targets")
	check(queued.release_log.entries().any(func(e):return e.get("source","")=="目标取消"),"cancelled queued hit records uncaught reason")
	queued.automation.stop_hunt("test restore")
	check(queued.automation._restore_hunt(saved) and queued.automation._hunt_templates()==[113,114],"resume restores same selected set and seed")
	queued.automation.stop_hunt("test none")
	saved.filter.templates=[]
	check(not queued.automation._restore_hunt(saved),"resume of explicit none cannot open capture")
	queued.queue_free();await process_frame
	print("HUNT TARGETS: %d failures" % failures);quit(1 if failures else 0)
