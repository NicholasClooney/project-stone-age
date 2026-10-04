extends SceneTree
## Internal hook matrix, NOT job2/full-route acceptance. Entry/first quiz use
## the real gate and original walk. REQUEST tail cases explicitly isolate the
## save/publication boundary with a prequalified-arrival stub (no route claim).
const Backend=preload("res://server/backend.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Rules=preload("res://server/original_quests.gd")
class ClaimArrival:
 extends "res://server/quest_legitimate_arrival.gd"
 func has_arrival(_b,map_id:int,_cell:Vector2i)->bool:return map_id==810
 func check_action(_b,npc:Dictionary,_branch:Dictionary,_phase:String)->String:
  return "" if npc.get("source_script") in ["quiz/equiz_01","quiz/equiz_02"] else "explicit claim fixture only"
var failures:=0
var assertions:=0
var serial:=0
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func fresh():
 var b=Backend.new();b.set_process(false)
 b.session._profile.player.level=35
 b.session._profile.no_random_encounters=true # Explicit short-hook fixture.
 return b
func service(id:String)->Dictionary:
 var r:=Source.recipe(id)
 return {"id":"golden44:%s:%s"%["entry" if r.kind=="golden_bui_gate" else "challenge",id],"action":"source_service","label":"hook fixture","npc_id":"%s@%d:%d:%d"%[id,r.map_id,r.cell[0],r.cell[1]],"map_id":r.map_id,"cell":r.cell.duplicate(),"source":{"policy":"golden44_service_v1","source_id":id,"service_id":id,"kind":r.kind}}
func claim(pet:bool=false)->Dictionary:
 var source:String="quiz/equiz_02" if pet else "quiz/equiz_01"
 var branch:Dictionary=Source.PET_BRANCH if pet else Source.CLAIM_BRANCH
 return {"id":"golden44:%s:810"%("exchange" if pet else "claim"),"action":"source_exchange","label":"claim boundary fixture","npc_id":"%s@810:%d:16"%[source,28 if pet else 29],"map_id":810,"cell":[28 if pet else 29,16],"source":{"policy":"golden44_pet14_v1" if pet else "golden44_claim_v1","source_id":source,"branch_index":branch.source_branch_index,"branch_data":branch.duplicate(true)}}
func arm(b,step:Dictionary)->void:
 var q=b.quest_auto
 q.running=true;q.quest_id=2;q.connection=17;q.client="hook-device";q.strict_walk=true;q.phase="source_fixture"
 q.identity.begin();q.identity.select_step(str(step.id));q.step=step.duplicate(true)
func open_source(b,step:Dictionary)->Dictionary:
 arm(b,step);b.quest_auto.internal=true
 var r:Dictionary=b.quest_auto.source_open(b,step)
 b.quest_auto.internal=false
 return r
func next(b)->Dictionary:
 b.quest_auto.internal=true
 var r:Dictionary=b.quest_auto.source_next(b)
 b.quest_auto.internal=false
 return r
func entry(b)->Dictionary:
 Equipment.add(b.session._profile,2755)
 b.automation.position_changed(811,Vector2i(30,22),true)
 return service("genout/wpm_811_30_20")
func quiz(b)->Dictionary:
 var step:=entry(b)
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":step.npc_id})
 check(r.ok and b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":"yes"}).ok,"Manual original paid entrance")
 var q:=service("genout/quz_800_29_19")
 check(Travel.walk_near(b,b.original_quests.npc_by_id(q.npc_id),[800]),"Real original first-floor approach")
 Equipment.add(b.session._profile,2752)
 return q
func persisted(b)->String:
 serial+=1
 b.save_path="user://source-hook-%d.json"%serial
 check(b.save(),"Initial disk baseline")
 return FileAccess.get_file_as_string(b.save_path)
func capture(events:Array,message:Dictionary)->void:events.append(message.duplicate(true))
func cancel_and_manual(b,step:Dictionary,state:Dictionary,message:Dictionary)->void:
 if state.get("fired",false) or message.get("type")!="profile":return
 state.fired=true
 state.saved_candidate=JSON.stringify(b.session.snapshot()).sha256_text()
 b.quest_auto.stop(b,"save observer cancellation")
 # This reenters handle while the automatic original service is still on the
 # stack at depth0. The later manual window must not inherit its capability.
 var manual:Dictionary=b.handle({"type":"quest_talk","npc_id":step.npc_id})
 check(manual.get("ok",false) and manual.has("dialogue"),"New manual window after cancellation")
 state.pending=b.original_quests.pending.duplicate(true)
 b.session._profile.player.gold+=1
 check(b.save(),"Independent observer save")
 state.final_serial=b.quest_save_serial
func tails(is_claim:bool,queued:bool)->void:
 var b=fresh()
 var step:Dictionary
 if is_claim:
  b.quest_arrival=ClaimArrival.new()
  b.automation.position_changed(810,Vector2i(29,18),true)
  step=claim()
 else:step=quiz(b)
 persisted(b)
 var r:=open_source(b,step)
 check(r.get("ok",false),"Open before tail cancellation: "+str(r))
 var state:Dictionary={}
 var callback:Callable=func(m):cancel_and_manual(b,step,state,m)
 b.event.connect(callback)
 if queued:b._depth+=1
 r=next(b)
 if queued:b._depth-=1;b._flush()
 check(state.get("fired",false),"Save publication observer ran")
 check(r.get("source_commit",{}).get("committed",false),"Actual source commit survives later stop and unrelated save")
 if not queued:check(not r.source_commit.continued,"Depth0 cancellation cannot continue original tail")
 check(r.source_commit.candidate_sha==state.get("saved_candidate",""),"Receipt belongs to original candidate, not later observer save")
 check(int(r.source_commit.save_serial)<int(state.get("final_serial",-1)),"Observer save cannot replace original successful boundary")
 check(b.original_quests.pending==state.get("pending",{}),"Cancelled SERVICE/REQUEST tail preserves complete newer manual pending")
 check(not b.quest_auto.running and b.quest_auto.issued.is_empty(),"No runner or receipt resurrection")
 check(2753 in b.session._profile.original_items if is_claim else not 2752 in b.session._profile.original_items,"Saved original item transaction is not rolled back by cancel")
 check(not next(b).get("ok",false),"Late automatic attempt refuses")
 b.free()
func gate(queued:bool,cancel_before_position:bool)->void:
 var b=fresh();var step:=entry(b);persisted(b)
 var events:Array=[];b.event.connect(func(m):capture(events,m))
 check(open_source(b,step).get("ok",false),"Gate opens without consuming or moving")
 if queued:b._depth+=1
 if cancel_before_position:
  b._emit({"type":"quest_result","text":"queued before actual saved Warp"})
  b.event.connect(func(m):
   if m.get("type")=="quest_result":b.quest_auto.stop(b,"before position dispatch")
  )
 var r:=next(b)
 if queued:b._depth-=1;b._flush()
 var positions:Array=events.filter(func(m):return m.get("type")=="position")
 check(r.get("source_commit",{}).get("committed",false),"Gate save is recorded")
 check(positions.size()==1,"One original Warp publishes once, without duplicate movement")
 check(b.automation.position_map==800 and b.automation.position_cell==Vector2i(14,26),"Original gate owns actual landing")
 check(b.quest_arrival.has_arrival(b,800,Vector2i(14,26)),"Original action_committed grants proof, never the project receipt")
 check(not 2755 in b.session._profile.original_items,"Original gate consumes exactly its real ticket")
 var disk=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
 check(disk.get("location",{}).get("map_id")==800,"Saved original Warp disk location")
 if not positions.is_empty():
  var packet:Dictionary=positions[0]
  check(packet.map_id==800 and packet.cell==[14,26],"Actual committed position still delivered")
  if cancel_before_position:
   check(not Motion.tagged(packet) and not b.quest_auto.running and b.quest_auto.issued.is_empty(),"Queued cancelled Warp becomes plain position, never stale receipt")
  else:
   check(Motion.tagged(packet) and packet.quest_ack_required and packet.get("quest_source_landing",false),"Saved source Warp requires full signed landing")
   var seq:Dictionary={"map_id":800,"cell":[14,26],"quest_position_seq":packet.quest_position_seq,"client":"hook-device","_quest_connection":17}
   b.handle(dict_command(seq))
   check(b.quest_auto.phase=="landing","Seq-only ACK cannot acknowledge source landing")
   for key in Motion.IDENTITY_FIELDS:seq[key]=packet[key]
   seq._quest_connection=18;b.handle(dict_command(seq))
   check(b.quest_auto.phase=="landing","Wrong connection cannot acknowledge")
   seq._quest_connection=17;b.handle(dict_command(seq))
   check(b.quest_auto.phase=="travel","Full current identity ACK completes landing")
 b.free()
func dict_command(value:Dictionary)->Dictionary:
 var result:=value.duplicate(true);result.type="report_position";return result
func failures_and_rejections()->void:
 var b=fresh();var step:=quiz(b)
 var baseline:=persisted(b)
 check(not b.quest_auto.source_open(b,step).get("ok",false),"No registered job/internal run, no execution")
 check(open_source(b,step).get("ok",false),"Open real quiz")
 var token:String=b.original_quests.pending.token
 var q=b.quest_auto
 var revision:int=q.identity.revision
 q.identity.revision+=1
 check(not next(b).get("ok",false),"Old revision cannot invoke a service")
 q.identity.revision=revision
 q.connection=18
 check(not next(b).get("ok",false),"Other connection cannot invoke this page")
 q.connection=17
 var old_step:String=q.identity.step_id;q.identity.step_id="other"
 check(not next(b).get("ok",false),"Wrong logical step cannot invoke this page")
 q.identity.step_id=old_step
 var before:Dictionary=b.session.snapshot();var location:Vector2i=b.automation.position_cell
 b.quest_auto.internal=true
 check(not b.call_quest_source(b.quest_auto.source_frame,step,{"token":token,"choice":"yes","text":""}).ok,"Backend rejects unreserved/replayed public-page choice")
 b.quest_auto.internal=false
 var dir:String=ProjectSettings.globalize_path(b.save_path+".tmp")
 DirAccess.make_dir_absolute(dir)
 var r:=next(b)
 check(not r.get("ok",false) and not r.get("source_commit",{}).get("committed",false) and not r.get("source_commit",{}).get("continued",true),"Real tmp write failure is not a commit or continuation")
 check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==baseline and b.automation.position_cell==location,"Save failure restores whole candidate and leaves disk/position unchanged")
 check(b.original_quests.pending.is_empty() and not next(b).get("ok",false),"Failed original token consumed, never replayed")
 DirAccess.remove_absolute(dir)
 b.quest_auto.stop(b)
 step=service("genout/quz_800_29_19")
 check(open_source(b,step).get("ok",false),"Fresh admitted attempt after rollback")
 b.quest_auto.detach(b,17)
 before=b.session.snapshot()
 check(not next(b).get("ok",false) and b.session.snapshot()==before,"Disconnect freezes current frame without a save")
 b.free()
func quiz_warp()->void:
 var b=fresh();var step:=quiz(b);persisted(b)
 var events:Array=[];b.event.connect(func(m):capture(events,m))
 check(open_source(b,step).get("ok",false),"Open first quiz")
 var paid:=next(b)
 check(paid.get("source_commit",{}).get("committed",false) and events.filter(func(m):return m.get("type")=="position").is_empty(),"Ticket save without Warp creates no receipt")
 var r:=next(b) # First-floor source has one question, public resolver only.
 check(r.get("ok",false) and r.get("source_commit",{}).get("committed",false),"Public source resolver executes real first quiz transaction")
 check(b.automation.position_map==800 and b.automation.position_cell==Vector2i(29,15) and 2754 in b.session._profile.original_items,"Original quiz owns reward and same-map Warp")
 check(events.filter(func(m):return m.get("type")=="position").size()==1,"Same-map service Warp publishes exactly once")
 b.free()
func warp_cancel(queued:bool)->void:
 var b=fresh();var step:=quiz(b);persisted(b)
 var events:Array=[];b.event.connect(func(m):capture(events,m))
 check(open_source(b,step).get("ok",false) and next(b).get("ok",false),"Paid quiz before final Warp cancellation")
 var state:Dictionary={}
 b.event.connect(func(m):
  if m.get("type")=="quest_result" and not state.get("fired",false):
   state.fired=true
   b.quest_auto.stop(b,"final result observer")
   if not queued:
    var manual:Dictionary=b.handle({"type":"quest_talk","npc_id":step.npc_id})
    check(manual.get("ok",false),"Manual page during saved Warp publication")
    state.pending=b.original_quests.pending.duplicate(true)
   b.session._profile.player.gold+=1
   check(b.save(),"Unrelated save during Warp publication")
 )
 if queued:b._depth+=1
 var r:=next(b)
 if queued:b._depth-=1;b._flush()
 var positions:Array=events.filter(func(m):return m.get("type")=="position")
 check(state.get("fired",false) and r.get("source_commit",{}).get("committed",false),"Cancel after actual final quiz save")
 check(positions.size()==1 and not Motion.tagged(positions[0]),"Depth0/queued result cancellation keeps actual plain position")
 check(b.automation.position_cell==Vector2i(29,15) and 2754 in b.session._profile.original_items and not b.quest_auto.running,"Committed reward/movement remain, runner remains stopped")
 if not queued:check(b.original_quests.pending==state.get("pending",{}),"Saved Warp cannot clear later manual page")
 b.free()
func other_save_fail(is_claim:bool)->void:
 var b=fresh();var step:Dictionary
 if is_claim:
  b.quest_arrival=ClaimArrival.new();b.automation.position_changed(810,Vector2i(29,18),true);step=claim()
 else:step=entry(b)
 var baseline:=persisted(b)
 check(open_source(b,step).get("ok",false),"Open REQUEST/gate before disk failure")
 var before:Dictionary=b.session.snapshot();var origin:Vector2i=b.automation.position_cell
 var events:Array=[];b.event.connect(func(m):capture(events,m))
 var tmp:String=ProjectSettings.globalize_path(b.save_path+".tmp")
 DirAccess.make_dir_absolute(tmp)
 var r:=next(b)
 check(not r.get("ok",false) and not r.get("source_commit",{}).get("committed",false),"REQUEST/gate tmp write failure rejects")
 check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==baseline and b.automation.position_cell==origin,"REQUEST/gate complete rollback")
 check(b.quest_auto.issued.is_empty() and events.filter(func(m):return m.get("type")=="position").is_empty(),"Failed transaction has no position/receipt")
 DirAccess.remove_absolute(tmp);b.free()
