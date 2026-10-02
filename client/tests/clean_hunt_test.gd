extends SceneTree
## 只进无其他敌人的遇敌 (hunt.clean_only) and its exception 属性达标仍进混合遇敌
## (hunt.mixed_if_stats): the settings and their defaults, the troop rule, the
## GDScript hunt passing over a Lv.1 pet whose troop holds stronger enemies,
## the battle forecast on the real battle core, and a find-pet cycle that
## pauses instead of entering a mixed troop it cannot win (and enters it when
## it can). The helper's parity for the same rule is in fast_hunt_test.
const Backend = preload("res://server/backend.gd")
const AutomationSettings = preload("res://scripts/automation_settings.gd")
const HuntRules = preload("res://scripts/pet_hunt_rules.gd")
const BattleForecast = preload("res://server/battle_forecast.gd")
const Wait = preload("res://tests/support/wait.gd")
const FastHunt = preload("res://server/fast_hunt.gd")
## 五十年前波拉岛, area 639: the added Lv.1 左迪洛斯 (302) next to Lv90-95 红暴.
const MAP := 500
const CELL := [400,400]
const BLUE_REX := 302
var failures := 0

func _initialize() -> void:call_deferred("run")

func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures += 1

func new_backend(encounter_seed: int):
	var backend = Backend.new()
	backend.set_process(false)
	root.add_child(backend)
	backend.automation.client_attached = false
	backend.encounter_rng.seed = encounter_seed
	return backend

## This suite compares the first accepted roll across weak/strong characters.
## One real scan then one real flow step prevents the wall-clock frame budget
## from queueing later hits before that first capture is selected.
func tick_until(backend, condition: Callable) -> bool:
	return await Wait.until(self,func():
		if condition.call():return true
		if backend.automation.hunt_running:backend.automation.scan_once()
		if backend.automation.flow_active():backend.automation.flow_step()
		return condition.call())

