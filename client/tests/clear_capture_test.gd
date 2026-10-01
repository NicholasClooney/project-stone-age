extends SceneTree
## Real encounter catalog, character configuration, squad core, capture rules,
## settlement and runner. No replacement battle engine or capture result.
const Backend = preload("res://server/backend.gd")
const Battle = preload("res://server/squad_battle_session.gd")
const Policy = preload("res://scripts/battle_auto_policy.gd")
const Forecast = preload("res://server/battle_forecast.gd")
const Settings = preload("res://scripts/automation_settings.gd")
const HuntRules = preload("res://scripts/pet_hunt_rules.gd")
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func troop_for(backend) -> Dictionary:
 var rng := RandomNumberGenerator.new()
 for seed in range(777,5777):
  rng.seed=seed
  var troop: Dictionary=backend.encounter_catalog.roll(500,Vector2i(400,400),rng,[])
  if HuntRules.clean_troop(troop):continue
  for i in range(troop.enemies.size()):
   if int(troop.enemies[i].level)==1 and int(troop.enemies[i].template_id)==302:return {"troop":troop,"slot":i}
 return {}
func backend_for():
 var backend=Backend.new();backend.set_process(false);root.add_child(backend)
 backend.automation.client_attached=false;backend.automation.auto_tick=false
 backend.session.gm_raise_level(-1,120)
 for stat in ["vitality","strength","toughness","dexterity"]:backend.session.gm_set_base_stat(-1,stat,10000)
 backend.session.gm_heal(-1)
 backend.session.gm_grant_pet(302)
 backend.session.gm_set_base_stat(0,"vitality",50)
 backend.session.gm_set_base_stat(0,"toughness",100)
 backend.session.gm_heal(0)
 return backend
func run_core(config: Dictionary, settings: Dictionary, slot: int, seed: int) -> Dictionary:
 var battle=Battle.new();battle.rng_seed=seed;battle.start_battle(config);battle.automated=true
 var decisions: Array=[]
 for turn in range(200):
  var state: Dictionary=battle.snapshot()
  if not state.active:break
  var decision: Dictionary=Policy.decide(state,settings,slot)
  decisions.append(decision)
  if decision.has("stop"):break
  battle.set_capture_assist(bool(decision.get("assist",true)))
  battle.set_pet_command(str(decision.pet));battle.set_pet_target(int(decision.target))
  battle.submit_action(str(decision.action),int(decision.target),int(decision.get("switch",-2)))
 return {"state":battle.snapshot(),"decisions":decisions}
