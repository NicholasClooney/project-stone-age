extends "res://tests/support/quest_auto_public25_support.gd"
## Explicit player walk back to Jaja after24, then a fresh manual25 start.
## Not continuous25 acceleration. No event/proof/position injection after24.
func run()->void:
 deadline=Clock.ticks_msec()+170000
 var b=fixture("B")
 var completed24:bool=await drive(b,"B",24)
 var returned:=false
 var completed25:=false
 if completed24:returned=await return_to_jaja(b)
 if returned:completed25=await drive(b,"B",25)
 check(completed24 and returned and completed25,"Actual24, player original exit/public walk, then independent25 all finish")
 check(Clock.ticks_msec()<deadline,"Independent public25 B remains inside condition budget")
 var output=FileAccess.open("user://public-corridors-public25-b-results.json",FileAccess.WRITE)
 if output!=null:
  output.store_string(JSON.stringify({"summaries":summaries,"actual24_portals":outbound_portals,"assertions":assertions,"failures":failures}))
  output.close()
 check(output!=null,"Retain independent public25 evidence separately from continuous25")
 b.free()
 print("QUEST AUTO PUBLIC CORRIDORS PUBLIC25 B: %d assertions, %d failures; wall_ms=%d"%[assertions,failures,Clock.ticks_msec()-began])
 quit(0 if failures==0 else 1)
