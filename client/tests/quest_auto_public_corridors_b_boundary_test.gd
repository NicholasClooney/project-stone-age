extends "res://tests/quest_auto_public_corridors_execution_test.gd"
## Register this B-only entry, never the uncontrolled A/C diagnostic base.
func run()->void:
 deadline=Clock.ticks_msec()+50000
 var result:Dictionary=await route("B")
 check(not result.is_empty(),"Actual B boundary route returned evidence")
 check(in_time(),"B boundary finishes inside condition deadline")
 var output=FileAccess.open("user://public-corridors-b-boundary-results.json",FileAccess.WRITE)
 if output!=null:
  output.store_string(JSON.stringify({"result":result,"assertions":assertions,"failures":failures}))
  output.close()
 check(output!=null,"Retain full B-only boundary evidence")
 print("QUEST AUTO PUBLIC CORRIDORS B BOUNDARY: %d assertions, %d failures; wall_ms=%d"%[assertions,failures,Clock.ticks_msec()-suite_started])
 quit(0 if failures==0 else 1)
