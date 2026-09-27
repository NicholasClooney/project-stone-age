extends SceneTree
var game
var failures := 0
func _initialize():call_deferred("run")
func check(ok: bool, note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func frames():
 await process_frame
 await process_frame
func run():
 game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false
 root.add_child(game)
 await frames()
 game.random_encounters=false
 var catalog=game.world_catalog
 check(catalog.maps.size()>=103,"original villages, interiors, wilderness and crossing route imported")
 for id in [1000,2000,3000,4000,100,200,1100,1300,1400,3100,3200,3300,3400,10201,10202,10203]:
  var start=Time.get_ticks_msec()
  check(game.dev_visit(id),"developer destination loads original map %d" % id)
  await frames()
  game.camera.reset_smoothing()
  check(game.is_walkable(game.cell) and game.display_cell()==game.cell,"map %d uses safe original coordinates" % id)
  check(game.session.set_location(id,game.cell.x,game.cell.y),"map %d location accepted by save authority" % id)
  var bridges_ok=true
  for index in game.props.visible_props:
   var ident=str(int(game.data.objects[index][2]))
   var metadata: Dictionary=game.data.images[ident]
   if int(metadata.get("priority",0))==3 and int(metadata.hit)!=0:
    bridges_ok=bridges_ok and game.props.visible_props[index].z_index==-1
  check(bridges_ok,"map %d respects original bridge drawing priority" % id)
  check(game.props.visible_props.size()<3000,"map %d streams nearby scenery instead of entire island" % id)
  check(game.music.stream.resource_path.ends_with(str(catalog.info(id).music)),"map %d uses source music" % id)
  print("WORLD LOAD %d: %dms / %d visible props" % [id,Time.get_ticks_msec()-start,game.props.visible_props.size()])
  if DisplayServer.get_name()!="headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://../artifacts/world-%d.png" % id)
 # All imported interiors are valid for loading and persistence, not only dev-menu entries.
 for id_text in catalog.maps:
  var id=int(id_text)
  if id in [1000,2000,3000,4000,100,200,1100,1300,1400,3100,3200,3300,3400,10201,10202,10203]:continue
  var info: Dictionary=catalog.info(id)
  check(game.load_area_id(id,Vector2i(info.spawn[0],info.spawn[1])),"interior %d loads original map" % id)
  await frames()
  check(game.checkpoint(),"interior %d can checkpoint" % id)
 # Exercise actual portal trigger/transition in both directions for each village.
 for id in [1000,2000,3000,4000,1300,1400,3100,3200,3300,3400]:
  var chosen: Dictionary={}
  for link in catalog.links(id).values():
   if int(link.to_map) in [100,200]:chosen=link;break
  check(not chosen.is_empty(),"village %d has source wilderness exits" % id)
  if chosen.is_empty():continue
  game.load_area_id(id,Vector2i(chosen.cell[0],chosen.cell[1]))
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"village %d exit starts actual transition" % id)
  while game.area_transition_busy:await process_frame
  check(int(game.data.map_id)==int(chosen.to_map) and game.cell==Vector2i(chosen.target[0],chosen.target[1]),"village %d exit preserves source destination" % id)
  var incoming: Dictionary={}
  for link in catalog.links(int(chosen.to_map)).values():
   if int(link.to_map)==id:incoming=link;break
  game.load_area_id(int(incoming.from_map),Vector2i(incoming.cell[0],incoming.cell[1]))
  game.arrival_lock=Vector2i(-1,-1)
  check(game.handle_arrival(),"village %d entrance starts actual transition" % id)
  while game.area_transition_busy:await process_frame
  check(int(game.data.map_id)==id,"village %d return enters village" % id)
 # Real dev menu selection, not only direct helper calls.
 game.dev_destinations.get_popup().id_pressed.emit(3000)
 await frames()
 check(int(game.data.map_id)==3000,"developer menu selection travels to Jaja")
 game.paused_input=true
 check(not game.dev_visit(4000),"teleport rejects modal/battle state")
 game.paused_input=false
 check(not game.dev_visit(99999),"unknown destination rejected")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop()
 game.music.stream=null;game.effect.stream=null
 game.queue_free()
 await frames()
 await create_timer(0.5).timeout
 print("WORLD EXPANSION: %d failures" % failures)
 quit(1 if failures else 0)
