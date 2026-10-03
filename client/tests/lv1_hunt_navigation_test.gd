extends SceneTree
const Wait=preload("res://tests/support/wait.gd")
const ReviewedTravel=preload("res://server/reviewed_hunt_travel.gd")
var failures:=0
func _initialize():call_deferred("run")
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 check(await Wait.until(self,func():return not game.data.is_empty()),"production GameScene starts")
 game.random_encounters=false
 var rows:Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/level-one-spots.json")).spots
 for row in rows:
  var map=game.dev_map_overview
  map.open_map();map.walk_mode=false
  var poi={"map_id":int(row.map_id),"area_id":int(row.area_id),"cell":Vector2i(row.cell[0],row.cell[1])}
  var moved:=false
  if not ReviewedTravel.reviewed_target(int(row.map_id),int(row.area_id),int(row.template_id)).is_empty():
   map.close_map()
   var menu=game.pet_encyclopedia
   menu.encyclopedia()
   for place in menu.book.entry_for(int(row.template_id)).locations:
    if int(place.map_id)==int(row.map_id) and int(place.area_id)==int(row.area_id):
     moved=menu.go_catch(place);break
  else:moved=map.select_poi(poi)
  check(await Wait.until(self,func():return int(game.data.map_id)==int(row.map_id) and game.cell==poi.cell and not game.area_transition_busy and not map._project_travel_pending and game.pet_encyclopedia.pending_hunt.is_empty()) and await Wait.settle(self,game),"%s destination position settles"%row.name)
  var menu=game.pet_hunt_menu
  if not menu.visible:menu.open_menu()
  menu.show_target(int(row.template_id),true)
  check(menu.choose_target(int(row.template_id)),"%s real target selection"%row.name)
  var found:=false
  var renderable:=false
  for i in range(menu.species.item_count):
   if menu.species.get_item_id(i)==int(row.template_id):
    found=true;renderable=not menu.species.is_item_disabled(i)
  check(moved and game.cell==poi.cell and int(game.data.map_id)==int(row.map_id) and found and renderable and not menu.start_button.disabled,"%s map %d (%s) found=%s render=%s enabled=%s actual=%s"%[row.name,row.map_id,poi.cell,found,renderable,not menu.start_button.disabled,game.cell])
  menu.auto_capture.button_pressed=false;menu.start_hunt()
  check(menu.running,"%s verified target starts real hunt; reason=%s auth=%s/%s pending=%s"%[row.name,menu.status.text,game.backend.automation.position_map,game.backend.automation.position_cell,map._project_travel_pending])
  if int(row.map_id)==41:check(game.backend.automation.hunt_running and game.backend.automation.position_map==41 and game.backend.automation.position_cell==poi.cell,"Burkel hunt runs at authoritative original position")
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
 check(await Wait.until(self,func():return int(game.data.map_id)==200 and game.cell==pet_cell) and await Wait.settle(self,game),"marker position settles")
 check(int(game.data.map_id)==200 and game.cell==pet_cell,"click inside rendered Lv1 marker lands on verified pet cell")
 game.pet_hunt_menu.open_menu()
 check(not game.pet_hunt_menu.start_button.disabled,"marker teleport exposes huntable newborn species")
 game.pet_hunt_menu.close_menu()
 game.process_mode=Node.PROCESS_MODE_DISABLED
 game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;await create_timer(0.3).timeout
 print("LV1 HUNT NAVIGATION: %d failures"%failures)
 quit(1 if failures else 0)
