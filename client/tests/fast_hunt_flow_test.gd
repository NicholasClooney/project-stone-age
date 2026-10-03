extends SceneTree
## 本机极速模式 end to end on a backend: the helper finds the same roll the
## GDScript scan finds, a find-pet cycle's Lv120 prediction hands off to
## capture, a missing helper falls back to GDScript, and a helper report the
## backend's replay does not confirm stops the hunt without a battle.
const Backend = preload("res://server/backend.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
const Progression = preload("res://server/progression.gd")
const MAP := 300
const CELL := [509,93]
const SEED := 424242
var failures := 0

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
	backend.encounter_rng.seed = SEED
	return backend

## Ticks the backend until the hunt stops; notes whether the helper ran.
func hunt_until_stopped(backend, seconds: float = 60.0) -> Dictionary:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	var saw_fast := false
	while backend.automation.hunt_running and not (backend.automation.flow_active() and backend.automation.flow_phase!="hunt") and Time.get_ticks_msec() < deadline:
		backend._process(0.016)
		saw_fast = saw_fast or backend.automation.fast_hunt.running()
		await process_frame
	return {"fast":saw_fast,"stopped":not backend.automation.hunt_running}

func dragon_hunt(backend, fast: bool) -> Dictionary:
	return backend.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":CELL,"filter":{"template":92,"level_one":true,"total":8,"offsets":[2,2,2,2],"auto_capture":false,"limit":0,"fast":fast}})

func run() -> void:
	# Other suites run beside this one; two threads still scan far faster than GDScript.
	FastHunt.threads = 2
	check(FastHunt.available(),"the helper is built (%s)" % FastHunt.unavailable_reason())

	# The helper gets only this server profile's inventory and restarts when it changes.
	var inventory_hunt = new_backend()
	inventory_hunt.session._profile.original_items = [2478]
	check(dragon_hunt(inventory_hunt,true).ok,"an item-owning profile starts a fast hunt")
	inventory_hunt.automation._fast_process()
	var inventory_pid: int = inventory_hunt.automation.fast_hunt.pid
	check(inventory_pid>0 and inventory_hunt.automation._fast_held_items==[2478],"helper launch reads the owning server profile's original items")
	inventory_hunt.session._profile.original_items = []
	inventory_hunt.automation._fast_process()
	check(inventory_hunt.automation.fast_hunt.pid>0 and inventory_hunt.automation.fast_hunt.pid!=inventory_pid and inventory_hunt.automation._fast_held_items.is_empty(),"inventory changes restart the helper with current item gates")
	inventory_hunt.handle({"type":"auto_stop"})
	inventory_hunt.queue_free()

	var multi_hits: Array=[]
	for native in [false,true]:
		var multi=new_backend()
		multi.handle({"type":"report_position","map_id":100,"cell":[637,493]})
		multi.session._profile.original_items=[2478]
		check(multi.handle({"type":"auto_start","kind":"hunt","map_id":100,"cell":[637,493],"filter":{"templates":[113,114],"level_one":true,"total":-8,"offsets":[],"auto_capture":false,"fast":native,"clean_only":false}}).ok,"multi-species end-to-end hunt starts with inventory gates")
		var multi_run: Dictionary=await hunt_until_stopped(multi)
		var hit: Dictionary=multi.automation.hunt_last_hit
		check(multi_run.stopped and multi.battle_open and not hit.is_empty() and int(hit.actor.template_id) in [113,114],"multi-species real hit enters ordinary battle")
		multi_hits.append([multi.automation.hunt_rolls,hit.get("index",-1),hit.get("actor",{}).get("growth_seed",0)])
		multi.queue_free();await process_frame
	check(multi_hits[0]==multi_hits[1],"multi-species helper/slow capture handoff preserves RNG with inventory")
	# The GDScript scan and the helper find the same roll.
	var slow = new_backend()
	var started: Dictionary = dragon_hunt(slow,false)
	check(started.ok,"a GDScript hunt starts %s" % started)
	var slow_run := await hunt_until_stopped(slow,120.0)
	var slow_hit: Dictionary = slow.automation.hunt_last_hit
	check(not slow_run.fast and not slow_hit.is_empty() and slow.battle_open,"the GDScript scan finds a 满档 blue dragon after %d rolls" % slow.automation.hunt_rolls)
	var fast = new_backend()
	check(dragon_hunt(fast,true).ok,"a fast hunt starts")
	var fast_run := await hunt_until_stopped(fast)
	var fast_hit: Dictionary = fast.automation.hunt_last_hit
	check(fast_run.fast and fast.automation.hunt_fast_note.is_empty(),"本机极速模式 scanned with the helper")
	check(not fast_hit.is_empty() and fast.automation.hunt_rolls==slow.automation.hunt_rolls and int(fast_hit.index)==int(slow_hit.index) and int(fast_hit.actor.growth_seed)==int(slow_hit.actor.growth_seed),
		"the helper finds the same roll, slot and pet (roll %d)" % fast.automation.hunt_rolls)
	check(fast.automation.hunt_inspected==slow.automation.hunt_inspected and fast.automation.hunt_best==slow.automation.hunt_best,"and counts the same inspected pets (%d) and best grade" % fast.automation.hunt_inspected)
	check(fast.battle_open and fast.automation.hunt_status.begins_with("找到达标个体"),"the hit enters the ordinary battle")
	var expected_rolls: int = slow.automation.hunt_rolls
	slow.queue_free();fast.queue_free()

	# A find-pet cycle: the helper applies the Lv120 prediction too.
	var flow = new_backend()
	flow.handle({"type":"grant_starter_pets"})
	for command in [{"type":"gm_raise_level","index":-1,"target":20},{"type":"gm_set_base_stat","index":-1,"stat":"toughness","value":200},{"type":"gm_heal"}]:
		flow.handle(command)
	var strict := {"mode":"any","stop_after":1,"conditions":{"sum":{"enabled":true,"value":621,"strict":false,"keep":0}}}
	var reply: Dictionary = flow.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL,"stat_filters":{"92":strict},
		"filter":{"template":92,"level_one":true,"total":8,"offsets":[2,2,2,2],"auto_capture":false,"limit":0,"fast":true,"showcase":false},"settings":{"capture_hp":100}})
	check(reply.ok and flow.automation.flow_phase=="hunt","a find-pet cycle starts hunting")
	var flow_run := await hunt_until_stopped(flow)
	var matched: Dictionary = flow.automation.flow_matched_actor
	var projected := Progression.project_pet(matched,120) if not matched.is_empty() else {}
	check(flow_run.fast and flow.automation.flow_phase in ["capture","train","compare"] and not matched.is_empty(),"the helper's hit hands the cycle on (phase %s: %s)" % [flow.automation.flow_phase,flow.automation.flow_reason])
	check(not projected.is_empty() and int(projected.attack)+int(projected.defence)+int(projected.speed)>=621,"the matched pet reaches Lv120 sum %d (at least 621)" % (int(projected.get("attack",0))+int(projected.get("defence",0))+int(projected.get("speed",0))))
	check(int(flow.automation.flow_predicted_rejects)>0 and int(flow.automation.flow_best_predicted.get("sum",0))>=621,"rejected predictions (%d) and the best prediction are reported" % flow.automation.flow_predicted_rejects)
	flow.handle({"type":"auto_stop"})
	flow.queue_free()

	# No helper: the same hunt runs in GDScript and says why.
	FastHunt.helper_override = ProjectSettings.globalize_path("user://no-such-fast-hunt")
	var fallback = new_backend()
	dragon_hunt(fallback,true)
	check(not fallback.automation.hunt_fast_note.is_empty() and fallback.automation.status().hunt.fast_note==fallback.automation.hunt_fast_note,"a missing helper is reported: %s" % fallback.automation.hunt_fast_note)
	var fallback_run := await hunt_until_stopped(fallback,120.0)
	check(not fallback_run.fast and not fallback.automation.hunt_last_hit.is_empty() and fallback.automation.hunt_rolls==expected_rolls,"and the GDScript scan still finds the same pet")
	fallback.queue_free()

	# A helper whose report the replay does not confirm cannot start a battle.
	var liar := ProjectSettings.globalize_path("user://fast-hunt-liar.sh")
	var file := FileAccess.open(liar,FileAccess.WRITE)
	file.store_string("#!/bin/sh\necho 'hit 3 0 0 -9 0 -1 -1' > \"$2\"\n")
	file.close()
	OS.execute("chmod",["+x",liar])
	FastHunt.helper_override = liar
	var lied = new_backend()
	dragon_hunt(lied,true)
	await hunt_until_stopped(lied)
	check(not lied.automation.hunt_running and lied.automation.hunt_status.contains("与游戏复核不一致") and not lied.battle_open,"an unconfirmed helper hit stops the hunt without a battle")
	DirAccess.remove_absolute(liar)
	FastHunt.helper_override = ""
	lied.queue_free()
	await process_frame
	print("FAST HUNT FLOW: %d failures" % failures)
	quit(1 if failures else 0)
