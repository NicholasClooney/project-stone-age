extends SceneTree
const Backend=preload("res://server/backend.gd")
const Gate=preload("res://server/quest_auto_permit_gate.gd")
class CancelBackend extends "res://server/backend.gd":
 var cancel_after_save:=false
 func save()->bool:
  var result:bool=super.save()
  if result and cancel_after_save:
   cancel_after_save=false
   # Model a synchronous observer in a future save publication hook.
   publish()
  return result
var failures:=0
var events:Array=[]
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func prepare(b,source:String)->void:
 b.quest_auto.stop(b)
 b.quest_auto.running=true;b.quest_auto.strict_walk=true;b.quest_auto.quest_id=30
 b.quest_auto.phase="travel";b.quest_auto.client="test";b.quest_auto.connection=17
 b.quest_auto.identity.begin();b.quest_auto.identity.select_step("herb:doctor")
 b.quest_auto.internal=true
 b.session._profile.travel_pass=true
 var point:Array=Gate.GATES[source].anchor
 b.automation.position_changed(10202,Vector2i(point[0],point[1]))
 b.session.set_location(10202,point[0],point[1])
 b.original_quests.pending={};b.session._pending={}
 b.battle_open=false
func commit(b,source:String)->Dictionary:
 return b.commit_undersea_permit_gate(source,b.quest_auto.identity.run_id,b.quest_auto.identity.step_id,b.quest_auto.identity.revision)