## Any 左迪洛斯 Lv.1, no grade limit, GDScript scan.
func rex_filter(extra: Dictionary = {}) -> Dictionary:
	var filter := {"template":BLUE_REX,"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"auto_capture":false,"limit":0,"rate":0,"fast":false,"showcase":false}
	filter.merge(extra,true)
	return filter

## A troop of the area with the Lv.1 左迪洛斯 and a stronger enemy.
func mixed_troop(backend) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	for i in range(5000):
		rng.seed = 777+i
		var troop: Dictionary = backend.encounter_catalog.roll(MAP,Vector2i(CELL[0],CELL[1]),rng,[])
		if HuntRules.clean_troop(troop):continue
		for enemy in troop.get("enemies",[]):
			if int(enemy.template_id)==BLUE_REX and int(enemy.level)==1:return troop
	return {}

func slot_of(troop: Dictionary) -> int:
	for i in range(troop.enemies.size()):
		if int(troop.enemies[i].template_id)==BLUE_REX and int(troop.enemies[i].level)==1:return i
	return -1

## A find-pet cycle for 左迪洛斯 with a fixed (absolute) 属性条件 every pet meets.
func start_cycle(backend, mixed_if_stats: bool) -> Dictionary:
	var lax := {"mode":"any","stop_after":1,"conditions":{"sum":{"enabled":true,"value":0,"strict":false,"keep":0}}}
	return backend.handle({"type":"auto_start","kind":"find_pet","map_id":MAP,"cell":CELL,"stat_filters":{str(BLUE_REX):lax},
		"filter":rex_filter({"mixed_if_stats":mixed_if_stats}),"settings":{"capture_hp":100}})

func run() -> void:
	FastHunt.threads = 2
	# Settings: on by default, the exception off; an old save has neither key.
	var defaults := AutomationSettings.hunt_filter({})
	check(bool(defaults.clean_only) and not bool(defaults.mixed_if_stats),"只进无其他敌人的遇敌 is on and 属性达标仍进混合遇敌 off by default")
	var old_save := AutomationSettings.sanitize({"hunt":{"fast":false,"queue":5}})
	check(bool(AutomationSettings.hunt_filter(old_save).clean_only) and int(AutomationSettings.hunt_filter(old_save).queue)==5,"a save from before the setting gets the default and keeps its own values")
	var patched := AutomationSettings.apply_patch({},{"hunt":{"clean_only":false,"mixed_if_stats":true}})
	check(patched.ok and not bool(AutomationSettings.hunt_filter(patched.overrides).clean_only) and bool(AutomationSettings.hunt_filter(patched.overrides).mixed_if_stats),"both are saved with the character")
	check(not AutomationSettings.apply_patch({},{"hunt":{"clean_only":1}}).ok,"a non-boolean value is refused")
	check(AutomationSettings.apply_patch({},{"hunt":{"clean_only":true,"mixed_if_stats":false}}).overrides.is_empty(),"values equal to the default are not stored")

	# The rule: only Lv.1 enemies, whatever their species.
	check(HuntRules.clean_troop({"enemies":[{"level":1,"template_id":302},{"level":1,"template_id":303}]}),"Lv.1 pets of another species do not make a troop mixed")
	check(not HuntRules.clean_troop({"enemies":[{"level":1,"template_id":302},{"level":92,"template_id":303}]}),"a Lv.92 enemy does")
	check(not HuntRules.wants_clean({"clean_only":true,"level_one":false}),"a hunt not limited to Lv.1 never skips troops")

	# The GDScript hunt: every pet it takes comes from a clean troop, the mixed
	# ones are counted and reported.
	# Seeds until a run's first hit came after passing over a mixed troop.
	var all_clean := true
	var passed := -1
	for candidate in range(20):
		var hunt = new_backend(4242+candidate)
		if not hunt.handle({"type":"auto_start","kind":"hunt","map_id":MAP,"cell":CELL,"filter":rex_filter()}).ok:check(false,"a 左迪洛斯 hunt starts")
		await tick_until(hunt,func():return not hunt.automation.hunt_running)
		var hit: Dictionary = hunt.automation.hunt_last_hit
		all_clean = all_clean and not hit.is_empty() and HuntRules.clean_troop(hit.troop) and hunt.battle_open
		if hunt.automation.hunt_mixed_skips>0 and int(hunt.automation.status().hunt.mixed)==hunt.automation.hunt_mixed_skips:passed = hunt.automation.hunt_mixed_skips
		hunt.queue_free()
		if passed>0:break
	check(all_clean,"every hunt enters a troop with only Lv.1 enemies")
	check(passed>0,"one passed over %d pets in mixed troops first, shown in the status" % passed)

	# The forecast, on the real battle core.
	var weak = new_backend(1)
	var troop := mixed_troop(weak)
	check(not troop.is_empty(),"a mixed troop with a Lv.1 左迪洛斯: %s" % BattleForecast.stronger_enemies(troop))
	var config: Dictionary = weak.session.start_wild_battle_config(troop)
	weak.session.cancel_pending_battle(str(config.battle_id))
	var settings: Dictionary = weak.automation.profile_settings()
	var lost := BattleForecast.forecast(config,settings,slot_of(troop),43)
	check(not bool(lost.ok) and int(lost.wins)<int(lost.trials)-BattleForecast.ALLOWED_LOSSES and not str(lost.reason).is_empty(),"a new Lv.1 character cannot win it: %d of %d (%s)" % [int(lost.wins),int(lost.trials),lost.reason])
	var strong := config.duplicate(true)
	for key in ["player_attack","player_defence","player_speed"]:strong[key] = 50000
	strong.player_hp = 99999;strong.player_max_hp = 99999
	var won := BattleForecast.forecast(strong,settings,slot_of(troop),43)
	check(bool(won.ok) and int(won.wins)>=int(won.trials)-BattleForecast.ALLOWED_LOSSES,"a far stronger character can: %d of %d" % [int(won.wins),int(won.trials)])
	check(BattleForecast.simulate(config,settings,slot_of(troop),43)==BattleForecast.simulate(config,settings,slot_of(troop),43),"a forecast battle is deterministic for its seed")
	weak.queue_free()

	# A find-pet cycle with the exception: the first hit is in a mixed troop
	# (the encounter seed is picked so), and a new character pauses.
	var cycle_seed := -1
	var paused = null
	for candidate in range(20):
		var backend = new_backend(9000+candidate)
		if not start_cycle(backend,true).ok:
			check(false,"seed %d: a find-pet cycle starts (%s)" % [9000+candidate,backend.automation.flow_reason])
		await tick_until(backend,func():return backend.automation.flow_phase!="hunt")
		var last: Dictionary = backend.automation.hunt_last_hit
		if not last.is_empty() and not HuntRules.clean_troop(last.troop):
			cycle_seed = 9000+candidate;paused = backend;break
		backend.handle({"type":"auto_stop"})
		backend.queue_free()
	check(paused!=null,"an encounter seed whose first hit is in a mixed troop (%d)" % cycle_seed)
	if paused!=null:
		var reason: String = paused.automation.flow_reason
		check(paused.automation.flow_phase=="paused" and not paused.battle_open,"the cycle pauses without entering the battle")
		check(reason.contains("同组还有") and reason.contains("已暂停") and reason.contains("属性达标仍进混合遇敌"),"and says why: %s" % reason)
		check(paused.session.gm_raise_level(-1,2),"no battle is left pending (the character can change again)")
		paused.queue_free()

		# Without the exception the same run passes the pet over and goes on.
		var plain = new_backend(cycle_seed)
		start_cycle(plain,false)
		await tick_until(plain,func():return plain.automation.flow_phase!="hunt")
		var taken: Dictionary = plain.automation.hunt_last_hit
		check(not taken.is_empty() and HuntRules.clean_troop(taken.troop) and plain.automation.hunt_mixed_skips>0,"without 属性达标仍进混合遇敌 the cycle skips it and takes a clean troop later (phase %s)" % plain.automation.flow_phase)
		plain.handle({"type":"auto_stop"})
		plain.queue_free()

		# A strong character enters the same mixed troop.
		var mighty = new_backend(cycle_seed)
		mighty.session.gm_raise_level(-1,120)
		for stat in ["vitality","strength","toughness","dexterity"]:mighty.session.gm_set_base_stat(-1,stat,10000)
		mighty.handle({"type":"gm_heal","index":-1})
		start_cycle(mighty,true)
		await tick_until(mighty,func():return mighty.automation.flow_phase!="hunt")
		var entered: Dictionary = mighty.automation.hunt_last_hit
		check(not entered.is_empty() and not HuntRules.clean_troop(entered.troop) and mighty.automation.flow_phase in ["capture","train","restart"] ,"a character the forecast says wins enters the mixed troop (phase %s: %s)" % [mighty.automation.flow_phase,mighty.automation.flow_reason])
		var actual: Dictionary = mighty.battle.snapshot()
		check(mighty.battle_open and actual.get("active",false) and not HuntRules.clean_troop(actual) and int(actual.get("clear_capture_target",-1))==slot_of(entered.troop),"the real active battle contains the stronger enemies and pins the matched Lv.1 target")
		check(mighty.session._pending.get("group_id",-1)==entered.troop.group_id and mighty.session._pending.enemies.map(func(e):return [e.template_id,e.level,e.growth_seed])==entered.troop.enemies.map(func(e):return [e.template_id,e.level,e.growth_seed]),"the authority's actual battle is the same forecast-approved original troop")
		mighty.handle({"type":"auto_stop"})
		mighty.queue_free()
	await process_frame
	print("CLEAN HUNT: %d failures" % failures)
	quit(1 if failures else 0)
