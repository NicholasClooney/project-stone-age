extends SceneTree
## STATIC UNRUN. Complete-copy eligibility only; never a real route or transaction.
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Plan=preload("res://server/quest_auto_munde_plan.gd")
var b
var base:Dictionary={}
var assertions:int=0
var failures:int=0
var fixture_failed:bool=false
var last:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func fixture_ready()->bool:
 if fixture_failed:
  if failures==0:check(false,"fixture did not complete; stop before branch/proposal")
  return false
 return true
func fixture(ended:Array,now:Array,items:Array,level:int)->Dictionary:
 fixture_failed=true
 var base_before:Dictionary=base.duplicate(true)
 var live_before:Dictionary=b.session._profile.duplicate(true)
 var p:Dictionary=base.duplicate(true)
 Equipment.migrate(p)
 if not check(p.get("original_items") is Array and p.get("original_instances") is Array and p.get("original_equipment") is Dictionary and typeof(p.get("next_original_uid"))==TYPE_INT and p.get("next_original_uid",0)>0,"fixture migration creates items/instances/equipment/positive integer next_uid"):return {}
 if not check(p.original_items.size()==p.original_instances.size() and p.original_equipment.size()==5,"fixture migrated collection structure"):return {}
 for slot in ["arm","bracelet","amulet","head","body"]:
  if not check(typeof(p.original_equipment.get(slot))==TYPE_INT and p.original_equipment.get(slot,-1)>=0,"fixture migrated equipment slot integer"):return {}
 for index in range(p.original_items.size()):
  var entry:Variant=p.original_instances[index]
  if not check(typeof(p.original_items[index])==TYPE_INT and entry is Dictionary,"fixture migrated item and instance types"):return {}
  if not check(typeof(entry.get("uid"))==TYPE_INT and entry.get("uid",0)>0 and entry.get("uid",0)<p.next_original_uid and typeof(entry.get("item_id"))==TYPE_INT and entry.get("item_id")==p.original_items[index] and typeof(entry.get("durability"))==TYPE_INT,"fixture migrated instance fields and UID bound"):return {}
 if not check(base==base_before and b.session._profile==live_before,"fixture migration preserves base and live full profile"):return {}
 p.player.level=level
 for value in [4,9,10,11,12,17,20,21,22,27]:
  Rules.set_flag(p,"ended",value,value in ended)
  Rules.set_flag(p,"now",value,value in now)
 # Complete copy, actual item-instance constructor; never add to live base.
 p.original_items=[];p.original_instances=[]
 for slot in p.original_equipment:p.original_equipment[slot]=0
 for item in items:Equipment.add(p,int(item))
 if not check(base==base_before and b.session._profile==live_before,"fixture eligibility edits preserve base and live full profile"):return {}
 fixture_failed=false
 return p

func state()->Dictionary:
 return {"profile":b.session._profile.duplicate(true),"position":[b.automation.position_map,b.automation.position_cell],"scope":b.quest_arrival._scope,"marks":b.quest_arrival._marks.duplicate(true),"stages":b.quest_arrival._stages.duplicate(true),"pending":b.original_quests.pending.duplicate(true),"session_pending":b.session._pending.duplicate(true),"serial":b.original_quests.serial,"save_serial":b.quest_save_serial,"resume_writes":b.resume_writes,"running":b.quest_auto.running,"battle":b.battle_open,"catalog":b.quest_catalog.npcs.duplicate(true),"jobs":b.quest_catalog.jobs.duplicate(true),"overrides":b.quest_catalog.npc_overrides.duplicate(true),"enabled":b.quest_catalog.enabled_events.duplicate()}
func invoke(p:Dictionary,kind:String,job:int,dialogue:Dictionary={})->Dictionary:
 var saved:Dictionary=b.session._profile
 b.session._profile=p
 var before:Dictionary=state()
 var result:Dictionary={}
 result=Plan.request10_proposal(b,job)
 var unchanged:bool=state()==before
 b.session._profile=saved
 check(unchanged,"single proposal leaves profile/catalog/authority/proof/save/pending unchanged")
 return result
func case_row(ended:Array,now:Array,items:Array,level:int,stage:String,kind:String,job:int,dialogue:Dictionary={})->bool:
 var p:Dictionary=fixture(ended,now,items,level)
 if not fixture_ready():return false
 # Preconditions are inspected directly; no extra select/branch_for/snapshot query.
 if not check(p.player.level==level and p.original_items==items,"case level and item eligibility actually installed"):return false
 for event in [4,9,10,11,12,17,20,21,22,27]:
  if not check(Rules.flag(p,"now",event)==(event in now) and Rules.flag(p,"ended",event)==(event in ended),"case complete flag preconditions"):return false
 last=invoke(p,kind,job,dialogue)
 if failures:return false
 if stage=="step":return check(last.get("status")=="step" and last.has("step"),"exact ordinary proposal")
 if stage=="done":return check(last.get("status")=="done" and not last.has("step"),"final event stops")
 return check(last.get("status")=="manual" and last.get("stage")==stage and not last.has("step"),"manual stage "+stage)
