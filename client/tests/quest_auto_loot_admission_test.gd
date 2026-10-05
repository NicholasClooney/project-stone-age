extends "res://tests/quest_auto_loot_state_test.gd"
const Backend=preload("res://server/backend.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
const Plan=preload("res://server/quest_auto_jewel_loot_plan.gd")
class ObservedBackend:
 extends "res://server/backend.gd"
 var observer:Callable
 var commits:=0
 func _loot_settlement_written(payload:String,owner,path:String)->void:
  super._loot_settlement_written(payload,owner,path)
  commits+=1
  if observer.is_valid():observer.call(self)
func setup(b,path:String)->bool:
 b.set_process(false);b.save_path=path
 b.session.OriginalEquipment.add(b.session._profile,2764)
 var found:=false
 check(b.quest_helper.maps.is_empty(),"Fresh internal fixture has a genuinely cold helper map cache")
 if failures:return false
 var data:Dictionary=preload("res://scripts/map_file.gd").load_map(b.quest_helper.places.file(100))
 check(b.quest_loot.admission_terrain_valid(data),"Original loader terrain shape checked before scanning any cell")
 if failures:return false
 var links:Dictionary=b.quest_helper.places.links(100)
 for y in range(341,413):
  for x in range(621,646):
   var cell:=Vector2i(x,y)
   if b.encounter_catalog.area_at(100,cell).get("id")!=56:continue
   if not b.quest_helper.safe(data,cell,{},links):continue
   b.automation.position_changed(100,cell,true,"project")
   found=true;break
  if found:break
 if not found:return false
 var q=b.quest_auto;q.identity.begin();q.identity.select_step(KEY)
 q.running=true;q.internal=true;q.detached=false;q.restored=false
 q.connection=71;q.client="admission-internal-fixture";q.phase="loot_admission";q.step=Sources.step()
 return b.save()
func guard_cases()->bool:
 for guard_name in ["quest_visit_guard","party_guard"]:
  for stage in ["initial","before_open"]:
   for mutation in ["cancel","runner","identity","source"]:
    var b=ObservedBackend.new()
    if not setup(b,"user://loot-guard-%s-%s-%s.json"%[guard_name,stage,mutation]):check(false,"Guard fixture setup");b.free();return false
    var called:Array=[false]
    var old_runner=b.quest_auto
    var hook:Callable=func():
     if called[0] or (stage=="before_open" and b.commits==0):return ""
     called[0]=true
     match mutation:
      "cancel":old_runner.stop(b,"Actual guard cancellation")
      "runner":b.quest_auto=preload("res://server/quest_auto.gd").new()
      "identity":old_runner.identity.begin();old_runner.identity.select_step(KEY)
      "source":old_runner.step.source.signature="changed-by-guard"
     return ""
    b.set(guard_name,hook)
    var before:Dictionary=b.session.snapshot()
    var disk:String=FileAccess.get_file_as_string(b.save_path)
    var reply:Dictionary=b.quest_loot.admit_prepared_run(b)
    check(called[0] and not reply.get("ok",false) and b.quest_loot.anchor_ms<0,"Actual Callable rejects old invocation: %s/%s/%s"%[guard_name,stage,mutation])
    if failures:b.free();return false
    if stage=="initial":
     check(b.commits==0 and b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk,"Initial guard never writes a successor run")
    else:
     check(b.commits==1 and not b.session._profile.quest_loot.entries[KEY].open_span,"Post-acquire guard forbids open; committed acquire stays")
    if failures:b.free();return false
    b.free()
 return true
func run()->void:
 # Public source position/internal runner are explicit fixtures, never proof.
 for mode in ["normal","disabled","missing_item","connection","savefail","cancel_acquire","cancel_open","newsave","lifetime_token_replacement"]:
  var b=ObservedBackend.new()
  if not setup(b,"user://loot-admission-"+mode+".json"):check(false,"Original public area fixture setup");b.free();quit(1);return
  check(Plan.select(b,Sources.matches_backend).get("status")=="step","Real plan consumes real complete source verifier")
  if failures:b.free();quit(1);return
  if mode=="disabled":b.session._profile.no_random_encounters=true
  if mode=="missing_item":b.session._profile.original_items.erase(2764)
  if mode=="connection":b.quest_auto.connection=-1
  if mode=="savefail":
   check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own tmp blocker")
   if failures:b.free();quit(1);return
  if mode.begins_with("cancel_"):
   var at:int=1 if mode=="cancel_acquire" else 2
   b.observer=func(host):
    if host.commits==at:host.quest_auto.stop(host,"Admission observer cancels")
  if mode=="newsave":
   b.observer=func(host):
    if host.commits==2:
     host.session._profile.player.gold+=1
     check(host.save(),"Later observer save succeeds")
  # Synthetic token replacement only; NOT start/accept lifecycle API coverage.
  if mode=="lifetime_token_replacement":
   b.observer=func(host):
    if host.commits==2:host.quest_loot.lifetime=RefCounted.new()
  var before:Dictionary=b.session.snapshot()
  var disk:String=FileAccess.get_file_as_string(b.save_path)
  var pressure:int=b.encounter_catalog.pressure;var rng:int=b.encounter_rng.state
  var result:Dictionary=b.quest_loot.admit_prepared_run(b)
  if failures:b.free();quit(1);return
  check(not b.battle_open and b.session._pending.is_empty() and b.encounter_catalog.pressure==pressure and b.encounter_rng.state==rng,"E1 never rolls/opens battle")
  if failures:b.free();quit(1);return
  if mode=="normal":
   check(b.quest_helper.maps.is_empty(),"Successful admission did not warm helper cache")
   if failures:b.free();quit(1);return
   check(result.get("ok",false) and b.commits==2 and b.session._profile.quest_loot.entries[KEY].open_span and b.quest_loot.anchor_ms>=0,"Actual acquire/open precede timer")
   if failures:b.free();quit(1);return
   var saved:String=FileAccess.get_file_as_string(b.save_path)
   check(not b.quest_loot.admit_prepared_run(b).ok and FileAccess.get_file_as_string(b.save_path)==saved,"Repeated start cannot reset/open existing span")
  else:
   check(not result.get("ok",false) and b.quest_loot.anchor_ms<0,"Failure/observer change never arms old timer")
   if failures:b.free();quit(1);return
   if mode in ["disabled","missing_item","connection","savefail"]:
    check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk and b.commits==0,"Admission refusal/failure preserves complete profile and bytes")
   elif mode=="cancel_acquire":check(b.commits==1 and not b.session._profile.quest_loot.entries[KEY].open_span,"Cancel first commit forbids second write")
   elif mode=="cancel_open":check(result.get("persisted",false) and b.commits==3 and not b.session._profile.quest_loot.entries[KEY].open_span,"E3 closes the actual saved open cancelled before timer startup")
   else:check(result.get("persisted",false) and b.session._profile.quest_loot.entries[KEY].open_span,"Already saved open is reported, never pretended rollback")
  if failures:b.free();quit(1);return
  # Do not remove blocker or proceed to next fixture after any failed assertion.
  if mode=="savefail":
   check(DirAccess.remove_absolute(b.save_path+".tmp")==OK,"Remove only own proven blocker")
   if failures:b.free();quit(1);return
  b.free()
 if not guard_cases():quit(1);return
 print("QUEST AUTO LOOT ADMISSION: %d failures; internal prepared run, no attempt/WS/public entry"%failures)
 quit(1 if failures else 0)
