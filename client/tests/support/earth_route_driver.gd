extends RefCounted
## Source-route test support. Never writes arrival scopes, marks or receipts.
const Route=preload("res://tests/support/original_route_driver.gd")
static func npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==script:return n
 return {}
static func path_to(b,n:Dictionary)->Array:
 var target:=Vector2i(int(n.cell[0]),int(n.cell[1]))
 for delta in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
  var goal:Vector2i=target+delta
  if b.automation.position_map==int(n.map_id) and b.automation.position_cell==goal:return [{"map_id":n.map_id,"cell":[goal.x,goal.y]}]
  var route:Array=Route.path(b,int(n.map_id),goal,range(21001,21017))
  if not route.is_empty():return route
 return []
static func approach(b,n:Dictionary)->bool:
 var route:Array=path_to(b,n)
 if route.is_empty():return false
 for step in route:
  if not b.handle({"type":"report_position","map_id":step.map_id,"cell":step.cell,"client":"earth-original-route"}).get("ok",false):return false
 return true
static func converse(b,n:Dictionary)->Dictionary:
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":n.id})
 for i in range(3):
  if not r.get("ok",false) or not r.has("dialogue"):return r
  var phase:String=str(b.original_quests.pending.get("phase",""))
  r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"ok" if phase in ["reward","end"] else "yes"})
 return r
static func reach_goddess(b,test)->bool:
 var gate:Dictionary=npc(b,"genout/wpm_200_359_671")
 b.automation.position_changed(200,Vector2i(359,672)) # Public surface only.
 if not converse(b,gate).get("ok",false):return false
 gate=npc(b,"genout/wpm_21003_34_10")
 if not approach(b,gate) or not converse(b,gate).get("ok",false):return false
 for script in ["200/sb_dtp.arg","200/sb_dbt.arg"]:
  var guard:Dictionary=npc(b,script)
  if not approach(b,guard):return false
  var r:Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
  if not r.get("ok",false):return false
  if not b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"yes"}).get("ok",false) or not b.battle_open:return false
  if test.has_method("earth_guard"):test.earth_guard(b,guard)
  else:
   test.fight(b)
   if not b.handle({"type":"battle_close"}).get("ok",false):return false
 return b.automation.position_map==21015 and b.quest_arrival.has_arrival(b,21015,b.automation.position_cell)
