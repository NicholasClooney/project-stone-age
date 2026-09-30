extends SceneTree
var failures:=0
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame;await process_frame
 game.random_encounters=false
 var catalog=game.world_catalog
 for village in [5000,5100]:
  check(catalog.info(village).get("kind")=="village","Giru village classified as settlement %d"%village)
  check(game.dev_map_overview.selector.get_item_index(village)>=0,"Giru village appears in map navigator %d"%village)
 game.dev_map_overview.browse_map(300)
 for label in ["福尔德村","达那村"]:
  check(game.dev_map_overview.pois.any(func(p):return str(p.name).contains(label)),"Giru overview marks village entrance "+label)
 for village in [5000,5100]:
  check(game.dev_visit(village),"teleport loads Giru village %d"%village)
  await process_frame;await process_frame
  check(game.is_walkable(game.cell) and game.checkpoint(),"village has walkable persistent arrival")
  var saved: Dictionary=game.session.snapshot().location
  check(int(saved.map_id)==village and Vector2i(saved.x,saved.y)==game.cell,"checkpoint records village and arrival cell")
  check(game.music.stream.resource_path.get_file().get_basename()==str(catalog.info(village).music).get_file().get_basename(),"village uses original music")
  var interior:=5001 if village==5000 else 5101
  for building in ([5001,5003,5005] if village==5000 else [5101,5103,5105,5106]):
   check(catalog.village_for(building)==village,"building ownership uses declared village %d"%building)
   check(game.dev_map_overview.selector.get_item_index(building)<0,"building hidden from navigation dropdown %d"%building)
  check(catalog.village_for(interior)==village,"interior ownership works beyond old map-number cutoff")
  check(game.dev_visit(interior),"ordinary village building can be entered")
  await process_frame
  var exit_link: Dictionary={}
  for link in catalog.links(village).values():
   if int(link.to_map)==300:exit_link=link;break
  check(not exit_link.is_empty(),"village has original Giru exit")
  if exit_link.is_empty():continue
  game.load_area_id(village,Vector2i(exit_link.cell[0],exit_link.cell[1]))
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"walking over village exit triggers map transition")
  while game.area_transition_busy:await process_frame
  check(int(game.data.map_id)==300,"village exit arrives on Giru")
  var entrance: Dictionary={}
  for link in catalog.links(300).values():
   if int(link.to_map)==village:entrance=link;break
  check(not entrance.is_empty(),"Giru has original village entrance")
  if entrance.is_empty():continue
  game.load_area_id(300,Vector2i(entrance.cell[0],entrance.cell[1]))
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"walking over Giru entrance triggers map transition")
  while game.area_transition_busy:await process_frame
  check(int(game.data.map_id)==village,"Giru entrance returns to village")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
 game.queue_free();await process_frame;await create_timer(0.5).timeout
 print("GIRU VILLAGES: %d failures"%failures)
 quit(1 if failures else 0)
