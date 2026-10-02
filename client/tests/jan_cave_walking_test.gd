extends "res://tests/munde_cave_walking_test.gd"
func run()->void:
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 if not check(await Wait.until(self,func():return not game.data.is_empty()),"isolated Jan world loads"):quit(1);return
 game.random_encounters=false
 if not check(game.load_area_id(20601,Vector2i(9,59)),"exact original outside entrance destination"):quit(1);return
 for level in range(20601,20604):
  var door:Dictionary={}
  for p in game.world_catalog.links(level).values():
   if int(p.to_map)==level+1:door=p;break
  if not check(not door.is_empty(),"original staircase exists %d"%level):break
  var cell:=Vector2i(int(door.cell[0]),int(door.cell[1]))
  if not check(game.navigation.get_id_path(game.cell,cell).size()>1,"source collision connects original stairs"):break
  game.walk_to(cell)
  if not check(await Wait.until(self,func():return int(game.data.map_id)==level+1 and not game.area_transition_busy,180.0),"actual world walk enters next floor"):break
  check(game.cell==Vector2i(int(door.target[0]),int(door.target[1])),"exact original stair landing")
 check(int(game.data.map_id)==20604,"three original stairs reach first keyword floor")
 for stage in [[20604,11,54],[20605,4,71,51,5],[20606,64,3,9,24],[20607,7,5,28,31]]:
  # Subsequent starts are exact keyword destinations, whose transactions have independent route/UI tests.
  if stage.size()==5:check(game.load_area_id(stage[0],Vector2i(stage[1],stage[2])),"source keyword landing fixture")
  var target:=Vector2i(stage[-2],stage[-1])
  if not check(game.navigation.get_id_path(game.cell,target).size()>1,"source route to next keyword/guard exists"):break
  game.walk_to(target)
  if not check(await Wait.until(self,func():return game.cell==target and game.path.is_empty(),180.0),"actual world walks from original landing to next gate"):break
 check(game.load_area_id(20607,Vector2i(36,31)),"exact battle victory landing fixture")
 game.walk_to(Vector2i(75,13))
 check(await Wait.until(self,func():return int(game.data.map_id)==20608 and not game.area_transition_busy,180.0),"actual walk follows original portal into Sarah room")
 check(game.cell==Vector2i(0,7),"fixed source first-match portal lands0,7")
 # Move off the arrival lock, then walk back onto the actual source return portal.
 game.walk_to(Vector2i(1,7))
 check(await Wait.until(self,func():return game.cell==Vector2i(1,7) and game.path.is_empty()),"step away from Sarah-room arrival portal")
 game.walk_to(Vector2i(0,7))
 check(await Wait.until(self,func():return int(game.data.map_id)==20607 and not game.area_transition_busy),"actual original return portal reaches Jan floor")
 check(game.cell==Vector2i(75,13),"exact source return destination")
 game.music.stop();game.effect.stop();game.queue_free();await process_frame
 print("JAN CAVE WALKING: %d failures"%failures);quit(1 if failures else 0)