func pet_exchange()->void:
 var b=fresh();b.quest_arrival=ClaimArrival.new()
 b.automation.position_changed(810,Vector2i(28,18),true)
 Rules.set_flag(b.session._profile,"now",44,true)
 Equipment.add(b.session._profile,2753)
 var step:=claim(true)
 check(open_source(b,step).get("ok",false),"Exact original GetPet14 branch opens")
 check(next(b).get("ok",false),"Original ACCEPT goes to explicit reward confirmation")
 var before:Dictionary=b.session.snapshot()
 var r:=next(b)
 check(r.get("ok",false) and r.get("source_commit",{}).get("committed",false) and not r.source_commit.durable,"In-memory original transaction never claims disk durability")
 check(b.session._profile.pets.size()==before.pets.size()+1 and int(b.session._profile.pets[-1].level)==1 and Rules.flag(b.session._profile,"ended",44) and not 2753 in b.session._profile.original_items,"Original GetPet14 creates level1 pet once and END44")
 before=b.session.snapshot()
 check(not next(b).get("ok",false) and b.session.snapshot()==before,"Reward confirmation cannot replay")
 b.free()
func run()->void:
 for queued in [false,true]:
  tails(false,queued);tails(true,queued)
  gate(queued,false)
  warp_cancel(queued)
 gate(true,true)
 failures_and_rejections()
 other_save_fail(false);other_save_fail(true)
 quiz_warp()
 pet_exchange()
 var b=fresh()
 check(b.quest_auto.delivery_supports(2) and not b.handle({"type":"quest_auto_start","quest_id":2,"client":"hook-device","_quest_connection":17}).get("ok",false),"Registered job2 still refuses unqualified public entry")
 check(not Source.transaction(service("genout/quz_800_29_19"),{"event":-1,"texts":{},"actions":{"Warp":"810,29,18"}},"SERVICE"),"No arbitrary service destination")
 check(not Source.transaction(claim(true),Source.CLAIM_BRANCH,"reward"),"No generic branch/GetPet substitution")
 b.free()
 print("QUEST AUTO SOURCE EXECUTION HOOKS: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
