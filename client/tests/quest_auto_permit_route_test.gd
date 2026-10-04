extends SceneTree
## Both actual permit transactions within full cross-island A task routes.
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
var failures:=0
func check(value:bool,label:String)->void:
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 for spec in [[30,1,1000,2427,Vector2i(21,33)],[11,2,3100,2415,Vector2i(21,27)]]:
  var b=Backend.new()
  b.quest_catalog.enabled_events=[int(spec[1])]
  b.session._profile.no_random_encounters=true
  b.session._profile.travel_pass=true
  b.session._profile.original_savepoint_bits=2 if spec[0]==11 else 1
  var home:int=spec[2]
  var spawn:Array=b.quest_helper.places.info(home).spawn
  b.automation.position_changed(home,Vector2i(spawn[0],spawn[1]))
  b.save_path="user://permit-route-%s.json"%spec[0]
  check(b.save(),"Initial real profile saved")
  check(b.handle({"type":"quest_auto_start","quest_id":spec[0],"client":"test"}).ok,"Cross-island task starts with existing permit")
  var crossed:=0
  var steps:=0
  for index in range(20000):
   if not b.quest_auto.running:break
   var old_map:int=b.automation.position_map
   var old:Vector2i=b.automation.position_cell
   var gold:int=b.session._profile.player.gold
   b.quest_auto.tick(b,0.21)
   var current:Vector2i=b.automation.position_cell
   if old_map==b.automation.position_map and absi(old.x-current.x)+absi(old.y-current.y)>1:
    crossed+=1
    check(old_map==10202 and current==spec[4],"Only the correct original guard makes its fixed same-map warp")
    check(b.session._profile.travel_pass and b.session._profile.player.gold==gold,"Original permit is reusable and no purchase or fee occurs")
    check(b.quest_auto.phase=="landing","Same-map original gate waits for the initiating map-ready ACK")
    check(not b.quest_arrival.has_arrival(b,10204,Vector2i(2,6)) and not b.quest_arrival.has_arrival(b,20101,Vector2i(29,69)),"Permit warp does not mint adult or herb arrival")
    var disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
    check(int(disk.location.map_id)==10202 and Vector2i(disk.location.x,disk.location.y)==current,"Original gate destination is really saved before movement publishes")
   elif old_map!=b.automation.position_map:
    var portal:Dictionary=b.quest_helper.places.links(old_map).get(old,{})
    check(not portal.is_empty() and int(portal.to_map)==b.automation.position_map and Vector2i(portal.target[0],portal.target[1])==current,"All other map changes follow original portals")
   if b.quest_auto.phase=="landing":
    b.handle({"type":"report_position","map_id":b.automation.position_map,"cell":[current.x,current.y],"client":"test"})
   steps+=1
  check(crossed==1,"Full cross-island route uses exactly its original permit gate")
  check(not b.quest_auto.running and Rules.flag(b.session._profile,"ended",spec[1]) and b.session._profile.original_items==[spec[3]],"Cross-island original chain completes: "+str(spec[0])+" / "+b.quest_auto.message)
  print("PERMIT ROUTE ",spec[0]," ticks=",steps," gates=",crossed)
  for path in [b.save_path,b.save_path+".bak",b.save_path+".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
  b.free()
 print("QUEST AUTO PERMIT ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
