extends SceneTree
## Real battle settlement/session + file-backed capture history.
const Backend=preload("res://server/backend.gd")
const Battle=preload("res://server/battle_session.gd")
const Progression=preload("res://server/progression.gd")
const Filter=preload("res://scripts/pet_stat_filter.gd")
const Log=preload("res://server/release_log.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func capture(backend,troop:Dictionary)->Dictionary:
 var config:Dictionary=backend.session.start_wild_battle_config(troop)
 check(not config.is_empty(),"real wild capture config accepted")
 if config.is_empty():return {}
 config.player_attack=100;config.player_speed=100;config.player_defence=100
 var battle=Battle.new();battle.start_battle(config)
 for i in range(100):
  battle.submit_action("capture",0)
  if not battle.snapshot().active:break
 check(battle.snapshot().outcome=="captured" and backend.session.apply_battle_result(battle.snapshot()),"real capture settles through session")
 backend.handle({"type":"ping"})
 return backend.capture_log.entries().back()
func run():
 var backend=Backend.new();backend.set_process(false);root.add_child(backend)
 backend.capture_log_path="user://capture-reasons.jsonl"
 DirAccess.remove_absolute(ProjectSettings.globalize_path(backend.capture_log_path))
 var rng:=RandomNumberGenerator.new();rng.seed=1234
 var troop:Dictionary={}
 for i in range(500):
  var rolled:Dictionary=backend.encounter_catalog.roll(100,Vector2i(637,493),rng)
  for actor in rolled.get("enemies",[]):
   if int(actor.level)==1 and actor.can_capture:
    actor.hp=1;troop={"enemies":[actor]};break
  if not troop.is_empty():break
 check(not troop.is_empty(),"original catalog provides actual Lv1 pet")
 if troop.is_empty():quit(1);return
 var auto=backend.automation
 auto.flow_phase="capture";auto.flow_run_id="capture-reasons-run";auto.flow_target_filter={"conditions":{}}
 var first:=capture(backend,troop)
 check(first.capture_decision.tags==["unconditional"],"disabled conditions explicitly capture every pet")
 check(first.capture_decision.metrics.all(func(m):return m.original_max==null and int(m.rank)==1 and int(m.ties)==0),"first pet has no original same-species maximum")
 var stats:Dictionary=Progression.project_pet(troop.enemies[0],120)
 var template:int=troop.enemies[0].template_id
 var raw:Dictionary=Filter.defaults(template)
 raw.threshold_mode="relative";raw.conditions={"attack":{"enabled":true,"minus":1,"value":0}}
 auto.flow_stat_filters[template]=raw;auto.flow_target_filter=Filter.resolve(raw,Filter.maxima([stats]))
 var hit:Dictionary={"actor":troop.enemies[0].duplicate(true),"prediction":stats,"index":10,"run_seed":123,"slot":0,"troop":troop}
 auto.showcase_current=hit
 auto.showcase_queue=[hit.duplicate(true)] # same UID must never compare itself
 var second:=capture(backend,troop)
 check(second.capture_decision.tags==["stats"] and second.capture_decision.threshold_text.contains("满足"),"relative threshold stores its actual passing value")
 check(second.capture_decision.metrics.all(func(m):return int(m.rank)==1 and int(m.ties)==1 and int(m.original_max)==int(m.value)),"competition ties exclude current/queue duplicate and candidate itself")
 var saved:Dictionary=second.capture_decision.duplicate(true)
 check(backend.session.gm_grant_pet(template,true),"real same-species full-grade pet supplies higher comparisons")
 backend.handle({"type":"ping"})
 var owned:Array=backend.session.snapshot().pets
 backend.session._profile.pet_storage.append(owned[0].duplicate(true))
 var repeated:Dictionary=hit.duplicate(true);repeated.index=11;repeated.actor=owned.back().duplicate(true);repeated.prediction=Progression.project_pet(repeated.actor,120)
 auto.showcase_queue=[hit.duplicate(true),repeated,repeated.duplicate(true)]
 var ranked:=capture(backend,troop)
 var expected:Array=owned.map(func(p):return Progression.project_pet(p,120))
 for metric in ranked.capture_decision.metrics:
  var higher:int=expected.filter(func(p):return Filter.rank_value(p,str(metric.key))>int(metric.value)).size()
  check(int(metric.rank)==1+higher,"strictly higher count decides %s competition rank, duplicate owned/waiting IDs ignored"%metric.key)
 check(ranked.capture_decision.metrics.any(func(m):return int(m.rank)>1),"real stronger pet puts at least one metric below first place")
 backend.session._profile.pet_storage=[]

 auto.flow_target_survey=true
 var survey:=capture(backend,troop)
 check(survey.capture_decision.tags.has("survey"),"survey selection remains a combinable reason")
 auto.flow_target_survey=false;raw.threshold_mode="absolute";raw.conditions.attack.value=int(stats.attack)
 auto.flow_target_filter=Filter.resolve(raw,{})
 auto.hunt_filter={"clean_only":true,"mixed_if_stats":true}
 var mixed_troop:Dictionary=auto.showcase_current.troop.duplicate(true)
 auto.showcase_current={};auto.showcase_queue=[];auto.refresh_maxima()
 var earlier:Dictionary=hit.duplicate(true);earlier.index=9
 auto._showcase_add(earlier);auto._showcase_add(hit)
 auto._take_queued();auto.showcase_current=auto._take_queued()
 auto.showcase_current.troop=mixed_troop
 var mixed:=capture(backend,troop)
 check(mixed.capture_decision.tags==["stats"],"absolute passing condition is captured without claiming a clean troop is mixed")
 check(mixed.capture_decision.queue.admission_rank==2 and mixed.capture_decision.queue.departure_rank==1 and float(mixed.capture_decision.queue.wait_seconds)>=0 and float(mixed.capture_decision.queue.wait_seconds)<30,"queue explains admission/departure ranking and exact elapsed time")
 auto.flow_phase="";auto.showcase_current={};auto.showcase_queue=[]
 var manual:=capture(backend,troop)
 check(manual.capture_decision.tags==["manual"],"manual capture makes no automatic gate claim")
 check(backend.session.gm_grant_pet(92),"actual GM grant succeeds")
 backend.handle({"type":"ping"})
 check(backend.capture_log.entries().back().capture_decision.tags==["gm"],"GM capture remains explicit")
 backend.session.gm_raise_level(0,120)
 auto.flow_stat_filters={};auto.flow_target_filter={}
 var reread=Log.new();reread.path=backend.capture_log_path
 check(reread.entries()[1].capture_decision==saved,"file reload preserves frozen decision after inventory/rule changes")
 check(backend.session.save_game("user://capture-reasons-save.json") and backend.session.load_game("user://capture-reasons-save.json"),"save reload accepts independent capture log")
 reread.append([{"pet_id":"old","name":"old"}])
 check(not reread.entries().back().has("capture_decision"),"old log entries remain readable without fabricated fields")
 var menu=load("res://scripts/adventure_menu.gd")
 check(menu.capture_reason_details(reread.entries().back()).contains("—"),"old log UI shows unavailable reason")
 check(menu.capture_reason_details(second).contains("并列第1") and menu.capture_reason_details(first).contains("原最高 —"),"UI renders server ties and unavailable original maximum")
 backend.queue_free();await process_frame
 print("CAPTURE REASONS: %d failures"%failures);quit(1 if failures else 0)
