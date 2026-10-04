extends SceneTree
## Read-only geometry contracts. Authority timing/encounters/ACKs are core tests.
const Backend=preload("res://server/backend.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 b.automation.position_changed(100,Vector2i(637,494))
 var npc:Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_1")
 var plain=Navigation.new()
 var a:Array=plain.plan(b,npc)
 check(a.size()>300 and a[-1].has("portal"),"Baseline covers the full original public field leg")
 var nav=Navigation.new()
 for lane in nav.public_routes.LANES:
  var corridor:Array=nav.public_routes.corridor(nav,b,lane)
  check(corridor.size()>2,"Each audited source tuple has a real original corridor: "+str(lane.id))
  for point in corridor.slice(1):
   check(nav.public_routes.public_cell(nav,b,int(lane.map),Vector2i(point.cell[0],point.cell[1])),"Every audited corridor cell excludes portals and occupants")
 var before:Dictionary=b.session.snapshot()
 var first:Dictionary=nav.next_segment(b,npc,"B",3)
 check(first.get("kind")=="public_jump" and nav.validate_segment(b,npc,first),"B proposes only the reviewed next entrance outside")
 if first.get("kind")=="public_jump":
  check(first.points[0]==a[-3],"B stops one original cell before the door")
  var forged:Dictionary=first.duplicate(true)
  forged.points[0].cell=[78,614]
  check(not nav.validate_segment(b,npc,forged),"B cannot land on the portal itself")
  forged=first.duplicate(true);forged.points[0].cell=[108,225]
  check(not nav.validate_segment(b,npc,forged),"B cannot replace its audited endpoint")
 check(b.session.snapshot()==before and b.automation.position_cell==Vector2i(637,494),"Segment proposal and validation never write authority")
 nav.clear()
 var walked:Array=[]
 var strides:=0
 for index in range(2000):
  if b.automation.position_map!=100:break
  var segment:Dictionary=nav.next_segment(b,npc,"C",99)
  if segment.is_empty():check(false,"C cannot lose the known A route");break
  check(nav.validate_segment(b,npc,segment),"New C segment validates at current authority")
  if segment.kind=="public_stride":
   strides+=1
   check(segment.points.size()<=3,"C obeys the central maximum even with a larger local request")
  for cursor in range(segment.points.size()):
   segment.remaining=segment.points.slice(cursor).duplicate(true)
   check(nav.validate_segment(b,npc,segment),"Remaining suffix validates after each committed logical cell")
   var point:Dictionary=segment.points[cursor]
   walked.append(point.duplicate(true))
   b.automation.position_changed(int(point.map_id),Vector2i(point.cell[0],point.cell[1]),int(point.map_id)!=b.automation.position_map,"project" if segment.kind=="public_stride" else "walk")
 check(strides>10 and walked==a,"C emits exactly the complete A cell/portal sequence")
 b.automation.position_changed(100,Vector2i(637,494));nav.clear()
 var pending:Dictionary=nav.next_segment(b,npc,"C",3)
 b.quest_catalog.npc_overrides[npc.id]={"map_id":2000,"cell":[57,91]}
 check(not nav.validate_segment(b,npc,pending),"Dynamic NPC change invalidates a previously proposed segment")
 b.quest_catalog.npc_overrides.clear()
 b.session._profile.player.level+=1
 check(not nav.validate_segment(b,npc,pending),"Changed passage eligibility invalidates an existing proposal")
 b.session._profile.player.level-=1
 var door:Dictionary=b.quest_helper.places.links(100)[Vector2i(78,614)]
 door.disabled=true
 check(not nav.validate_segment(b,npc,pending),"Closed original portal invalidates its public corridor")
 door.erase("disabled")
 for map_id in [10201,10202,10204,20101,20105,300,32001]:
  for cell in [Vector2i(105,228),Vector2i(108,225),Vector2i(102,228)]:
   check(not nav.public_routes.public_cell(nav,b,map_id,cell),"C never classifies caves/doors/300 approach as a public lane")
 b.automation.position_changed(1000,Vector2i(89,73));nav.clear()
 check(nav.next_segment(b,npc,"B",3).get("kind")=="walk","An unaudited public source falls back to A")
 b.automation.position_changed(-1,Vector2i.ZERO);nav.clear()
 check(nav.next_segment(b,npc,"B",3).is_empty(),"B never hides an unknown A route")
 b.free()
 gate_geometry()
 print("QUEST AUTO SEGMENT GEOMETRY: %d failures"%failures)
 quit(1 if failures else 0)
func gate_geometry()->void:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[1,2]
 b.session._profile.travel_pass=true
 var nav=Navigation.new()
 # North-to-south and south-to-north each require an original same-map gate.
 for spec in [[Vector2i(9,7),3110,"genout/wpm_10202_22_28"],[Vector2i(33,49),1000,"genout/wpm_10202_22_32"]]:
  b.automation.position_changed(10202,spec[0]);nav.clear()
  var npc:Dictionary={"id":"route-geometry-only","map_id":spec[1],"cell":[10,10]}
  var found:=false
  for index in range(200):
   var point:Dictionary=nav.next(b,npc)
   if point.is_empty():break
   check(nav.validate(b,point),"Original permit approach remains adjacent and valid")
   if point.has("gate"):
    found=true
    check(point.gate.source_id==spec[2],"Proposal identifies only the correct original guard")
    b.session._profile.travel_pass=false
    check(not nav.validate(b,point),"Revoking the permit invalidates the pending gate proposal")
    b.session._profile.travel_pass=true
    var wrong:Dictionary=point.duplicate(true);wrong.cell=[1,1]
    check(not nav.validate(b,wrong),"A gate proposal cannot carry a different destination")
    break
   b.automation.position_changed(int(point.map_id),Vector2i(point.cell[0],point.cell[1]),false,"walk")
  check(found,"Read-only geometry reaches the original guard without adding a portal")
 b.free()
