extends SceneTree
var failures:=0
func check(ok: bool,note: String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.random_encounters=false
 var menu=game.dev_map_overview
 menu.open_map()
 check(menu.tabs.tab_count==3,"navigation exposes three category tabs")
 menu.browse_map(300)
 menu.select_category(0)
 check(not menu.scope_button.visible,"places tab has no misleading all-map scope")
 check(menu.pois.any(func(p):return str(p.name).contains("福尔德村")) and menu.pois.any(func(p):return str(p.name).contains("达那村")),"places retains both Giru village entrances")
 check(menu.pois.all(func(p):return p.get("kind","") in ["pet","pet_added"] or not p.has("area_id")),"places tab excludes training locations")
 check(menu.pois.any(func(p):return p.get("kind","")=="pet" and str(p.name).begins_with("Lv.1 宠物")),"places tab marks Lv.1 pet areas")
 menu.all_maps=false;menu.select_category(1)
 check(not menu.pois.is_empty() and menu.pois.all(func(p):return int(p.map_id)==300 and p.name.begins_with("练级")),"training current-map scope contains only Giru training")
 var local_count:int=menu.pois.size()
 menu.scope_button.pressed.emit()
 check(menu.all_maps and menu.pois.size()>local_count and menu.pois.any(func(p):return int(p.map_id)!=300),"scope button exposes all imported training maps")
 menu.tabs.current_tab=2
 check(menu.category==2 and menu.pois.all(func(p):return str(p.name).contains("Lv.1") and not str(p.name).begins_with("练级")),"Lv1 tab signal selects separate species list")
 var rows: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/level-one-spots.json")).spots
 check(menu.pois.size()==rows.size(),"all-map pet list matches generated species locations")
 var valid:=true
 var region_valid:=true
 for row in rows:
  var enemy: Dictionary=game.encounter_catalog.data.enemies[str(int(row.enemy_id))]
  valid=valid and int(enemy.pet_flag)!=0 and int(enemy.level_min)<=1 and int(enemy.level_max)>=1 and int(enemy.template_id)==int(row.template_id)
  var area: Dictionary=game.encounter_catalog.area_at(int(row.map_id),Vector2i(row.cell[0],row.cell[1]))
  region_valid=region_valid and not area.is_empty() and int(area.id)==int(row.area_id)
 check(valid,"every indexed species is independently capturable at Lv1 in source enemy row")
 check(region_valid,"every location selects its declared original encounter region")
 menu.scope_button.pressed.emit()
 check(not menu.all_maps and not menu.pois.is_empty() and menu.pois.all(func(p):return int(p.map_id)==300),"Lv1 current-map scope filters foreign species locations")
 var original_map:int=game.data.map_id
 var stale: Dictionary=menu.pois[0].duplicate(true)
 stale.area_id=-999
 check(not menu.select_poi(stale) and int(game.data.map_id)==original_map and menu.visible,"stale encounter region rejected without movement")
 var blocked: Dictionary=menu.pois[0].duplicate(true)
 var source: Dictionary=game.encounter_catalog.area_at(int(blocked.map_id),blocked.cell)
 var found_blocked:=false
 for y in range(int(source.rect[1]),int(source.rect[3])+1):
  for x in range(int(source.rect[0]),int(source.rect[2])+1):
   var cell:=Vector2i(x,y)
   if Rect2i(Vector2i.ZERO,menu.map_dimensions).has_point(cell) and not menu._walkable(cell):
    var actual: Dictionary=game.encounter_catalog.area_at(int(blocked.map_id),cell)
    if not actual.is_empty() and int(actual.id)==int(blocked.area_id):
     blocked.cell=cell;found_blocked=true;break
  if found_blocked:break
 check(found_blocked,"test fixture finds blocked cell in same encounter region")
 check(found_blocked and not menu.select_poi(blocked) and int(game.data.map_id)==original_map and menu.visible,"unsafe encounter landing rejected instead of silently relocating")
 menu.browse_map(5000)
 check(menu.pois.is_empty(),"village does not inherit wilderness pet list")
 menu.select_category(0)
 check(not menu.pois.is_empty() and menu.pois.all(func(p):return int(p.map_id)==5000),"village places preserved after tab switching")
 menu.close_map()
 game.load_area_id(1000,Vector2i(85,95))
 menu=game.dev_map_overview;menu.open_map();menu.walk_mode=true
 var point:=Vector2i(80,90)
 check(menu.select_poi({"map_id":1000,"cell":point}),"POI selection starts walk route")
 check(game.cell==Vector2i(85,95) and game.travel_router.active and not menu.visible,"walking does not teleport and closes map")
 game.travel_router.cancel("test");game.clear_input()
 menu.open_map();menu.walk_mode=false
 var destination: Dictionary=game.world_catalog.info(5000)
 var spawn:=Vector2i(destination.spawn[0],destination.spawn[1])
 check(menu.select_poi({"map_id":5000,"cell":spawn}),"foreign POI supports explicit teleport mode")
 await process_frame;await process_frame
 check(int(game.data.map_id)==5000 and game.is_walkable(game.cell),"foreign POI teleport loads safe village destination")
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;await create_timer(0.3).timeout
 print("MAP NAVIGATION TABS: %d failures"%failures)
 quit(1 if failures else 0)
