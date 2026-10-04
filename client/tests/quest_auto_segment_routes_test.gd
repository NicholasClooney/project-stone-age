extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Arrival=preload("res://server/quest_arrival_policy.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 for mode in ["B","C"]:
  for spec in [[1,4,1000,2418],[11,2,1000,2414],[30,1,3100,2427]]:
   var b=Backend.new()
   b.quest_catalog.enabled_events=[int(spec[1])]
   b.session._profile.no_random_encounters=true
   if spec[0]==1:b.session.gm_raise_level(-1,30)
   for item in b.session._profile.inventory:b.session._profile.inventory[item]=0
   var spawn:Array=b.quest_helper.places.info(spec[2]).spawn
   b.automation.position_changed(spec[2],Vector2i(spawn[0],spawn[1]))
   b.handle({"type":"set_automation_settings","settings":{"quest":{"mode":mode}}})
   check(b.handle({"type":"quest_auto_start","quest_id":spec[0],"client":"test","_quest_connection":17}).ok,"Real route starts "+mode+str(spec[0]))
   var fast:=[0];var protected_walk:=[0]
   b.event.connect(func(event):
    if event.get("type")!="position" or not event.has("quest_segment"):return
    var segment:Dictionary=event.quest_segment
    if segment.kind!="walk":
     fast[0]+=1
     check(int(event.map_id) in [100,200,1100,3100] and Arrival.scope(int(event.map_id)).is_empty(),"Fast authority always stays in exact public maps")
     check(not b.quest_arrival.has_arrival(b,10204,Vector2i(2,6)) and not b.quest_arrival.has_arrival(b,20101,Vector2i(29,69)),"Project movement never grants protected arrival")
    elif not Arrival.scope(int(event.map_id)).is_empty():protected_walk[0]+=1
   )
   for index in range(20000):
    if not b.quest_auto.running:break
    b.quest_auto.tick(b,0.21)
    if b.quest_auto.phase in ["landing","segment_landing"]:
     var receipt:Dictionary=b.quest_auto.issued[-1]
     var ack={"type":"report_position","map_id":receipt.map_id,"cell":receipt.cell.duplicate(),"client":"test","_quest_connection":17,"quest_position_seq":receipt.seq}
     for key in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]:ack[key]=receipt[key]
     b.handle(ack)
   check(not b.quest_auto.running and Rules.flag(b.session._profile,"ended",spec[1]) and b.session._profile.original_items==[spec[3]],"Full original transaction once "+mode+str(spec[0])+" "+b.quest_auto.message)
   check(fast[0]>0,"Actual fast corridor used "+mode+str(spec[0]))
   if spec[0]!=11:check(protected_walk[0]>0,"Protected original route remains walk "+mode+str(spec[0]))
   print("SEGMENT ROUTE ",mode," job=",spec[0]," fast=",fast[0]," protected=",protected_walk[0])
   b.free()
 print("QUEST AUTO SEGMENT ROUTES: %d failures"%failures)
 quit(1 if failures else 0)