func close_files(path:String)->void:
 for suffix in ["",".bak",".tmp"]:
  if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func run()->void:
 var b=Backend.new()
 b.event.connect(func(event):events.append(event.duplicate(true)))
 for source in Gate.GATES:
  prepare(b,source)
  b.save_path="user://quest-permit-gate.json"
  check(b.save(),"Save source-side fixture")
  var before:Dictionary=b.session.snapshot()
  var revision:int=b.quest_auto.identity.revision
  var reply:Dictionary=b.quest_auto.advance_permit_gate(b,{"gate":{"source_id":source}})
  var destination:Array=Gate.GATES[source].target
  check(reply.ok and reply.committed and reply.continued and b.quest_auto.phase=="landing","Fixed source Warp waits for same-map landing: "+source+" "+str(reply))
  check(b.automation.position_cell==Vector2i(destination[0],destination[1]) and b.session.snapshot().location=={"map_id":10202,"x":destination[0],"y":destination[1]},"Authority and saved location agree")
  var persisted=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
  check(int(persisted.location.map_id)==10202 and int(persisted.location.x)==destination[0] and int(persisted.location.y)==destination[1],"Destination persisted before position event")
  check(b.session.has_travel_pass() and b.session.snapshot().player.gold==before.player.gold and b.session.snapshot().original_items==before.original_items,"Permit and gold are not consumed")
  check(b.quest_auto.identity.revision>revision and b.quest_auto.motion.get("awaiting_ack",false),"Gate rotates capability and issues landing receipt")
  if b.quest_auto.issued.is_empty():b.free();quit(1);return
  var receipt:Dictionary=b.quest_auto.issued[-1]
  var ack={"type":"report_position","map_id":10202,"cell":destination.duplicate(),"client":"test","_quest_connection":17,"quest_position_seq":receipt.seq}
  for field in ["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]:ack[field]=receipt[field]
  var old:Dictionary=ack.duplicate();old.quest_revision=revision
  b.handle(old)
  check(b.quest_auto.phase=="landing","Pre-gate revision cannot acknowledge destination")
  check(b.handle(ack).ok and b.quest_auto.phase=="travel","Current owner receipt releases same-map landing")
  check(not commit(b,source).ok,"Source gate cannot replay from opposite side")
 close_files(b.save_path);b.save_path=""
 var source:String="genout/wpm_10202_22_28"
 for case in ["internal","run","step","revision","empty_step","permit","map","distance","npc_cell","battle","pending","dialogue","party","source","duplicate","destination","target_npc","source_npc","map_missing"]:
  prepare(b,source)
  var residents:Array=b.quest_helper.places.residents.duplicate(true)
  var map:Dictionary=b.quest_helper.places.maps["10202"].duplicate(true)
  var run_id:String=b.quest_auto.identity.run_id
  var step_id:String=b.quest_auto.identity.step_id
  var revision:int=b.quest_auto.identity.revision
  match case:
   "internal":b.quest_auto.internal=false
   "run":run_id="old"
   "step":step_id="old"
   "revision":revision-=1
   "empty_step":step_id="";b.quest_auto.identity.step_id=""
   "permit":b.session._profile.travel_pass=false
   "map":b.automation.position_changed(1000,Vector2i(21,28))
   "distance":b.automation.position_changed(10202,Vector2i(10,7))
   "npc_cell":b.automation.position_changed(10202,Vector2i(22,28))
   "battle":b.battle_open=true
   "pending":b.session._pending={"battle_id":"x"}
   "dialogue":b.original_quests.pending={"token":"x"}
   "party":b.quest_visit_guard=func():return "party"
   "source":source="genout/unreviewed"
   "duplicate":
    for resident in residents:
     if resident.get("dialogue_source","")=="gmsv/data/npc/"+source:b.quest_helper.places.residents.append(resident.duplicate(true));break
   "destination":
    for resident in b.quest_helper.places.residents:
     if resident.get("dialogue_source","")=="gmsv/data/npc/"+source:resident.destination=[1,1]
   "target_npc":b.quest_helper.places.residents.append({"map_id":10202,"cell":[21,33]})
   "source_npc":b.quest_helper.places.residents.append({"map_id":10202,"cell":[21,28]})
   "map_missing":b.quest_helper.places.maps["10202"].path="world/no-permit-gate.map"
  var before:Dictionary=b.session.snapshot()
  var position:Vector2i=b.automation.position_cell
  var map_id:int=b.automation.position_map
  events.clear()
  var reply:Dictionary=b.commit_undersea_permit_gate(source,run_id,step_id,revision)
  check(not reply.ok and before==b.session.snapshot() and position==b.automation.position_cell and map_id==b.automation.position_map and events.is_empty(),"Reject without mutation: "+case)
  b.quest_helper.places.residents=residents
  b.quest_helper.places.maps["10202"]=map
  b.quest_visit_guard=Callable();source="genout/wpm_10202_22_28"
 prepare(b,source)
 var npcs:Array=b.quest_catalog.npcs.duplicate(true)
 b.quest_catalog.npcs.append({"id":"gate-dynamic-fixture","map_id":10202,"cell":[10,7],"events":[2],"branches":[{"event":2,"events":[2],"enabled":true}]})
 b.original_quests.npc_state.records["gate-dynamic-fixture"]={"map_id":10202,"cell":[21,33]}
 check(not commit(b,source).ok,"Current NPC override blocks target despite clear original cell")
 b.original_quests.npc_state.records["gate-dynamic-fixture"]={"map_id":10202,"cell":[10,7]}
 check(commit(b,source).ok,"Moving NPC away reopens the original gate target")
 b.original_quests.npc_state.records.erase("gate-dynamic-fixture")
 b.quest_catalog.npcs=npcs
 for point in [{"gate":{"source_id":source},"map_id":1000},{"gate":{"source_id":source},"cell":[1,1]},{"gate":{"source_id":source,"target":[1,1]}},{"gate":{"source_id":source},"portal":{}}]:
  prepare(b,source)
  var position:Vector2i=b.automation.position_cell
  check(not b.quest_auto.advance_permit_gate(b,point).ok and b.automation.position_cell==position,"Navigation target forgery rejected")
 prepare(b,source)
 b.save_path="user://missing-permit-gate-parent/save.json"
 var before:Dictionary=b.session.snapshot()
 var origin:Vector2i=b.automation.position_cell
 # An opaque pre-existing proof must remain byte-for-byte unchanged on fail.
 b.quest_arrival._marks={"test:previous":7};var epoch:int=b.quest_arrival._epoch
 events.clear()
 var failed:Dictionary=b.quest_auto.advance_permit_gate(b,{"gate":{"source_id":source}})
 check(not failed.ok and b.session.snapshot()==before and b.automation.position_cell==origin,"Savefail restores full profile and authority")
 check(b.quest_arrival._marks=={"test:previous":7} and b.quest_arrival._epoch==epoch and not events.any(func(event):return event.type=="position"),"Savefail neither clears proof nor publishes position")
 b.save_path="";prepare(b,source)
 b.quest_arrival._marks={"test:previous":7};b.quest_arrival._approach={"test":true}
 check(commit(b,source).ok and b.quest_arrival._marks.is_empty() and b.quest_arrival._approach.is_empty() and b.quest_arrival._scope.is_empty(),"Saved source script Warp clears old proof without granting arrival")
 check(not b.quest_arrival.has_arrival(b,10204,Vector2i(2,6)),"No adult proof from permit Warp")
 check(not b.handle({"type":"commit_undersea_permit_gate","source_id":source}).ok,"Internal gate transaction is not an RPC")
 b.free()
 cancellation_order()
 print("QUEST AUTO PERMIT GATE: %d failures"%failures)
 quit(1 if failures else 0)
func cancellation_order()->void:
 var b=CancelBackend.new()
 var source:="genout/wpm_10202_22_28"
 prepare(b,source)
 b.save_path="user://quest-permit-cancel.json"
 b.save()
 var emitted:Array=[]
 var seen:=[false]
 b.event.connect(func(event):
  emitted.append(event.duplicate(true))
  if event.type=="profile" and not seen[0]:
   seen[0]=true
   b.quest_auto.stop(b,"cancel after gate save")
 )
 b.cancel_after_save=true
 var result:Dictionary=b.quest_auto.advance_permit_gate(b,{"gate":{"source_id":source}})
 check(result.ok and result.committed and not result.continued and not b.quest_auto.running,"Cancellation after save does not deny committed Warp or revive run")
 var persisted=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
 check(int(persisted.location.map_id)==10202 and int(persisted.location.x)==21 and int(persisted.location.y)==33 and b.automation.position_cell==Vector2i(21,33),"Saved and authority destination remain identical after cancellation")
 check(b.quest_auto.issued.is_empty() and not emitted.any(func(event):return event.has("quest_position_seq")),"Cancelled commit publishes correction without issuing old run capability")
 check(emitted.any(func(event):return event.type=="position" and event.cell==[21,33]),"Client still receives actual committed position")
 var position:Vector2i=b.automation.position_cell
 b.quest_auto.tick(b,1.0)
 check(b.automation.position_cell==position and not b.battle_open,"No subsequent movement or encounter after cancellation")
 close_files(b.save_path);b.free()
