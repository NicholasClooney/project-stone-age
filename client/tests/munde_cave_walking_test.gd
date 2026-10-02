extends SceneTree
## Start at the already-tested keyword Warp, then walk every ordinary original staircase.
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
func check(ok:bool,note:String)->bool:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
 return ok
func _initialize()->void:call_deferred("run")
func run()->void:
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 if not check(await Wait.until(self,func():return not game.data.is_empty()),"isolated world loads"):quit(1);return
 game.random_encounters=false
 if not check(game.load_area_id(11101,Vector2i(33,29)),"start at exact original keyword destination"):quit(1);return
 for level in range(11101,11107):
  var door:Dictionary={}
  for p in game.world_catalog.links(level).values():
   if int(p.to_map)==level+1:door=p;break
  if not check(not door.is_empty(),"original staircase exists %d"%level):break
  var cell:=Vector2i(int(door.cell[0]),int(door.cell[1]))
  var route:Array[Vector2i]=game.navigation.get_id_path(game.cell,cell)
  if not check(route.size()>1,"source collision has walkable route from prior landing %d"%level):break
  game.walk_to(cell)
  if not check(await Wait.until(self,func():return int(game.data.map_id)==level+1 and not game.area_transition_busy,180.0),"production walk enters original next floor %d"%level):break
  if not check(game.cell==Vector2i(int(door.target[0]),int(door.target[1])),"exact original stair destination"):break
 check(int(game.data.map_id)==11107,"all six original staircases reach guard floor")
 check(not game.world_catalog.links(11107).has(Vector2i(22,41)) and not game.world_catalog.links(11107).has(Vector2i(23,41)),"neither guard cell contains scenic bypass")
 game.music.stop();game.effect.stop();game.queue_free()
 await process_frame
 print("MUNDE CAVE WALKING: %d failures"%failures)
 quit(1 if failures else 0)
