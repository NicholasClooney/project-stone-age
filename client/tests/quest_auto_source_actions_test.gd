extends SceneTree
## Dormant policy/frame checks only. Not an END44 execution or route acceptance.
const Backend=preload("res://server/backend.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
const Frame=preload("res://server/quest_auto_source_frame.gd")
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const Plan=preload("res://server/quest_auto_golden_bui_plan.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func service(source:String)->Dictionary:
 var recipe:Dictionary=Source.recipe(source)
 var id:String="%s@%d:%d:%d"%[source,recipe.map_id,recipe.cell[0],recipe.cell[1]]
 return {"id":"golden44:%s:%s"%["entry" if recipe.kind=="golden_bui_gate" else "challenge",source],"action":"source_service","label":"source fixture","npc_id":id,"map_id":recipe.map_id,"cell":recipe.cell.duplicate(),"source":{"policy":"golden44_service_v1","source_id":source,"service_id":source,"kind":recipe.kind}}
func exchange(room:int,claim:bool)->Dictionary:
 var source:String="quiz/equiz_01" if claim else "quiz/equiz_02"
 var branch:Dictionary=Source.CLAIM_BRANCH if claim else Source.PET_BRANCH
 var cell:Array=[29 if claim else 28,16]
 return {"id":"golden44:%s:%d"%["claim" if claim else "exchange",room],"action":"source_exchange","label":"exchange fixture","npc_id":"%s@%d:%d:%d"%[source,room,cell[0],cell[1]],"map_id":room,"cell":cell,"source":{"policy":"golden44_claim_v1" if claim else "golden44_pet14_v1","source_id":source,"branch_index":branch.source_branch_index,"branch_data":branch.duplicate(true)}}
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=Backend.new()
 var before:Dictionary=b.session.snapshot()
 var count:=0
 for base in [800,820,840]:
  for offset in range(10):
   var source:String="genout/%s_%d_%d_19"%["jan" if offset in [2,4,7] else "quz",base+offset,29 if offset%2==0 else 18]
   var step:=service(source)
   check(Source.validate_step(b,2,step).ok,"Actual reviewed source "+source)
   var decoded:Dictionary=JSON.parse_string(JSON.stringify(step))
   check(Source.validate_step(b,2,decoded).ok,"JSON integer-valued source fields remain valid")
   count+=1
 for source in Source.GATES:
  check(Source.validate_step(b,2,service(source)).ok,"Exact original entry source "+source);count+=1
 check(count==35,"Only 21 quiz, 9 janken and 5 entry sources")
 check(Source.recipe("genout/wpm_800_34_23").is_empty() and Source.recipe("genout/quz_812_29_19").is_empty(),"Exit and later job47 source excluded")
 for room in [810,850]:
  for claim in [true,false]:
   var step:=exchange(room,claim)
   check(Source.validate_step(b,2,step).ok,"Exact source index 3/4, not runtime array index")
   check(Source.validate_step(b,2,JSON.parse_string(JSON.stringify(step))).ok,"Whole original branch tolerates JSON numeric encoding only")
 var valid:=service("genout/quz_800_29_19")
 for field in ["id","npc_id","map_id","cell","source"]:
  var bad:Dictionary=valid.duplicate(true)
  match field:
   "id":bad.id="golden44:challenge:other"
   "npc_id":bad.npc_id="other"
   "map_id":bad.map_id=800.1
   "cell":bad.cell=[true,19]
   "source":bad.source.kind="original_jug_shop"
  check(not Source.validate_step(b,2,bad).ok,"Reject altered "+field)
 var bad:Dictionary=valid.duplicate(true);bad.target={"map_id":850,"cell":[28,17]}
 check(not Source.validate_step(b,2,bad).ok,"Client-like destination cannot extend source step")
 check(not Source.validate_step(b,44,valid).ok,"Job id is 2, not event44")
 check(not Source.validate_step(b,2,{"id":"golden44:stairs:800","action":"walk_portal","label":"stairs","source":{}}).ok,"Missing exact stairs tuple is rejected")
 bad=exchange(810,false);bad.source.branch_data.actions.GetPet="15"
 check(not Source.validate_step(b,2,bad).ok,"No generic GetPet capability")
 bad=exchange(810,false);bad.source.branch_data.texts.ThanksMsg="changed"
 check(not Source.validate_step(b,2,bad).ok,"Complete branch includes original text")
 bad=exchange(810,false);bad.source.branch_index=0
 check(not Source.validate_step(b,2,bad).ok,"Projected array index cannot substitute source index")
 var pets:Dictionary=b.quest_catalog.reward_pets.duplicate(true)
 b.quest_catalog.reward_pets["14"].level=77
 check(not Source.validate_step(b,2,exchange(810,false)).ok,"No later level77 reward substitution")
 b.quest_catalog.reward_pets=pets
 var duplicate:Dictionary=b.original_quests.npc_by_id(valid.npc_id)
 b.quest_catalog.npcs.append(duplicate)
 check(not Source.validate_step(b,2,valid).ok,"Duplicate NPC is not authority")
 b.quest_catalog.npcs.pop_back()
 check(Source.same_source([44.0],[44]) and not Source.same_source([44.5],[44]) and not Source.same_source([true],[1]),"No fractional/bool numeric authority")
 check(b.session.snapshot()==before and not b.quest_auto.running and b.original_quests.pending.is_empty(),"Policy checks have no transaction or registration side effects")
 check(b.quest_auto.delivery_supports(2),"Only reviewed job2 is registered")
 portals(b)
 admission(b)
 b.free()
 frames()
 print("QUEST AUTO SOURCE ACTION PREPARATION: %d failures"%failures)
 quit(1 if failures else 0)
func frames()->void:
 var f=Frame.new()
 var identity:Dictionary={"run_id":"0123456789abcdef0123456789abcdef","step_id":"golden44:challenge:genout/quz_800_29_19","revision":4}
 check(f.configure(identity,17,"npc","source"),"Bind complete internal run identity")
 for key in ["run_id","step_id","revision"]:
  var stale:Dictionary=identity.duplicate()
  stale[key]=3 if key=="revision" else "stale"
  check(not f.matches(stale,17),"Every identity field binds the public page")
 for revision in [true,4.5,NAN,INF]:
  var malformed:Dictionary=identity.duplicate();malformed.revision=revision
  check(not Frame.valid_identity(malformed),"Reject noninteger/nonfinite/bool revision")
 var call=f.begin_call(identity,17)
 check(call!=null and f.begin_call(identity,17)==null,"No nested service invocation")
 f.enter_publication(call)
 check(not f.record_saved(call,99),"A publication callback save is not this transaction")
 f.leave_publication(call)
 check(not f.record_saved(RefCounted.new(),99),"Wrong frame capability cannot attest a save")
 check(f.record_saved(call,10) and not f.record_saved(call,11),"Exactly one original save recorded before publication")
 var page:Dictionary={"token":"live-1","npc_id":"npc","kind":"golden_bui_quiz","text":"public fixture","input":"choice","choices":[{"id":"1","text":"one"},{"id":"cancel","text":"取消"}]}
 for field in ["npc_id","token","choices","answer"]:
  var forged:Dictionary=page.duplicate(true)
  match field:
   "npc_id":forged.npc_id="other"
   "token":forged.token="old"
   "choices":forged.choices.append(forged.choices[0].duplicate())
   "answer":forged.answer="private answer is never a public field"
  check(not f.receive_page(call,forged,"live-1"),"Wrong-source/old/private/ambiguous page refused")
 check(f.receive_page(call,page,"live-1"),"Bind only the actual public returned token")
 check(f.complete_call(call,identity,17).committed,"Matched save has a receipt")
 check(f.take_choice(identity,17,"live-1","unknown").is_empty(),"Unknown choice is not submitted")
 check(f.take_choice(identity,18,"live-1","1").is_empty(),"Other socket cannot consume this page")
 check(not f.take_choice(identity,17,"live-1","1").is_empty() and f.take_choice(identity,17,"live-1","1").is_empty(),"Page token reserved once before source call")
 call=f.begin_call(identity,17)
 page.token="live-2"
 check(f.receive_page(call,page,"live-2"),"New public page may progress without another save")
 check(not f.complete_call(call,identity,17).committed,"Intermediate ok is not persistent success")
 f.detach()
 check(f.begin_call(identity,17)==null,"Detach freezes service calls")
 var next:Dictionary=identity.duplicate();next.revision=5
 check(not f.rebind(next,18,"missing") and f.rebind(next,18,"live-2"),"Reconnect requires still-live page and newer identity")
 call=f.begin_call(next,18)
 check(f.record_saved(call,12),"Source transaction saved before cancellation")
 f.cancel();page.token="late"
 check(not f.receive_page(call,page,"late"),"Late page cannot revive cancelled runner")
 var result:Dictionary=f.complete_call(call,next,18)
 check(result.committed and not result.continued,"Cancellation preserves committed fact only")
 check(f.owns_pending("late") and not f.owns_pending("new-manual"),"Cleanup owns only old call page, preserves later manual token")

func portals(b)->void:
 for row in Sources.table().portals:
  var portal:Dictionary={"from_map":row.from_map,"from_cell":row.from_cell.duplicate(),"to_map":row.to_map,"to_cell":row.to_cell.duplicate()}
  var step:Dictionary={"id":"golden44:stairs:%d"%int(row.from_map),"action":"walk_portal","label":"original stairs","source":{"policy":"golden44_stairs_v1"},"portal":portal}
  check(Source.validate_step(b,2,step).ok,"Exact approved original link "+step.id)
  for key in ["from_cell","to_cell","to_map"]:
   var bad:Dictionary=step.duplicate(true)
   if key=="to_map":bad.portal.to_map+=1
   else:bad.portal[key][0]+=1
   check(not Source.validate_step(b,2,bad).ok,"No adjacent/unapproved door or target fallback")
  var links:Dictionary=b.quest_helper.places.links(int(row.from_map))
  var cell:=Vector2i(int(row.from_cell[0]),int(row.from_cell[1]))
  var link:Dictionary=links[cell]
  var saved:Dictionary=link.duplicate(true)
  link.disabled=true
  check(not Source.validate_step(b,2,step).ok,"Disabled actual original link refuses")
  link.clear();link.merge(saved,true)
func admission(b)->void:
 b.session._profile.player.level=35
 b.automation.position_changed(811,Vector2i(30,22))
 var step:=service("genout/wpm_811_30_20")
 var before:Dictionary=b.session.snapshot()
 check(not Source.validate_open(b,2,step).ok,"No original ticket remains manual")
 check(b.session.snapshot()==before,"Admission never purchases a ticket")
 b.session._profile.original_items.append(2755) # Explicit inventory prerequisite fixture.
 var proposed:Dictionary=Plan.select(b,2)
 check(proposed.status=="step" and Source.validate_step(b,2,proposed.step).ok,"Real 4b entry proposal accepted by dormant core policy")
 check(Source.validate_open(b,2,step).ok,"Actual public entry ready with original ticket")
 before=b.session.snapshot()
 b.quest_visit_guard=func():return "party"
 check(not Source.validate_open(b,2,step).ok,"Party blocks service admission")
 b.quest_visit_guard=Callable()
 b.battle_open=true
 check(not Source.validate_open(b,2,step).ok,"Battle blocks service admission")
 b.battle_open=false
 b.original_quests.pending={"token":"manual"}
 check(not Source.validate_open(b,2,step).ok,"Never replace an unrelated manual dialogue")
 b.original_quests.pending={}
 b.automation.running=true
 check(not Source.validate_open(b,2,step).ok,"Other runner blocks source admission")
 b.automation.running=false
 b.automation.position_changed(811,Vector2i(30,25))
 check(not Source.validate_open(b,2,step).ok,"Original max-distance two remains enforced")
 b.automation.position_changed(800,Vector2i(29,21))
 b.session._profile.original_items.append(2752)
 check(not Source.validate_open(b,2,service("genout/quz_800_29_19")).ok,"Protected coordinates alone cannot create proof")
 check(b.quest_auto.delivery_supports(2) and not b.quest_auto.running,"Read-only proposals never start registered job2")
