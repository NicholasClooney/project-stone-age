extends "res://tests/quest_delivery_remote_ui_test.gd"
## Regression for same-cell source step publication, NOT terminal/reward
## acceptance. Public authority and prior receipt are explicit initial-state
## fixtures; actual production selection/validation and WS consumers run.
const Equipment=preload("res://server/original_equipment.gd")
const OLD_STEP="fixture:previous-step"
const GATE_STEP="golden44:entry:genout/wpm_811_30_20"
class CountingIdentity extends "res://server/quest_auto_state.gd":
 var select_calls:=0
 func select_step(id:String)->void:
  select_calls+=1
  super.select_step(id)
class CountingRunner extends "res://server/quest_auto.gd":
 var open_calls:=0
 func source_open(b,proposal:Dictionary)->Dictionary:
  open_calls+=1
  return super.source_open(b,proposal)
class DiagnosticBackend extends "res://server/backend.gd":
 var watching:=false
 var manual:=false
 var ticks:=0
 var unexpected:=0
 var fields:=0
 var events:Array=[]
 func _process(delta:float)->void:
  if watching:
   if manual:ticks+=1
   else:unexpected+=1
  super._process(delta)
 func _cmd_field_step(command:Dictionary)->Dictionary:
  fields+=1
  return super._cmd_field_step(command)
var audit:Array=[]
func fixture_backend():
 var b=DiagnosticBackend.new();b.set_process(false)
 b.quest_auto=CountingRunner.new();b.quest_auto.identity=CountingIdentity.new()
 b.session._profile.player.level=35
 b.session._profile.no_random_encounters=true
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 Equipment.add(b.session._profile,2755)
 b.automation.position_changed(811,Vector2i(30,23),true)
 return b
func establish_prior(b,client:String,peer:int)->bool:
 # Explicit public authority fixture, not an original path or protected proof.
 b.automation.position_changed(811,Vector2i(30,22),false,"project")
 if not check(b.quest_auto.begin_source_run(b,client,peer).ok,"Production plan admits real public gate under true inventory/position"):return false
 b.quest_auto.identity.select_step(OLD_STEP)
 b.quest_auto.emit_position(b,{"map_id":811,"cell":[30,22]},{"map_id":811,"cell":[30,23]},false)
 b.publish()
 return true
func observe(label:String,message:Dictionary={})->void:
 var event:Dictionary={"type":message.get("type","")}
 if message.get("type")=="profile":event.auto=message.derived.quest_auto.duplicate(true)
 elif message.get("type")=="auto_status":event.position=message.status.position.duplicate(true)
 elif message.get("type")=="position":event=message.duplicate(true)
 var record:Dictionary={"label":label,"t":Time.get_ticks_msec(),"event":event,"authority":str(backend_node.automation.position_cell),"live_step":backend_node.quest_auto.identity.step_id,"live_revision":backend_node.quest_auto.identity.revision,"live_phase":backend_node.quest_auto.phase}
 if is_instance_valid(world):
  record.scene=str(world.cell);record.follow=world._follow.duplicate();record.followed=world._followed.duplicate()
  record.receipt=world.get_meta("quest_position_receipt",{}).duplicate(true)
  record.client_position=world.state.automation.get("position",{}).duplicate(true)
  record.client_auto=world.state.derived.get("quest_auto",{}).duplicate(true)
 audit.append(record)
 print("STEP TRANSITION ",JSON.stringify(record))
func run_case(fresh_status:bool)->bool:
 backend_node=fixture_backend();backend_node.save_path="user://step-transition-regression-%s.json"%str(fresh_status)
 if not check(backend_node.save(),"Fixture persisted before remote scene"):return false
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,"Diagnostic real WS port0"):return false
 if not await create_world():return false
 backend_node.set_process(false);backend_node.watching=true
 if not await ready(func():return int(world.data.map_id)==811 and world.cell==Vector2i(30,23) and not world.moving,"Initial public scene consumes actual authority"):return false
 if not check(await Wait.settle(self,world),"Initial public reports fully settled"):return false
 if not establish_prior(backend_node,world._client_id,server_node.clients()[0].get_instance_id()):return false
 if not await ready(func():return world.cell==Vector2i(30,22) and not world.moving and not world.get_meta("quest_position_receipt",{}).is_empty(),"Artificial prior-step receipt actually consumed by production scene"):return false
 if not check(await Wait.settle(self,world),"Prior step motion settled before single-variable control"):return false
 if not check(world.state.automation.position.cell==[30,23] and backend_node.quest_auto.identity.step_id==OLD_STEP,"Actual old auto_status and artificial prior identity preconditions"):return false
 if fresh_status:
  backend_node.emit_event({"type":"auto_status","status":backend_node.automation.status()})
  if not check(await Wait.settle(self,world) and world.state.automation.position.cell==[30,22],"Fresh control changes only real status publication"):return false
 var before:Dictionary=backend_node.session.snapshot()
 var disk:String=FileAccess.get_file_as_string(backend_node.save_path)
 var save_serial:int=backend_node.quest_save_serial
 backend_node.event.connect(func(m):backend_node.events.append(m.duplicate(true));observe("backend",m))
 world.link.message.connect(func(m):
  if m.get("type") in ["profile","position","auto_status"]:observe("after-production-consumer",m)
 )
 observe("before-switch fresh="+str(fresh_status))
 backend_node.manual=true;backend_node._process(0.21);backend_node.manual=false
 if not check(await Wait.settle(self,world),"One actual production advance_source tick drained over WS"):return false
 var status_seen:=false
 for event in backend_node.events:
  if event.get("type")=="auto_status" and event.status.position.cell==[30,22]:status_seen=true
  if event.get("type")=="profile" and event.derived.quest_auto.step_id==GATE_STEP:
   if not check(status_seen,"Current authority status precedes any new-step receipt-clearing profile"):return false
 var expected:=Vector2i(30,22)
 if not await ready(func():return world.cell==expected and not world.moving,"Both stale and fresh initial status retain actual authority without extra tick"):return false
 observe("after-switch fresh="+str(fresh_status))
 if not check(backend_node.quest_auto.identity.step_id==GATE_STEP and backend_node.quest_auto.phase=="source_dialogue" and not backend_node.quest_auto.source_frame.page.is_empty(),"Production select/validate/clear/select_step/source_open created actual new gate confirm"):return false
 if not check(backend_node.events.filter(func(m):return m.get("type")=="position").is_empty() and backend_node.fields==0,"Same-location transition emits no movement and no field step"):return false
 if not check(world.get_meta("quest_position_receipt",{}).is_empty() and backend_node.automation.position_cell==Vector2i(30,22),"Old capability cleared while true authority stays unchanged"):return false
 if not check(backend_node.ticks==1 and backend_node.unexpected==0 and backend_node.session.snapshot()==before and FileAccess.get_file_as_string(backend_node.save_path)==disk and backend_node.quest_save_serial==save_serial,"No uncontrolled tick, payment, save, reward or profile mutation"):return false
 print("STEP TRANSITION CASE ",JSON.stringify({"fresh_status":fresh_status,"scene":str(world.cell),"authority":str(backend_node.automation.position_cell),"kept_authority":world.cell==Vector2i(30,22),"ticks":backend_node.ticks,"unexpected":backend_node.unexpected,"new_step":backend_node.quest_auto.identity.step_id}))
 backend_node.quest_auto.stop(backend_node,"diagnostic case complete")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return not is_instance_valid(world),"Diagnostic scene disposed"):return false
 server_node.stop();server_node.queue_free();backend_node.queue_free()
 await process_frame
 return true
