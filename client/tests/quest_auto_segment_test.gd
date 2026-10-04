extends SceneTree
## Cursor/protocol unit matrix only. This does not certify any public route.
const Segment=preload("res://server/quest_auto_segment.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const State=preload("res://server/quest_auto_state.gd")
const Backend=preload("res://server/backend.gd")
class Validator extends RefCounted:
 var seen:Dictionary={}
 var allowed:=true
 var callback:Callable
 func validate_segment(_b,_npc:Dictionary,value:Dictionary)->bool:
  seen=value.duplicate(true)
  value.navigation_key="mutated-copy"
  if callback.is_valid():callback.call()
  return allowed
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func proposal()->Dictionary:
 return {"kind":"public_stride","audit_id":"unit-fixture-only","from_map":100,"from_cell":[10,10],"navigation_key":"frozen-local-key","private_metadata":{"version":7},"points":[{"map_id":100,"cell":[11,10]},{"map_id":100,"cell":[11,11]},{"map_id":100,"cell":[12,11]}]}
func run()->void:
 var identity=State.new();identity.begin();identity.select_step("unit:step")
 var origin={"map_id":100,"cell":[10,10]}
 var cursor=Segment.new()
 var nav=Validator.new()
 var source=proposal()
 check(cursor.begin(source,"C",origin,identity,1),"Well-shaped local cursor can stage without moving authority")
 source.private_metadata.version=8
 check(cursor.proposal.private_metadata.version==7 and cursor.interval()==0.1,"Deep-copy proposal and central 2x timing")
 for index in range(3):
  var next=cursor.next_point(null,{},nav,identity)
  check(nav.seen.navigation_key=="frozen-local-key" and nav.seen.private_metadata.version==7 and nav.seen.points==proposal().points and nav.seen.remaining==proposal().points.slice(index),"Every validation retains full metadata and complete ordered suffix")
  check(cursor.packet(identity,index+1,true).is_empty() if index==0 else cursor.packet(identity,index+1,false).quest_segment.cells.size()==index,"Uncommitted future cells never broadcast")
  check(cursor.commit(next,identity),"Commit exactly current next point")
  var packet=cursor.packet(identity,index+1,index==2)
  check(packet.quest_segment_id==identity.run_id+":1" and packet.quest_segment_index==index+1 and packet.quest_segment_done==(index==2),"Stable segment identity and monotone prefix")
  check(not packet.quest_segment.has("navigation_key") and not packet.quest_segment.has("private_metadata") and not packet.quest_segment.has("points"),"Local metadata cannot leak into client packet")
 check(cursor.complete() and not cursor.commit(proposal().points[-1],identity),"Repeated committed point cannot advance cursor")
 for case in ["unknown","wrong_mode","too_many","fraction","bool","nan","non_adjacent","gate","portal","map","origin","key","audit","injected_remaining"]:
  var value=proposal();var mode="C"
  match case:
   "unknown":value.kind="anything"
   "wrong_mode":mode="B"
   "too_many":value.points.append({"map_id":100,"cell":[13,11]})
   "fraction":value.points[0].cell=[11.25,10]
   "bool":value.points[0].cell=[true,10]
   "nan":value.points[0].cell=[NAN,10]
   "non_adjacent":value.points[0].cell=[14,10]
   "gate":value.points[0].gate={"source_id":"x"}
   "portal":value.points[0].portal={}
   "map":value.points[0].map_id=200
   "origin":value.from_cell=[9,10]
   "key":value.erase("navigation_key")
   "audit":value.erase("audit_id")
   "injected_remaining":value.remaining=[value.points[-1]]
  check(not cursor.begin(value,mode,origin,identity,1) and cursor.proposal.is_empty(),"Reject invalid segment shape: "+case)
 cursor.begin(proposal(),"C",origin,identity,2)
 nav.allowed=false
 check(cursor.next_point(null,{},nav,identity).is_empty() and cursor.proposal.is_empty(),"Geometry rejection discards entire tail")
 nav.allowed=true
 cursor.begin(proposal(),"C",origin,identity,2)
 nav.callback=func():identity.invalidate()
 check(cursor.next_point(null,{},nav,identity).is_empty(),"Cancellation during validation cannot authorize a point")
 nav.callback=Callable()
 cursor.begin(proposal(),"C",origin,identity,2)
 check(not cursor.commit(proposal().points[1],identity) and cursor.committed.is_empty(),"Out of order point cannot become committed prefix")
 cursor.clear()
 check(cursor.packet(identity,2,true).is_empty(),"Cleared cursor has no replay packet")
 ack_matrix(identity)
 var b=Backend.new()
 check(b.quest_auto.snapshot(b).available_modes==["A"] and b.quest_auto.snapshot(b).effective_mode=="A","Cursor preparation does not enable B/C")
 b.quest_auto.segment.begin(proposal(),"C",origin,identity,4)
 b.quest_auto.clear_motion()
 check(b.quest_auto.segment.proposal.is_empty(),"Cancel/detach/battle clear_motion also drops pending tail")
 b.free()
 print("QUEST AUTO SEGMENT: %d failures"%failures)
 quit(1 if failures else 0)
func ack_matrix(identity)->void:
 var cursor=Segment.new()
 cursor.begin(proposal(),"C",{"map_id":100,"cell":[10,10]},identity,8)
 cursor.commit(proposal().points[0],identity)
 var receipt=cursor.packet(identity,9,true);receipt.seq=9
 var ack={"map_id":100,"cell":[11,10],"quest_position_seq":9}
 for field in Motion.IDENTITY_FIELDS:ack[field]=receipt[field]
 check(Motion.matches(ack,receipt,identity),"Full C identity matches a committed receipt")
 for field in Motion.IDENTITY_FIELDS:
  var missing=ack.duplicate();missing.erase(field)
  check(not Motion.matches(missing,receipt,identity),"C ACK requires field "+field)
 var legacy=ack.duplicate()
 for field in Motion.IDENTITY_FIELDS:legacy.erase(field)
 check(not Motion.matches(legacy,receipt,identity),"C never accepts seq-only fallback")
 for field in ["quest_run_id","quest_step_id","quest_segment_id","quest_revision","quest_position_seq","map_id","cell"]:
  var wrong=ack.duplicate()
  wrong[field]=[12,10] if field=="cell" else (123 if field in ["quest_revision","quest_position_seq","map_id"] else "old")
  check(not Motion.matches(wrong,receipt,identity),"C rejects mismatched "+field)
 receipt.quest_segment.mode="B"
 check(not Motion.matches(legacy,receipt,identity) and Motion.matches(ack,receipt,identity),"B likewise requires full identity")
 receipt.quest_segment.mode="A"
 check(Motion.matches(legacy,receipt,identity),"Existing A receipt compatibility remains scoped")
