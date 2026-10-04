extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=Backend.new()
 b.session.snapshot()
 b.quest_catalog.enabled_events=[2]
 b.session._profile.no_random_encounters=true
 for bit in [0,1,2,3]:
  b.quest_auto.stop(b)
  b.session._profile.original_savepoint_bits=1<<bit
  b.session._profile.original_items=[];b.session._profile.original_instances=[]
  Rules.set_flag(b.session._profile,"ended",2,true)
  var clean:Dictionary=b.quest_auto.strict_select(b,11,true).get("step",{})
  check(not clean.is_empty() and b.quest_auto.safe_step(clean,11,true),"Only reviewed directional shell CLEAN admitted")
  for mutated in ["actions","condition","npc","extra"]:
   var unsafe:Dictionary=clean.duplicate(true)
   if mutated=="actions":unsafe.source.branch_data.actions={"CleanFlg":"19"}
   elif mutated=="condition":unsafe.source.branch_data.condition="LV>0"
   elif mutated=="npc":unsafe.npc_id="other"
   else:unsafe.source.branch_data.project_pet_selection=true
   check(not b.quest_auto.safe_step(unsafe,11,true),"Unknown CLEAN rejected: "+mutated)
  var npc:Dictionary=b.original_quests.npc_by_id(clean.npc_id)
  var near:Dictionary=b.quest_helper.geometric_destination(b,npc,"near")
  b.automation.position_changed(near.map_id,Vector2i(near.cell[0],near.cell[1]))
  var before:Dictionary=b.session.snapshot()
  var cell:Vector2i=b.automation.position_cell
  check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"test"}).ok and b.session.snapshot()==before and b.automation.position_cell==cell,"Start admits CLEAN without side effects")
  for i in range(8):
   b.quest_auto.tick(b,0.21)
   if not Rules.flag(b.session._profile,"ended",2):break
  check(not Rules.flag(b.session._profile,"ended",2),"Original transaction clears only event2")
  for i in range(3):b.quest_auto.tick(b,0.21)
  check(not b.quest_auto.clean_authorized,"Successful CLEAN permission is consumed, not a repeat loop")
  b.quest_auto.stop(b)
 # Save failure at original CLEAN commit leaves full profile intact.
 Rules.set_flag(b.session._profile,"ended",2,true)
 b.session._profile.original_savepoint_bits=1
 var clean:Dictionary=b.quest_auto.strict_select(b,11,true).step
 var npc:Dictionary=b.original_quests.npc_by_id(clean.npc_id)
 var near:Dictionary=b.quest_helper.geometric_destination(b,npc,"near")
 b.automation.position_changed(near.map_id,Vector2i(near.cell[0],near.cell[1]))
 b.save_path="user://missing-auto-clean-parent/save.json"
 var before:Dictionary=b.session.snapshot()
 check(b.handle({"type":"quest_auto_start","quest_id":11,"client":"test"}).ok,"Failed-save CLEAN fixture starts")
 for i in range(8):
  if not b.quest_auto.running:break
  b.quest_auto.tick(b,0.21)
 check(not b.quest_auto.running and b.session.snapshot()==before,"CLEAN savefail preserves profile and stops")
 b.save_path=""
 for invalid in ["completed","savepoint"]:
  b.quest_auto.stop(b)
  b.session._profile.original_items=[];b.session._profile.original_instances=[]
  Rules.set_flag(b.session._profile,"ended",2,invalid=="completed")
  Rules.set_flag(b.session._profile,"now",2,false)
  b.session._profile.original_savepoint_bits=1 if invalid=="completed" else 0
  if invalid=="completed":b.session.OriginalEquipment.add(b.session._profile,2414)
  before=b.session.snapshot()
  var identity:Dictionary=b.quest_auto.identity.checkpoint()
  var reply:Dictionary=b.handle({"type":"quest_auto_start","quest_id":11,"client":"test"})
  check(not reply.ok and not b.quest_auto.running and b.session.snapshot()==before and b.quest_auto.identity.checkpoint()==identity,"Immediate side-effect-free rejection: "+invalid)
  if invalid=="completed":check(b.handle({"type":"quest_discard","item_id":2414}).ok,"Rejected start does not lock explicit discard")
 b.free()
 print("QUEST AUTO ADMISSION: %d failures"%failures)
 quit(1 if failures else 0)
