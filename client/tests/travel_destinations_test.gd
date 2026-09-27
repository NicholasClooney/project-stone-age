extends SceneTree
var failures:=0
var game
func _initialize():call_deferred("run")
func check(ok: bool, message: String):
 print(("PASS: " if ok else "FAIL: ")+message)
 if not ok:failures+=1
func run():
 game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame
 await process_frame
 var menu=load("res://scripts/travel_destinations.gd").new()
 menu.configure(game);game.ui_layer.add_child(menu)
 var maps: Dictionary={}
 var residents:=0
 var doors:=0
 for entry in menu.entries:
  if entry.kind==1:maps[entry.map_id]=true
  elif entry.kind==2:residents+=1
  else:doors+=1
 check(maps.size()==game.world_catalog.maps.size() and maps.size()>=103,"all imported maps present, not just curated shortcuts")
 check(residents>=game.world_catalog.residents.size() and doors>0,"residents and original doors included")
 menu.open_menu()
 check(menu.visible and game.paused_input,"browser pauses movement")
 menu.search.text="玛丽娜丝";menu.refresh()
 check(not menu.filtered.is_empty(),"Chinese map-name search finds new locations")
 var all_match:=true
 for entry in menu.filtered:
  if not str(entry.label).contains("玛丽娜丝"):all_match=false
 check(all_match,"all search results match")
 menu.search.text="";menu.category.select(1);menu.refresh()
 check(menu.filtered.size()==maps.size(),"map filter includes every registered map")
 var point=menu.safe_destination(1000,Vector2i(63,103))
 check(point!=Vector2i(63,103) and point.x>=0,"NPC coordinate relocates to adjacent walkable cell")
 check(not game.world_catalog.links(1000).has(point),"landing avoids automatic door triggers")
 check(menu.safe_destination(999999,Vector2i.ZERO)==Vector2i(-1,-1),"unknown map rejected")
 game.area_transition_busy=true
 check(not menu.visit_entry(menu.filtered[0]),"active map transition cannot be replaced")
 game.area_transition_busy=false
 menu.close_menu()
 check(not game.paused_input,"closing restores exploration")
 game.paused_input=true;menu.open_menu()
 check(not menu.visible,"cannot open over another modal")
 game.paused_input=false;menu.open_menu()
 var target: Dictionary={}
 for entry in menu.entries:
  if entry.kind==1 and entry.map_id==2000:target=entry;break
 check(menu.visit_entry(target),"travel to restored village succeeds")
 check(int(game.data.map_id)==2000 and not game.paused_input,"destination loaded and input restored")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.music.stream=null;game.effect.stream=null
 game.queue_free();await process_frame;await create_timer(0.5).timeout
 print("TRAVEL DESTINATIONS: %d failures" % failures)
 quit(1 if failures else 0)
