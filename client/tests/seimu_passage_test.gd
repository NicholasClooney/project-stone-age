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
 var doors=[]
 for p in Catalog.new().links(40).values():
  if int(p.to_map) in [31301,31401,31501]:doors.append(p)
 for id in [31301,31401,31501]:
  for p in Catalog.new().links(id).values():
   if int(p.to_map)==40:doors.append(p)
 check(doors.size()==6,"all original sea doors imported")
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
   check(not game.travel_router.map_route(a,b,true).is_empty(),"permit connects islands %d and %d" % [a,b])
 backend.session._profile.player.gold=200
 check(backend.session.buy_travel_pass(),"server permit bought")
 game.backend.session._profile.player.gold=200
 check(game.session.buy_travel_pass(),"client permit bought")
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
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.queue_free();backend.free()
 print("SEIMU PERMIT: %d failures" % failures)
 quit(1 if failures else 0)
