extends SceneTree
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.random_encounters=false
 game.switch_area(true,Vector2i(45,45))
 var menu=game.pet_hunt_menu
 menu.open_menu()
 check(menu.rate.max_value>=2000 and menu.rate.value==100,"higher requested rates supported without changing default")
 menu.rate.value=2000;menu.start_hunt()
 check(menu.running and menu.filter.rate==2000,"2000/s target starts")
 # Impossible test-only quality threshold prevents random hit from ending sample.
 # The real encounter generator and per-actor checks remain unchanged.
 var direct:=RandomNumberGenerator.new();direct.seed=24680
 var prepared:=RandomNumberGenerator.new();prepared.seed=24680
 var identical:=true
 for i in range(100):
  var expected:Dictionary=game.encounter_catalog.roll(menu.region_map,menu.region_cell,direct)
  var actual:Dictionary=menu.hunt_catalog.roll(menu.region_map,menu.region_cell,prepared)
  identical=identical and expected==actual and direct.state==prepared.state
 check(identical,"prepared location preserves 100 complete troops and exact RNG states")
 menu.filter.total=9
 menu._process(1.0/60.0)
 check(menu.rolls>0,"real encounter work runs under the frame budget")
 menu._process(2.0)
 check(menu.credit<=200.0,"long stall retains at most 100ms of requested work")
 check(menu.credit>20.0,"backlog is no longer artificially capped at 20 groups")
 check(menu.status.text.contains("目标 2000") and menu.status.text.contains("实际"),"requested and actual throughput are visible")
 menu.stop_hunt("test")
 var before:int=menu.rolls
 menu._process(1)
 check(menu.rolls==before,"cancelled scan performs no more work")
 menu.start_hunt()
 var old_cell:Vector2i=game.cell
 game.cell+=Vector2i(1,0)
 menu._process(1.0/60.0)
 check(not menu.running and menu.rolls==0,"changed location cancels before using prepared encounters")
 game.cell=old_cell
 menu.start_hunt()
 check(menu.running and menu.hunt_catalog.data.areas.size()==1 and menu.hunt_catalog.data.areas[0]==game.encounter_catalog.area_at(int(game.data.map_id),game.cell),"restart prepares current validated source area afresh")
 menu.close_menu()
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;await create_timer(0.2).timeout
 print("PET HUNT SPEED: %d failures"%failures)
 quit(1 if failures else 0)
