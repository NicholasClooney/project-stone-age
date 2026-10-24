extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Real original routes and transactions; only the ordinary encounter toggle is off.
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var started:=Clock.ticks_msec()
 for spec in [[1,4,1000,2418,[1000,100,1100,10201,10202,10204]],[11,2,1000,2414,[1000,100,2000]],[30,1,3100,2427,[3100,3110,200,20101,20102,20103,20104,20105]]]:
  var b=Backend.new()
  b.quest_catalog.enabled_events=[int(spec[1])]
  b.session._profile.no_random_encounters=true
  if int(spec[0])==1:b.session.gm_raise_level(-1,30)
  for item in b.session._profile.inventory:b.session._profile.inventory[item]=0
  var home:int=spec[2]
  var spawn:Array=b.quest_helper.places.info(home).spawn
  b.automation.position_changed(home,Vector2i(spawn[0],spawn[1]))
  var seen:Dictionary={home:true}
  check(b.handle({"type":"quest_auto_start","quest_id":spec[0],"client":"test"}).ok,"Original task starts at its manifest home: "+str(spec[0]))
  var moves:=0
  for index in range(20000):
   if not b.quest_auto.running:break
   var old_map:int=b.automation.position_map
   var old_cell:Vector2i=b.automation.position_cell
   b.quest_auto.tick(b,0.21)
   var next_map:int=b.automation.position_map
   var next_cell:Vector2i=b.automation.position_cell
   if old_map!=next_map:
    var portal:Dictionary=b.quest_helper.places.links(old_map).get(old_cell,{})
    check(not portal.is_empty() and int(portal.to_map)==next_map and Vector2i(portal.target[0],portal.target[1])==next_cell,"Every map change uses its exact original portal")
    seen[next_map]=true
   elif old_cell!=next_cell:
    moves+=1
    check(absi(old_cell.x-next_cell.x)+absi(old_cell.y-next_cell.y)==1,"A commits exactly one adjacent logical cell")
   check(b.quest_arrival.has_arrival(b,next_map,next_cell),"Original route retains actual arrival eligibility")
   if b.quest_auto.phase=="landing":
    b.handle({"type":"report_position","map_id":next_map,"cell":[next_cell.x,next_cell.y],"client":"test"})
  check(not b.quest_auto.running and Rules.flag(b.session._profile,"ended",spec[1]) and b.session._profile.original_items==[spec[3]],"Full original task reward once: "+str(spec[0])+" / "+b.quest_auto.message)
  for map_id in spec[4]:check(seen.has(map_id),"Route actually visits "+str(map_id))
  check(moves>300,"Full route is not a convenience fixture")
  print("A ROUTE ",spec[0]," moves=",moves," maps=",seen.keys())
  b.free()
 replan()
 print("QUEST AUTO NAVIGATION: %d failures; %.2fs"%[failures,(Clock.ticks_msec()-started)/1000.0])
 quit(1 if failures else 0)
func replan()->void:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 var nav=preload("res://server/quest_auto_navigation.gd").new()
 var npc:Dictionary=b.original_quests.npc_by_id("sainasu/event/event02_2")
 check(nav.next(b,npc).is_empty(),"Unknown initial location cannot invent a route")
 b.automation.position_changed(1000,Vector2i(89,73))
 var first:Dictionary=nav.next(b,npc)
 check(not first.is_empty() and nav.validate(b,first),"Source path starts with a valid adjacent point")
 # A legitimate external relocation invalidates the cached origin. Geometry
 # replans once; it neither writes the authority cell nor mints arrival proof.
 b.automation.position_changed(1000,Vector2i(89,74))
 var origin:Vector2i=b.automation.position_cell
 var next:Dictionary=nav.next(b,npc)
 check(not next.is_empty() and nav.validate(b,next),"Cached tail replans from current authority")
 check(b.automation.position_cell==origin,"Planning is read-only")
 b.free()
