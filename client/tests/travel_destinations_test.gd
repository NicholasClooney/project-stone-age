extends SceneTree
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game);await process_frame
 var menu=game.dev_map_overview
 check(game.find_child("DevDestinations",true,false)==null,"independent teleport menu removed")
 check(not menu.walk_mode and menu.mode_button.text=="DEV 传送","map navigation defaults to teleport")
 var excluded:=0
 for key in game.world_catalog.maps:
  if game.world_catalog.is_building(int(key)):
   excluded+=1
   check(menu.selector.get_item_index(int(key))<0,"building excluded from map dropdown "+key)
 check(excluded>=94,"all %d imported settlement buildings excluded (94 before the Sainasu interiors)"%excluded)
 for id in [100,200,300,1000,2000,5000,5100,10201,10202,10203,32001]:
  check(menu.selector.get_item_index(id)>=0,"outdoor village or cave remains selectable%d"%id)
 var landing=game.travel_landing
 var point:Vector2i=landing.safe_destination(1000,Vector2i(93,72))
 check(point!=Vector2i(93,72) and point.x>=0,"safe landing still avoids separately stored MVP villager")
 check(not game.world_catalog.links(1000).has(point),"safe landing avoids doors")
 check(landing.safe_destination(999999,Vector2i.ZERO)==Vector2i(-1,-1),"unknown map rejected")
 var encounters=menu.background.get_node("DevRandomEncounters")
 encounters.button_pressed=false
 check(not game.random_encounters,"moved random encounter toggle updates game state")
 menu.open_map()
 menu.selector.item_selected.emit(menu.selector.get_item_index(2000))
 check(menu.current_map==2000 and int(game.data.map_id)==1000,"existing dropdown browses without instant movement")
 var spawn:Array=game.world_catalog.info(2000).spawn
 check(menu.select_target(Vector2i(spawn[0],spawn[1])),"clicking browsed map uses default teleport")
 await process_frame;await process_frame
 check(int(game.data.map_id)==2000 and not game.paused_input,"teleport changes village and closes navigation")
 game.load_area_id(1002,Vector2i(11,15));menu=game.dev_map_overview
 menu.open_map()
 check(not menu.background.get_node("DevRandomEncounters").button_pressed,"random encounter toggle retains state after map rebuild")
 check(menu.current_map==1002 and menu.selector.selected==-1 and menu.heading.text.contains("1002"),"current building remains viewable without appearing in dropdown")
 check(not menu.pois.is_empty(),"building retains door and actor navigation points")
 menu.mode_button.pressed.emit()
 check(menu.walk_mode,"walk toggle still available")
 menu.close_map()
 game.music.stop();game.effect.stop();game.queue_free();await process_frame;await create_timer(0.3).timeout
 print("TRAVEL DESTINATIONS: %d failures"%failures);quit(1 if failures else 0)