func drift(p:Dictionary,kind:String,job:int,nid:String,event:int)->bool:
 var target:Dictionary={}
 for npc in b.quest_catalog.npcs:
  if npc.id==nid:target=npc;break
 if not check(not target.is_empty(),"mutation target exists"):return false
 var saved:Dictionary=target.duplicate(true)
 for mode in ["action","order","fraction","bool","events","coordinate"]:
  if mode=="action":target.branches[0].actions["probe"]="drift"
  elif mode=="order":
   if target.branches.size()>1:target.branches.reverse()
   else:target.branches.append(target.branches[0].duplicate(true))
  elif mode=="fraction":target.branches[0]["source_branch_index"]=0.5
  elif mode=="bool":target.branches[0]["source_branch_index"]=true
  elif mode=="events":target.branches[0].events=[]
  else:target.cell=[int(saved.cell[0])+1,int(saved.cell[1])]
  var triggered:bool=not Plan.same_source(target,saved)
  var result:Dictionary=invoke(p,kind,job)
  target.clear();target.merge(saved.duplicate(true))
  if failures:return false
  if not check(triggered and result.get("stage")=="source_changed","full source drift really triggered: "+mode):return false
 var overrides:Dictionary=b.quest_catalog.npc_overrides.duplicate(true)
 for mode in ["move","hide"]:
  b.quest_catalog.npc_overrides[nid]={"map_id":int(saved.map_id),"cell":[int(saved.cell[0])+1,int(saved.cell[1])]} if mode=="move" else {"hidden":true}
  # One active read proves production map+cell/hidden projection, not a search or branch query.
  var projected:Dictionary=b.quest_catalog.active_npc(nid)
  var triggered:bool=not Plan.same_source(projected.get("cell"),saved.cell) if mode=="move" else projected.is_empty()
  var result:Dictionary=invoke(p,kind,job)
  b.quest_catalog.npc_overrides=overrides.duplicate(true)
  if failures:return false
  if not check(triggered and result.get("stage")=="source_changed","actual active projection trigger: "+mode):return false
 var job_row:Dictionary={}
 for candidate in b.quest_catalog.jobs:
  if Plan.same_source(candidate.get("id"),job):job_row=candidate;break
 if not check(not job_row.is_empty(),"job mutation target exists"):return false
 var old_job:Dictionary=job_row.duplicate(true)
 job_row["audit_probe"]="drift"
 var job_changed:bool=not Plan.same_source(job_row,old_job)
 var rejected:Dictionary=invoke(p,kind,job)
 job_row.clear();job_row.merge(old_job)
 if failures:return false
 if not check(job_changed and rejected.get("stage")=="source_changed","full job metadata drift rejects"):return false
 var enabled:Array=b.quest_catalog.enabled_events.duplicate()
 b.quest_catalog.enabled_events.erase(event)
 var triggered:bool=not event in b.quest_catalog.enabled_events
 var result:Dictionary=invoke(p,kind,job)
 b.quest_catalog.enabled_events=enabled
 if failures:return false
 return check(triggered and result.get("stage")=="disabled","required event removal really applied")
func run()->void:
 b=Backend.new()
 b.automation.position_changed(1000,Vector2i(80,90),true,"project")
 base=b.session._profile.duplicate(true)
 var baseline:Dictionary=state()
 if not check(b.quest_arrival._scope.is_empty() and b.quest_arrival._marks.is_empty() and b.quest_arrival._stages.is_empty(),"explicit public authority is not protected arrival or saved location"):finish();return
 if not case_row([4],[9, 11],[],30,"step","munde",8):finish();return
 if not check(Plan.same_source(last.step.source.branch_index,2) and Plan.same_source(last.step.source.source_line,28) and last.step.source.actions=={} and last.step.source.branch_data.condition=="LV>29&ENDEV=4&NOWEV=9&NOWEV=11","exact original request10 identity/actions"):finish();return
 var output:Dictionary=last
 if not case_row([4],[9],[],30,"request11","munde",8):finish();return
 if not case_row([4],[9, 11],[],29,"branch_unavailable","munde",8):finish();return
 if not case_row([],[9, 11],[],30,"branch_unavailable","munde",8):finish();return
 if not case_row([4],[11],[],30,"request9","munde",8):finish();return
 if not case_row([4],[9, 10, 11],[],30,"keyword_route","munde",8):finish();return
 if not case_row([4],[9, 10, 11],[2420],30,"return_stone_charm","munde",8):finish();return
 if not case_row([4, 11],[9, 10],[2419],30,"return_stone10","munde",8):finish();return
 if not case_row([4, 12],[9, 11],[2419],30,"branch_unavailable","munde",8):finish();return
 if not case_row([9],[],[],30,"done","munde",8):finish();return
 var p:Dictionary=fixture([4],[9,11],[],30)
 if not fixture_ready():finish();return
 if not drift(p,"munde",8,"sainasu/event/event10@1300:65:65",10):finish();return
 output.step.source.branch_data.actions["alias"]="bad"
 var fresh:Dictionary=invoke(p,"munde",8)
 if failures:finish();return
 if not check(fresh.get("status")=="step" and fresh.step.source.branch_data.actions=={},"independent returned source copy"):finish();return
 # No proof is minted: use a deliberately unqualified protected map only as a negative; never claim arrival.
 var old_map:int=b.automation.position_map
 var old_cell:Vector2i=b.automation.position_cell
 b.automation.position_map=11107;b.automation.position_cell=Vector2i.ZERO
 var denied:Dictionary=invoke(p,"munde",8)
 b.automation.position_map=old_map;b.automation.position_cell=old_cell
 if failures:finish();return
 if not check(denied.get("stage")=="arrival_required","protected map with empty scope has no legitimate arrival"):finish();return
 var numeric:Variant=JSON.parse_string("[2,3]")
 if not check(Plan.same_source(numeric,[2,3]) and not Plan.same_source([2.5,3],[2,3]) and not Plan.same_source([true,3],[1,3]) and not Plan.same_source([3,2],[2,3]),"ordered finite integral JSON comparison, no coercion"):finish();return
 if not check(state()==baseline and b.session._profile==base,"all test fixtures restored; complete native/counters/catalog preserved"):finish();return
 finish()
func finish()->void:
 if b!=null:b.free()
 print("quest_auto_munde_request10_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
