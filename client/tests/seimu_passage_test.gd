extends SceneTree
const Backend=preload("res://server/backend.gd")
const Catalog=preload("res://scripts/world_catalog.gd")
const Router=preload("res://scripts/travel_router.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false
 root.add_child(game)
 check(await Wait.until(self,func():return not game.data.is_empty()),"isolated game ready")
 game.random_encounters=false
 var backend=Backend.new()
 # The restored fee writer needs a real isolated primary/cache, not an empty path.
 backend.save_path="user://seimu-passage-fee-test.json"
 if not backend.save():
  check(false,"initial isolated fee profile saves")
  game.free();backend.free();quit(1);return
 var doors=[]
 for p in Catalog.new().links(40).values():
  if int(p.to_map) in [31301,31401,31501]:doors.append(p)
 for id in [31301,31401,31501]:
  for p in Catalog.new().links(id).values():
   if int(p.to_map)==40:doors.append(p)
 var expected:Array=[
  [40,[1,8],31401,[92,27]], [40,[12,18],31501,[32,2]],
  [31301,[10,103],40,[12,1]], [31401,[94,27],40,[1,9]], [31501,[34,2],40,[11,18]]]
 var actual:Array=doors.map(func(p):return [int(p.from_map),[int(p.cell[0]),int(p.cell[1])],int(p.to_map),[int(p.target[0]),int(p.target[1])]])
 var order:Callable=func(a,b):return str(a)<str(b)
 actual.sort_custom(order);expected.sort_custom(order)
 check(actual==expected,"exact five original ordinary sea doors; Giru outbound is paid NPC")
 check(not Catalog.new().links(40).has(Vector2i(13,1)),"original paid NPC has no permit-only convenience portal")
 var paid:Dictionary=backend.original_quests.npc_by_id("genout/wpm_40_13_1@40:13:1")
 check(not paid.is_empty() and paid.branches[0].actions=={"Warp":"31301,10,104","DelStone":"300"},"original source fee and landing preserved")
 for door in doors:
  var origin=int(door.from_map)
  var target=int(door.to_map)
  var point=Vector2i(door.cell[0],door.cell[1])
  backend.automation.position_changed(origin,point,true)
  var command={"type":"check_passage","from_map":origin,"to_map":target}
  check(not backend.handle(command).get("ok",false),"server denies gate %d -> %d without permit" % [origin,target])
  check(not backend.handle({"type":"report_position","map_id":target,"cell":door.target,"map_changed":true}).get("ok",false) and backend.automation.position_map==origin,"direct position report cannot bypass permit")
  check(game.load_area_id(origin,point),"source gate loads")
  game.arrival_lock=Vector2i(-1,-1)
  check(not game.handle_arrival() and int(game.data.map_id)==origin,"walking gate refuses missing permit")
 for a in [100,200,300,400]:
  for b in [100,200,300,400]:
   if a==b:continue
   check(game.travel_router.map_route(a,b,false).is_empty(),"no permit route between islands %d and %d" % [a,b])
   check(game.travel_router.map_route(a,b,true).is_empty()==(b==300),"ordinary permit graph excludes only paid outbound Giru leg %d -> %d" % [a,b])
 # Explicit already-owned legacy compatibility fixtures, NOT purchases.
 backend.session._profile.travel_pass=true
 game.backend.session._profile.travel_pass=true
 game.backend.publish()
 check(backend.session.has_travel_pass(),"server legacy compatibility fixture grants passage")
 check(game.session.has_travel_pass(),"authoritative legacy compatibility fixture reaches client")
 for door in doors:
  var origin=int(door.from_map)
  var target=int(door.to_map)
  var point=Vector2i(door.cell[0],door.cell[1])
  backend.automation.position_changed(origin,point,true)
  check(backend.handle({"type":"check_passage","from_map":origin,"to_map":target}).get("ok",false),"server accepts permitted gate")
  check(backend.handle({"type":"report_position","map_id":target,"cell":door.target,"map_changed":true}).get("ok",false),"server accepts permitted arrival")
  check(game.load_area_id(origin,point),"permitted source loads")
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"permitted gate begins transition")
  check(await Wait.until(self,func():return not game.area_transition_busy),"permitted transition finishes")
  check(int(game.data.map_id)==target and game.cell==Vector2i(door.target[0],door.target[1]),"original gate destination retained")
 # A travel permit does not waive this restored original MONEY300 branch.
 backend.session._profile.player.gold=299
 backend.automation.position_changed(40,Vector2i(13,2))
 if not backend.save():
  check(false,"insufficient fee fixture is actually saved")
  game.free();backend.free();quit(1);return
 var offer:Dictionary=backend.handle({"type":"quest_talk","npc_id":paid.id})
 check(not backend.handle({"type":"quest_choose","token":offer.get("dialogue",{}).get("token",""),"choice":"yes"}).ok and backend.automation.position_map==40,"permit cannot waive original300 fee")
 backend.session._profile.player.gold=300
 if not backend.save():
  check(false,"exact fee fixture is actually saved")
  game.free();backend.free();quit(1);return
 offer=backend.handle({"type":"quest_talk","npc_id":paid.id})
 var pay:Dictionary={"type":"quest_choose","token":offer.get("dialogue",{}).get("token",""),"choice":"yes"}
 check(backend.handle(pay).ok and backend.session.snapshot().player.gold==0 and backend.automation.position_map==31301 and backend.automation.position_cell==Vector2i(10,104),"original paid sea NPC deducts300 and commits exact Warp")
 check(not backend.handle(pay).ok,"paid sea token cannot replay")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.queue_free();backend.free()
 print("SEIMU PERMIT: %d failures" % failures)
 quit(1 if failures else 0)
