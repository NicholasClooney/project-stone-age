extends SceneTree
## Integrated authority acceptance; run only after the core enables B/C.
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var results:Dictionary={}
 for mode in ["A","B","C"]:results[mode]=complete(mode)
 if results.A.is_empty() or results.B.is_empty() or results.C.is_empty():quit(1);return
 check(results.A.cells==results.C.cells,"Integrated C commits exactly the full A route, including turns and portals")
 check(results.B.jumps==1 and results.A.jumps==0 and results.C.jumps==0,"Only B performs one audited public entrance jump")
 check(results.B.field_seconds<results.C.field_seconds and results.C.field_seconds<results.A.field_seconds,"Identical reviewed field leg has A slower than C slower than B")
 check(absf(results.A.field_seconds/results.C.field_seconds-2.0)<0.05,"C public travel cadence is approximately twice A over the same complete route")
 check(results.C.strides>0 and results.C.max_prefix<=3,"C actually publishes bounded committed prefixes")
 print("MODE SIMULATION SECONDS A=",results.A.field_seconds," B=",results.B.field_seconds," C=",results.C.field_seconds)
 print("QUEST AUTO MODES ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
func complete(mode:String)->Dictionary:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 b.session._profile.no_random_encounters=true
 b.automation.position_changed(1000,Vector2i(89,73))
 check(b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}}).ok,"Movement preference saves through its real command")
 if not b.quest_auto.snapshot(b).available_modes.has(mode):
  check(false,"Requested movement mode has not been integrated: "+mode)
  b.free();return {}
 var packets:Array=[]
 b.event.connect(func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_segment_id"):packets.append(event.duplicate(true))
 )
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"test","_quest_connection":17}).ok,"Real original shell task starts in "+mode)
 var result:Dictionary={"cells":[],"field_seconds":0.0,"jumps":0,"strides":0,"max_prefix":0}
 var processed:=0
 for index in range(20000):
  if not b.quest_auto.running:break
  var old_map:int=b.automation.position_map
  var old:Vector2i=b.automation.position_cell
  b.quest_auto.tick(b,0.05)
  if old_map==100:result.field_seconds+=0.05
  if old_map!=b.automation.position_map or old!=b.automation.position_cell:
   result.cells.append([b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y])
   if old_map==b.automation.position_map and absi(old.x-b.automation.position_cell.x)+absi(old.y-b.automation.position_cell.y)>1:
    result.jumps+=1
    check(mode=="B" and old_map==100 and not b.quest_helper.places.links(100).has(b.automation.position_cell),"B jump ends outside the audited portal")
  while processed<packets.size():
   var packet:Dictionary=packets[processed];processed+=1
   var prefix:Array=packet.quest_segment.cells
   check(not prefix.is_empty() and prefix[-1].cell==packet.cell,"Published segment contains only the already committed endpoint")
   if packet.quest_segment.kind=="public_stride":
    result.strides+=1
    result.max_prefix=maxi(result.max_prefix,prefix.size())
    for cursor in range(1,prefix.size()):
     var delta:=Vector2i(prefix[cursor].cell[0],prefix[cursor].cell[1])-Vector2i(prefix[cursor-1].cell[0],prefix[cursor-1].cell[1])
     check(absi(delta.x)+absi(delta.y)==1,"C prefix follows each original turn without cutting")
   if packet.get("quest_ack_required",false):
    var ack:Dictionary={"type":"report_position","map_id":packet.map_id,"cell":packet.cell.duplicate(),"client":"test","_quest_connection":17}
    for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]:ack[field]=packet[field]
    check(b.handle(ack).ok,"Current initiating client acknowledges the exact committed segment")
 check(not b.quest_auto.running and Rules.flag(b.session._profile,"ended",2) and b.session._profile.original_items==[2414],"Full task original reward is identical in mode "+mode+" / "+b.quest_auto.message)
 b.free()
 return result