func cancellation()->bool:
 var b=fixture_backend()
 if not establish_prior(b,"cancel",71):return false
 var before:Dictionary=b.session.snapshot()
 var fired:Array=[]
 b.event.connect(func(m):
  if fired.is_empty() and m.get("type")=="profile" and m.derived.quest_auto.step_id==GATE_STEP and m.derived.quest_auto.phase=="source_dialogue":
   fired.append(b.original_quests.pending.token)
   b.quest_auto.stop(b,"current real publication hook cancels")
 )
 b.quest_auto.internal=true;b.quest_auto.advance_source(b);b.quest_auto.internal=false
 if not check(fired.size()==1 and not b.quest_auto.running and b.quest_auto.source_frame==null and b.original_quests.pending.is_empty(),"Current real source_dialogue publish hook cancels new frame/page"):return false
 var replay:Dictionary=b.handle({"type":"quest_choose","token":fired[0],"choice":"yes"})
 b._process(0.21)
 if not check(not replay.ok and b.session.snapshot()==before and b.fields==0 and b.quest_auto.issued.is_empty() and not b.quest_auto.running,"Cancelled page replay/old tick neither pays, moves nor revives"):return false
 b.free();return true
func pre_status_reentry()->bool:
 for mode in ["cancel","detach","identity","connection"]:
  var b=fixture_backend()
  if not establish_prior(b,"reentry",71):return false
  b.quest_auto.identity.select_calls=0;b.quest_auto.open_calls=0
  var before:Dictionary=b.session.snapshot()
  var original_step:Dictionary=b.quest_auto.step.duplicate(true)
  var fired:Array=[]
  var after_observer:Dictionary={}
  b.event.connect(func(m):
   if not fired.is_empty() or m.get("type")!="auto_status":return
   fired.append(m.status.position.duplicate(true))
   if mode=="cancel":b.quest_auto.stop(b,"pre-status observer cancellation")
   elif mode=="detach":b.quest_auto.detach(b,71)
   elif mode=="identity":b.quest_auto.identity.select_step("fixture:observer-next-step")
   else:b.quest_auto.connection=72
   after_observer.identity=b.quest_auto.identity.checkpoint()
   after_observer.select_calls=b.quest_auto.identity.select_calls
  )
  b.quest_auto.internal=true;b.quest_auto.advance_source(b);b.quest_auto.internal=false
  if not check(fired.size()==1 and fired[0].cell==[30,22],"New pre-status publication carries current authority: "+mode):return false
  if not check(b.quest_auto.open_calls==0 and b.quest_auto.identity.select_calls==after_observer.select_calls and b.quest_auto.identity.checkpoint()==after_observer.identity and b.quest_auto.step==original_step,"After observer change outer select_step/open never execute: "+mode):return false
  if mode=="cancel":
   if not check(b.quest_auto.identity.select_calls==0,"Pre-status cancellation has exactly zero select_step calls"):return false
   b._process(0.21)
   if not check(not b.quest_auto.running and b.quest_auto.open_calls==0,"Cancelled pre-status cannot resume on old tick"):return false
  if not check(b.session.snapshot()==before and b.automation.position_cell==Vector2i(30,22) and b.fields==0 and b.original_quests.pending.is_empty() and b.quest_auto.source_frame==null,"Reentry has no payment/position/page side effect: "+mode):return false
  print("STEP TRANSITION REENTRY ",mode," outer_select_calls=0 open_calls=",b.quest_auto.open_calls)
  b.free()
 return true
func run()->void:
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
 if not await run_case(false):return
 if not await run_case(true):return
 if not cancellation():return
 if not pre_status_reentry():return
 var file=FileAccess.open("user://step-transition-regression-events.json",FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(audit,"  "));file.close()
 print("QUEST AUTO SOURCE STEP TRANSITION: PASS; stale/fresh keep authority; pre-status select/open zero; existing profile cancellation; NO terminal/reward claim")
 quit(0)