func run():
 var backend=backend_for()
 var found:=troop_for(backend)
 check(not found.is_empty(),"real catalog yields a mixed troop")
 if found.is_empty():quit(1);return
 var slot:=int(found.slot)
 var config: Dictionary=backend.session.start_wild_battle_config(found.troop,slot)
 check(config.allies.size()==4 and config.ally_pets==[{},{},{},{}] and int(config.active_pet)==-1 and config.pet.is_empty(),"five people clear with no deployed or cloned pet")
 check(not backend.session.clone_squad_enabled,"temporary squad config preserves the character's clone preference")
 var settings: Dictionary=backend.automation.profile_settings();settings.preset="capture"
 settings.capture_fallback_rate=0;settings.capture_fallback_attempts=30
 var trial:=run_core(config,settings,slot,43)
 check(bool(trial.state.enemies[slot].captured),"clear then actual capture succeeds")
 var clearing:=true;var saw_clear:=false;var saw_capture:=false
 for decision in trial.decisions:
  if decision.action=="attack":saw_clear=true;clearing=clearing and int(found.troop.enemies[int(decision.target)].level)!=1 and decision.pet=="defend"
  if decision.action=="capture":saw_capture=true
 check(clearing and saw_clear and saw_capture and trial.decisions[0].action=="attack","only stronger enemies are targeted before capture")
 check(backend.session.apply_battle_result(trial.state),"real settlement accepts the real capture outcome")
 check(backend.session.snapshot().pets.size()==2 and backend.session.snapshot().pets[1].growth_seed==found.troop.enemies[slot].growth_seed,"settlement grants the exact target identity")
 # Every seed's forecast executes the same policy and real core as the trace.
 var wins:=0
 for seed in range(43,48):
  var actual:=run_core(config,settings,slot,seed)
  var expected: bool=bool(actual.state.enemies[slot].captured) and str(actual.state.outcome) in ["captured","win","escaped"]
  var predicted:=Forecast.simulate(config,settings,slot,seed)
  check(bool(predicted.won)==expected,"forecast/live strategy parity seed %d"%seed)
  if expected:wins+=1
 check(int(Forecast.forecast(config,settings,slot,43).wins)==wins,"all five trial seeds are counted")
 # Force the documented failure-count trigger without inventing capture math.
 var hard:=config.duplicate(true);hard.player_speed=1;hard.player_level=120;hard.player_charm=60
 settings.capture_fallback_rate=98;settings.capture_fallback_attempts=1
 var shaved:=run_core(hard,settings,slot,43)
 check(shaved.decisions.any(func(d):return d.get("action","")=="switch") and shaved.decisions.any(func(d):return d.get("pet","")=="attack"),"hard capture switches a real carried pet, then shaves")
 check(bool(shaved.state.enemies[slot].captured),"hard capture reaches genuine capture success after shaving")
 # The failure-count trigger waits for a real failed capture, independently
 # of the probability trigger.
 var retry_settings:=settings.duplicate(true);retry_settings.capture_fallback_rate=0;retry_settings.capture_fallback_attempts=1
 var failure_trigger:=false
 for seed in range(43,48):
  var retry:=run_core(hard,retry_settings,slot,seed)
  var attempts_before_switch:=0
  for decision in retry.decisions:
   if decision.get("action","")=="capture":attempts_before_switch+=1
   if decision.get("action","")=="switch":failure_trigger=attempts_before_switch>=1;break
  if failure_trigger:break
 check(failure_trigger,"a genuine failed capture triggers the configured retry fallback")
 # Core blocks retargeting and counters on another protected Lv.1.
 var protect:=config.duplicate(true)
 protect.enemies.append(found.troop.enemies[slot].duplicate(true))
 var guarded=Battle.new();guarded.start_battle(protect);guarded.set_capture_assist(false);guarded.set_pet_command("defend")
 for turn in range(10):
  if not guarded.snapshot().active:break
  guarded.submit_action("attack",slot)
 var state: Dictionary=guarded.snapshot()
 check(int(state.enemies[slot].hp)==int(protect.enemies[slot].hp) and int(state.enemies.back().hp)==int(protect.enemies.back().hp),"retargeting and retaliation preserve every Lv.1")
 var invalid:=state.duplicate(true);invalid.enemies[slot].battle_uid="wrong"
 check(Policy.decide(invalid,settings,slot).has("stop"),"a changed target UID never redirects capture")
 var dead:=state.duplicate(true);dead.enemies[slot].hp=0
 check(Policy.decide(dead,settings,slot).has("stop"),"dead target is failure, never another capture")
 var weak:=config.duplicate(true)
 for key in ["player_attack","player_defence","player_speed"]:weak[key]=1
 weak.player_hp=48;weak.player_max_hp=48;weak.allies=[];weak.ally_pets=[]
 check(not bool(Forecast.forecast(weak,settings,slot,43).ok),"five real-core trials reject an unwinnable troop")
 for patch in [{"fallback_attempts":0},{"fallback_attempts":31},{"fallback_rate":99},{"fallback_hp":100},{"fallback_hp":"50"}]:
  check(not bool(Settings.apply_patch({},{"capture":patch}).ok),"invalid fallback settings rejected: %s"%str(patch))
 var old:=Settings.runner_settings(Settings.sanitize({"capture":{"hp":37}}),120)
 check(int(old.capture_hp)==37 and int(old.capture_fallback_attempts)==5 and int(old.capture_fallback_rate)==20 and int(old.capture_fallback_hp)==50,"old saves keep existing settings and acquire bounded defaults")
 # Settings can change during clearing without changing the enemy reference.
 var live=backend_for();live.session.gm_set_base_stat(-1,"dexterity",0);live.session.gm_grant_pet(302)
 var live_config: Dictionary=live.session.start_wild_battle_config(found.troop,slot)
 live.open_battle(live_config);live.automation.start_capture_battle(slot,true)
 live.automation.step()
 var uid: String=str(live.battle.snapshot().clear_capture_uid)
 var selected: String=str(live.session.snapshot().pets[1].pet_id)
 check(live.handle({"type":"set_automation_settings","settings":{"capture":{"pet_id":selected}}}).ok,"capture helper settings change while the squad clears")
 check(str(live.automation.settings.capture_pet_id)==selected and str(live.battle.snapshot().clear_capture_uid)==uid,"new helper choice preserves the locked target UID")
 check(not live.session.store_pet(1) and live.session.last_error.contains("战斗"),"newly selected real carried helper receives the battle pet lock")
 live.abandon_battle();live.automation.stop("test");live.queue_free()
 # A real lethal helper exercises the runner's failure bookkeeping. The
 # forecast normally refuses this config; open it directly to audit a failure.
 var lethal=backend_for()
 lethal.session.gm_set_base_stat(0,"vitality",10000);lethal.session.gm_heal(0)
 lethal.session.gm_set_base_stat(-1,"dexterity",0)
 lethal.handle({"type":"set_automation_settings","settings":{"capture":{"fallback_rate":98}}})
 var started: Dictionary=lethal.handle({"type":"auto_start","kind":"find_pet","map_id":500,"cell":[400,400],
  "filter":{"template":302,"usable":[302],"level_one":true,"total":-8,"offsets":[-2,-2,-2,-2],"rate":0,"limit":0,"fast":false,"showcase":false,"mixed_if_stats":true},
  "stat_filters":{"302":{"mode":"any","threshold_mode":"absolute","conditions":{"sum":{"enabled":true,"value":0}}}}})
 check(bool(started.ok),"a real isolated search cycle starts")
 var fatal: Dictionary=lethal.session.start_wild_battle_config(found.troop,slot)
 check(not bool(Forecast.forecast(fatal,lethal.automation.profile_settings(),slot,43).ok),"forecast rejects a helper which kills the target even if the squad wins")
 lethal.automation.stop_hunt("test failure path")
 lethal.open_battle(fatal);lethal.automation.matched(slot,found.troop.enemies[slot])
 for turn in range(201):
  if not lethal.automation.running:break
  lethal.automation.step()
 lethal.automation.flow_step()
 check(lethal.automation.flow_phase=="restart" and int(lethal.automation.flow_skipped_count)==1 and lethal.session.snapshot().pets.size()==1,"real target death records a failure and restarts search without awarding a capture")
 lethal.automation.flow_step()
 check(lethal.automation.flow_phase=="hunt" and lethal.automation.hunt_running,"failed target is followed by a real new search")
 lethal.handle({"type":"auto_stop"});lethal.queue_free()
 backend.queue_free();await process_frame
 print("CLEAR CAPTURE: %d failures"%failures);quit(1 if failures else 0)
