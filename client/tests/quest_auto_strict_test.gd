extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=Backend.new()
 b.session._profile.no_random_encounters=true
 b.session._profile.original_savepoint_bits=1
 b.automation.position_changed(1000,Vector2i(56,58))
 var reply:Dictionary=b.handle({"type":"quest_auto_start","quest_id":11,"strict_walk":true,"client":"test"})
 check(reply.ok and b.quest_auto.strict_walk,"strict opt-in accepted for legacy delivery")
 var selection:Dictionary=b.quest_auto.strict_select(b)
 check(selection.status=="step","real shell branch selected")
 var npc:Dictionary=b.original_quests.npc_by_id(str(selection.step.npc_id))
 # Public fixture starts nearby; every emitted product step must be adjacent.
 b.quest_auto.stop(b)
 var near:Dictionary=b.quest_helper.geometric_destination(b,npc,"near")
 b.automation.position_changed(int(near.map_id),Vector2i(int(near.cell[0]),int(near.cell[1])))
 b.handle({"type":"quest_auto_start","quest_id":11,"strict_walk":true,"client":"test"})
 for i in range(8):
  var old_map:int=b.automation.position_map
  var old_cell:Vector2i=b.automation.position_cell
  b.quest_auto.tick(b,0.21)
  if b.automation.position_map==old_map:
   var offset:Vector2i=b.automation.position_cell-old_cell
   check(absi(offset.x)+absi(offset.y)<=1,"strict runner never jumps within map")
  else:
   var portal:Dictionary=b.quest_helper.places.links(old_map).get(old_cell,{})
   check(not portal.is_empty() and int(portal.to_map)==b.automation.position_map,"strict map change follows original portal")
 check(Rules.flag(b.session._profile,"now",2),"ordinary request saved through original transaction")
 # The user-authorized ordinary encounter policy reuses the existing
 # attack/compact lifecycle, never a new guard/Boss runner.
 b.quest_auto.start_battle(b)
 check(b.quest_auto.running and b.quest_auto.phase=="battle" and b.quest_auto.owns_battle and b.automation.compact_active,"strict ordinary battle uses existing attack compact lifecycle")
 b.quest_auto.handoff(b,"test manual boundary")
 check(not b.quest_auto.running and b.quest_auto.phase=="manual" and not b.automation.running,"manual handoff stops owned automation")
 check(b.quest_auto.resume_state().is_empty(),"manual stop cannot resume itself on restart")
 b.quest_auto.running=true
 b.session._pending={"quest_guard":{}}
 b.quest_auto.start_battle(b)
 check(not b.quest_auto.running and not b.automation.running,"guard battle remains manual")
 b.session._pending={}
 var unsafe:Dictionary=selection.step.duplicate(true)
 unsafe.source.branch_data.actions.DelPet="1"
 check(not b.quest_auto.safe_step(unsafe),"pet delivery never auto-confirms")
 unsafe=selection.step.duplicate(true);unsafe.source.branch_data.actions.DelStone="1"
 check(not b.quest_auto.safe_step(unsafe),"spending never auto-confirms")
 unsafe=selection.step.duplicate(true);unsafe.source.type="FREEWARP"
 check(not b.quest_auto.safe_step(unsafe),"unreviewed freewarp rejected")
 b.quest_auto.running=true;b.quest_auto.strict_walk=true;b.quest_auto.quest_id=11
 var resume:Dictionary=b.quest_auto.resume_state()
 check(resume.version==2 and resume.strict_walk and not resume.has("arrival"),"intent stores mode without arrival proof")
 b.quest_auto.stop(b)
 # A restart inside a protected cave does not recreate authority proof.
 b.automation.position_changed(20101,Vector2i(14,15))
 b.quest_auto.load_resume(b,{"version":2,"quest_id":30,"strict_walk":true})
 b.quest_auto.tick(b,0.21)
 check(not b.quest_auto.running and b.quest_auto.phase=="manual","restart without cave proof hands off")
 b.free()
 test_cave_navigation()
 print("QUEST AUTO STRICT: %d failures"%failures)
 quit(1 if failures else 0)

func test_cave_navigation()->void:
 var b=Backend.new()
 var nav=preload("res://server/quest_auto_navigation.gd").new()
 var npc:Dictionary=b.original_quests.npc_by_id("jaruga/event/event07_2@20406:36:34")
 var portal:Dictionary=preload("res://server/legacy_cave_helper.gd").entrance(b.quest_helper,npc)
 check(not portal.is_empty(),"original Goya entrance exists")
 if portal.is_empty():b.free();return
 b.automation.position_changed(int(portal.from_map),Vector2i(int(portal.cell[0]),int(portal.cell[1])))
 var reached:=false
 for i in range(6000):
  var delta:Vector2i=b.automation.position_cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  if b.automation.position_map==int(npc.map_id) and maxi(absi(delta.x),absi(delta.y))<=2:reached=true;break
  var point:Dictionary=nav.next(b,npc)
  if point.is_empty() or not nav.validate(b,point):
   check(false,"original Goya route failed at %s/%s"%[b.automation.position_map,b.automation.position_cell]);break
  var changed:bool=int(point.map_id)!=b.automation.position_map
  b.automation.position_changed(int(point.map_id),Vector2i(int(point.cell[0]),int(point.cell[1])),changed,"walk")
  check(b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"each cave move keeps original authority proof")
  if changed:nav.clear()
 check(reached,"production planner crosses all six Goya floors using original portals")
 b.free()
