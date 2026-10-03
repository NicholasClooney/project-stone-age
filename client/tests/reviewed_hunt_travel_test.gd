extends SceneTree
const Backend=preload("res://server/backend.gd")
const Travel=preload("res://server/reviewed_hunt_travel.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run()->void:
 var b=Backend.new()
 var counts:Dictionary={41:0,42:0,31806:0}
 for row in Travel.targets():
  var plan:Dictionary=b.reviewed_hunt_travel.resolve(b,row)
  check(not plan.is_empty() and plan.cell==Vector2i(int(row.cell[0]),int(row.cell[1])),"server derives exact reviewed catch plan %s"%str(row))
  counts[int(row.map_id)]+=1
 check(counts=={41:22,42:22,31806:7},"complete authorized 44 Dream plus seven mine targets")
 b.automation.position_changed(41,Vector2i(47,54))
 var before:Dictionary=b.session.snapshot()
 var target:={"type":"reviewed_hunt_travel","map_id":41,"area_id":416,"template_id":72,"cell":[1,1],"party":true,"grant":true}
 var result:Dictionary=b.handle(target)
 check(result.ok and b.automation.position_cell==Vector2i(34,35),"server ignores forged cell and permission fields and uses exact audited capture point")
 check(b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events,"capture travel changes no rewards or flags")
 var invalid:=target.duplicate(true);invalid.template_id=65
 check(not b.handle(invalid).ok,"wrong species for reviewed reward room rejected")
 invalid=target.duplicate(true);invalid.area_id=999
 check(not b.handle(invalid).ok,"arbitrary map coordinate area cannot obtain capture permit")
 invalid=target.duplicate(true);invalid.map_id=31805
 check(not b.handle(invalid).ok,"unreviewed map cannot obtain special travel")
 b.automation.position_changed(41,Vector2i(47,54))
 check(not b.handle({"type":"report_position","map_id":41,"cell":[34,35],"grant":true,"client":"party"}).ok,"ordinary report and forged party still cannot cross final guard")
 b.quest_visit_guard=func():return "组队"
 check(not b.handle(target).ok,"capture travel preserves existing party restriction")
 b.free();print("REVIEWED HUNT TRAVEL: %d failures"%failures);quit(1 if failures else 0)
