extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.random_encounters=false
 var rows:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/level-one-spots.json")).spots
 for row in rows:
  var map=game.dev_map_overview
  map.open_map();map.walk_mode=false
  var poi={"map_id":int(row.map_id),"area_id":int(row.area_id),"cell":Vector2i(row.cell[0],row.cell[1])}
  var moved:bool=map.select_poi(poi)
  await process_frame;await process_frame
  var menu=game.pet_hunt_menu
  menu.open_menu()
  var found:=false
  var renderable:=false
  for i in range(menu.species.item_count):
   if menu.species.get_item_id(i)==int(row.template_id):
    found=true;renderable=not menu.species.is_item_disabled(i)
  check(moved and game.cell==poi.cell and int(game.data.map_id)==int(row.map_id) and found and renderable and not menu.start_button.disabled,"%s map %d (%s) found=%s render=%s enabled=%s actual=%s"%[row.name,row.map_id,poi.cell,found,renderable,not menu.start_button.disabled,game.cell])
  menu.auto_capture.button_pressed=false;menu.start_hunt()
  check(menu.running,"%s verified target starts real hunt"%row.name)
  menu.close_menu()
 var map=game.dev_map_overview
 map.open_map();map.walk_mode=false;map.browse_map(200);map.select_category(2)
 var pet_cell:=Vector2i(460,335)
 var edge:Vector2=map.cell_to_point(pet_cell)+Vector2(-2.9,0)
 var raw:Vector2i=map.point_to_cell(edge)
 check(preload("res://scripts/pet_hunt_rules.gd").candidates(game.encounter_catalog,200,raw,true).is_empty(),"visible marker edge previously selected adjacent non-Lv1 region")
 var press:=InputEventMouseButton.new()
 press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=edge
 map._gui_input(press)
 var release:=InputEventMouseButton.new()
 release.button_index=MOUSE_BUTTON_LEFT;release.pressed=false;release.position=edge
 map._gui_input(release)
 await process_frame;await process_frame
 check(int(game.data.map_id)==200 and game.cell==pet_cell,"click inside rendered Lv1 marker lands on verified pet cell")
 game.pet_hunt_menu.open_menu()
 check(not game.pet_hunt_menu.start_button.disabled,"marker teleport exposes huntable newborn species")
 game.pet_hunt_menu.close_menu()
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;await create_timer(0.3).timeout
 print("LV1 HUNT NAVIGATION: %d failures"%failures)
 quit(1 if failures else 0)
