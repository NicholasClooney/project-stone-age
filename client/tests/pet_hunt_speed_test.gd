extends SceneTree
const Clock=preload("res://scripts/clock.gd")
const Wait=preload("res://tests/support/wait.gd")
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
 menu.open_menu();menu.auto_capture.button_pressed=false
 # This suite measures the ordinary GDScript scan; fast_hunt_flow_test covers 本机极速模式.
 menu.fast.button_pressed=false
 check(menu.rate.max_value>=5000 and menu.rate.value==0,"default is unlimited with explicit rates still supported")
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
 # Freeze automatic scan frames so each budget sample measures only its call;
 # backend clock flushing and normal on_status UI updates remain enabled.
 menu.set_process(false)
 var core=game.backend.automation
 check(not core.auto_tick,"local client drives scans while backend still flushes progress")
 var sample_started:=Time.get_ticks_usec()
 menu._process(1.0/60.0)
 var sample_usec:=Time.get_ticks_usec()-sample_started
 print("REAL SCAN: %d rolls, UI snapshot %d rolls, in %d usec; budget %d usec" % [core.hunt_rolls,menu.rolls,sample_usec,core.frame_budget(core.HUNT_FRAME_BUDGET_USEC)])
 check(core.hunt_rolls>0,"real encounter work runs under the frame budget")
 var before_stall:int=core.hunt_rolls
 menu._process(2.0)
 check(core.hunt_credit<=200.0 and core.hunt_rolls-before_stall<=201,"long stall retains at most 100ms of requested work")
 var progress_started:=Clock.ticks_msec()
 check(await Wait.until(self,func():return menu.rolls==core.hunt_rolls),"one-second progress publishes the real scan count")
 print("LOCAL PROGRESS FLUSH: core %d, UI %d, waited %d msec" % [core.hunt_rolls,menu.rolls,Clock.ticks_msec()-progress_started])
 check(menu.status.text.contains("目标 2000") and menu.status.text.contains("实际"),"requested and actual throughput are visible")
 menu.filter.rate=0;var before_unlimited:int=core.hunt_rolls
 # A CPU budget inside one frame: measured on the real clock, like the budget itself.
 sample_started=Time.get_ticks_usec()
 menu._process(1.0/60.0)
 sample_usec=Time.get_ticks_usec()-sample_started
 print("REAL UNLIMITED SCAN: %d additional rolls in %d usec; budget %d usec" % [core.hunt_rolls-before_unlimited,sample_usec,core.frame_budget(core.HUNT_FRAME_BUDGET_USEC)])
 check(sample_usec>=core.frame_budget(core.HUNT_FRAME_BUDGET_USEC),"unlimited real scan consumes the full frame budget")
 check(core.hunt_rolls>before_unlimited,"rate 0 scans for the whole frame budget without throttling")
 check(await Wait.until(self,func():return menu.rolls==core.hunt_rolls and int(menu._hunt().filter.rate)==0),"one-second progress publishes unlimited scan count and rate")
 check(menu.status.text.contains("不限速"),"unlimited throughput is visible")
 menu.stop_hunt("test")
 var before:int=core.hunt_rolls
 menu._process(1)
 check(core.hunt_rolls==before,"cancelled scan performs no more work")
 menu.start_hunt()
 var old_cell:Vector2i=game.cell
 game.cell+=Vector2i(1,0)
 menu._process(1.0/60.0)
 check(not menu.running and menu.rolls==0,"changed location cancels before using prepared encounters")
 game.cell=old_cell
 menu.start_hunt()
 check(menu.running and menu.hunt_catalog.data.areas.size()==1 and menu.hunt_catalog.data.areas[0]==game.encounter_catalog.area_at(int(game.data.map_id),game.cell),"restart prepares current validated source area afresh")
 menu.close_menu()
 menu.open_menu();menu.auto_capture.button_pressed=false
 check(menu.rate.value==2000,"reopening preserves chosen requested rate")
 menu.apply_preset(1)
 check(menu.total.value==4 and menu.min_offsets()==[-2,-2,-2,-2],"switching away from full quality removes individual +2 minima")
 menu.apply_preset(3)
 check(menu.total.value==8 and menu.min_offsets()==[2,2,2,2],"full-quality preset restores all four explicit +2 minima")
 menu.offsets[0].value=1
 menu.close_menu();menu.open_menu();menu.auto_capture.button_pressed=false
 check(menu.min_offsets()==[1,2,2,2] and menu.preset.selected==4,"reopening preserves customized thresholds")
 menu.close_menu()
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;await create_timer(0.2).timeout
 print("PET HUNT SPEED: %d failures"%failures)
 quit(1 if failures else 0)
