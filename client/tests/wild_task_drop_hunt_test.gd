extends "res://tests/wild_task_drop_test.gd"
const Fast=preload("res://server/fast_hunt.gd")
func run()->void:
 Fast.threads=1
 check(Fast.available(),"actual native helper available")
 for native in [false,true]:
  var b=fresh();strong(b);mine(b,false);root.add_child(b)
  var found:=false;var native_seen:=[false]
  for attempt in range(40):
   var r:Dictionary=b.handle({"type":"auto_start","kind":"hunt","map_id":31801,"cell":[37,48],"filter":{"templates":[181,184],"level_one":false,"clean_only":false,"total":-8,"offsets":[-2,-2,-2,-2],"auto_capture":false,"fast":native,"rate":0}})
   check(r.ok,"ordinary pet hunt starts at server point")
   if not r.ok:break
   var ended:bool=await Wait.until(self,func():
    if native:
     b.automation._fast_process()
     native_seen[0]=bool(native_seen[0]) or b.automation.fast_hunt.running()
    else:b.automation.scan_once()
    return b.battle_open or not b.automation.hunt_running,90.0)
   # Native can start and finish during one poll; recorded helper launch fields
   # and absence of fallback establish which search path was actually used.
   check(ended and b.battle_open,"real scan/replay opens its actual selected troop")
   if not b.battle_open:break
   found=b.session._pending.has("wild_drop_receipt")
   finish(b);check(b.handle({"type":"battle_close"}).ok,"hunt battle normal result closes")
   if found:break
  check(found and b.session.snapshot().original_items.count(2534)==0,"slow/native mixed hunt cannot award ore without route")
  if native:check(bool(native_seen[0]) and b.automation.hunt_fast_note.is_empty(),"native source search actually ran without fallback")
  b.free()
 await queue_capture()
 print("WILD TASK DROP HUNT: %d failures"%failures);quit(1 if failures else 0)

func queue_capture()->void:
 var b=fresh();strong(b);mine(b,false);root.add_child(b)
 var r:Dictionary=b.handle({"type":"auto_start","kind":"find_pet","map_id":31801,"cell":[37,48],"filter":{"templates":[181,184],"level_one":false,"clean_only":false,"total":-8,"offsets":[-2,-2,-2,-2],"fast":true,"background_search":true,"show_battles":true},"settings":{"capture_hp":100}})
 check(r.ok,"real queue workflow begins")
 if not r.ok:b.free();return
 check(await Wait.until(self,func():b.automation._fast_process();return not b.automation.showcase_queue.is_empty() or not b.automation.hunt_running,90.0),"native queue receives real replayed candidates")
 var matched:=false
 for entry in b.automation.showcase_queue:
  if entry.troop.enemies.any(func(e):return int(e.get("source_enemy_id",0))==1043):matched=true;break
 check(matched,"real queued troops include original protected ore slot")
 b.automation.stop_hunt("test pauses search while consuming real queued hit")
 for attempt in range(30):
  if b.automation.showcase_queue.is_empty():break
  b.automation._showcase_capture()
  if not b.battle_open:continue
  var protected:bool=b.session._pending.has("wild_drop_receipt")
  finish(b);check(b.handle({"type":"battle_close"}).ok,"queued real battle closes normally")
  if protected:
   check(b.session.snapshot().original_items.count(2534)==0 and b.battle_state.has("quest_drop_denied"),"queue replay cannot inherit task loot permission from hunt target")
   matched=true;break
  matched=false
 check(matched,"queue consumption actually exercised protected result")
 b.automation.stop_cycle("test complete");b.free()
