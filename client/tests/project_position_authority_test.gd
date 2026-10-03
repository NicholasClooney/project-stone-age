extends "res://tests/quest_arrival_backend_test.gd"
func run()->void:
 var old:Callable=WorldClock.clock;WorldClock.clock=func():return WorldClock.ERA+100
 var b=fresh()
 enter_route(b)
 var before:Vector2i=b.automation.position_cell
 var r:Dictionary=b.handle({"type":"project_position","map_id":41,"cell":[34,35],"quest_position_seq":1,"grant":true,"client":"party"})
 check(not r.ok and b.automation.position_cell==before and b.quest_arrival.has_arrival(b,41,before),"project command cannot cross guard or invalidate route on refusal")
 r=b.handle({"type":"project_position","map_id":41,"cell":[35,42],"kind":"walk","party":true})
 check(r.ok and b.automation.position_cell==Vector2i(35,42),"legal same-room project move updates authority")
 check(not b.quest_arrival.has_arrival(b,41,Vector2i(35,42)),"even adjacent project movement cannot claim original walking source")
 check(not b.handle({"type":"auto_start","kind":"hunt","map_id":41,"cell":[34,35]}).ok,"old client cannot start hunt at fabricated unsynchronized position")
 for cell in [[-1,2],[99999,2],[34,41]]:
  check(not b.handle({"type":"project_position","map_id":41,"cell":cell}).ok and b.automation.position_cell==Vector2i(35,42),"invalid bounds or occupied NPC cell leaves authority unchanged")
 check(not b.handle({"type":"project_position","map_id":42,"cell":[35,42]}).ok,"ordinary same-map command cannot switch maps")
 b.free();WorldClock.clock=old
 print("PROJECT POSITION AUTHORITY: %d failures"%failures);quit(1 if failures else 0)
