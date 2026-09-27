extends SceneTree
# Manual 60Hz wall-clock pacing; no graphics, no save files. Test-only impossible
# quality cutoff prevents hits but exercises the real RNG, troops and quality scan.
func _initialize():call_deferred("run")
func percentile(samples:Array,q:float)->float:
 var ordered:=samples.duplicate();ordered.sort()
 return float(ordered[mini(ordered.size()-1,int(ceil(ordered.size()*q))-1)])/1000.0
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game)
 await process_frame
 game.random_encounters=false
 var output:={"engine":Engine.get_version_info().string,"pacing_hz":60,"seconds_per_sample":2,"repetitions":3,"note":"Headless manual 60Hz wall-clock pacing, no render cost. Impossible test-only total9 avoids early matching; real troop RNG and actor filtering unchanged.","samples":[]}
 for fixture in [{"name":"samgir","map":100,"cell":Vector2i(637,493)},{"name":"giru","map":300,"cell":Vector2i(509,93)}]:
  game.load_area_id(fixture.map,fixture.cell)
  var menu=game.pet_hunt_menu
  menu.open_menu();menu.set_process(false)
  for target in [500,1000,1500,2000]:
   for repetition in range(3):
    game.encounter_rng.seed=7834+repetition
    menu.rate.value=target;menu.start_hunt()
    if not menu.running:
     push_error("Benchmark fixture unavailable: "+str(fixture));quit(1);return
    menu.filter.total=9;menu.filter.level_one=false
    # Warm up real generation and dictionary/resource caches before measurement.
    for i in range(30):menu._process(1.0/60.0)
    menu.rolls=0;menu.inspected=0;menu.credit=0;menu.started_usec=Time.get_ticks_usec()
    var started:=Time.get_ticks_usec()
    var previous:=started
    var frame:=0
    var costs:=[]
    while Time.get_ticks_usec()-started<2000000:
     var now:=Time.get_ticks_usec()
     menu._process((now-previous)/1000000.0)
     costs.append(Time.get_ticks_usec()-now);previous=now;frame+=1
     var wait:=started+int(frame*1000000.0/60.0)-Time.get_ticks_usec()
     if wait>0:OS.delay_usec(wait)
    var seconds:float=(Time.get_ticks_usec()-started)/1000000.0
    var stop_start:=Time.get_ticks_usec();menu.stop_hunt("benchmark")
    var stop_usec:=Time.get_ticks_usec()-stop_start
    var record:={"workload":fixture.name,"requested":target,"repetition":repetition+1,"groups":menu.rolls,"actors_inspected":menu.inspected,"seconds":seconds,"achieved":menu.rolls/seconds,"p50_ms":percentile(costs,0.5),"p95_ms":percentile(costs,0.95),"p99_ms":percentile(costs,0.99),"max_ms":costs.max()/1000.0,"stop_ms":stop_usec/1000.0}
    output.samples.append(record);print(JSON.stringify(record))
  menu.close_menu()
 var file=FileAccess.open("/tmp/stone-age-pet-hunt-benchmark.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(output,"  "));file.close()
 game.process_mode=Node.PROCESS_MODE_DISABLED;game.music.stop();game.effect.stop();game.queue_free()
 await process_frame;quit()
