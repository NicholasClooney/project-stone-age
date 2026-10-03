extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
func source_npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==script:return n
 return {}
func converse(b,n:Dictionary)->Dictionary:
 var r: Dictionary=b.handle({"type":"quest_talk","npc_id":n.id})
 for i in range(3):
  if not r.get("ok",false) or not r.has("dialogue"):return r
  var phase: String=str(b.original_quests.pending.get("phase",""))
  r=choose(b,r,"ok" if phase in ["reward","end"] else "yes")
 return r
func walk_to(b,n:Dictionary)->bool:
 for delta in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
  var point: Vector2i=Vector2i(int(n.cell[0]),int(n.cell[1]))+delta
  if not Route.path(b,int(n.map_id),point,range(21001,21017)).is_empty():return Route.walk(b,int(n.map_id),point,range(21001,21017)).get("ok",false)
 return false
func run()->void:
 var b=fresh()
 var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-earth-source.json"))
 b.quest_catalog.npcs.append_array(fixture.npcs.duplicate(true));b.quest_catalog.items.merge(fixture.items);b.quest_catalog.enabled_events.append(39)
 check(Policy.scope(3413).is_empty() and Policy.scope(200).is_empty(),"public earth request and moving diary have no cave pilgrimage")
 for script in ["jaruga/event/ruri01","jaruga/event/ruri05","jaruga/event/ruri06"]:
  var n: Dictionary=source_npc(b,script)
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  check(not b.handle({"type":"quest_talk","npc_id":n.id}).ok,"project arrival denies actual goddess/bag dialogue "+script)
 check(Route.complete_adult(b).get("ok",false),"real adult prerequisite")
 for script in ["jaruga/event/ruri02","jaruga/event/ruri03"]:
  var n: Dictionary=source_npc(b,script)
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  check(converse(b,n).get("ok",false),"public source request/material "+script)
 check(Rules.flag(b.session.snapshot(),"now",39) and 2698 in b.session.snapshot().original_items and 2699 in b.session.snapshot().original_items,"actual source gives both core materials")
 var gate: Dictionary=source_npc(b,"genout/wpm_200_359_671")
 b.automation.position_changed(200,Vector2i(359,672))
 check(converse(b,gate).get("ok",false) and b.quest_arrival.has_arrival(b,21001,Vector2i(4,3)),"original external adult-level gate starts earth route")
 gate=source_npc(b,"genout/wpm_21003_34_10")
 check(walk_to(b,gate),"two source floors reach original OR door")
 check(converse(b,gate).get("ok",false) and b.automation.position_cell==Vector2i(34,7),"original NOW39 OR branch opens without invented feather requirement")
 var guard: Dictionary=source_npc(b,"200/sb_dbt.arg")
 var reached: bool=walk_to(b,guard)
 if not reached:
  var middle: Dictionary=source_npc(b,"200/sb_dtp.arg")
  check(walk_to(b,middle),"physical route reaches intermediate source guard")
  var mid: Dictionary=b.handle({"type":"quest_talk","npc_id":middle.id})
  check(mid.ok and choose(b,mid,"yes").ok and b.battle_open,"actual intermediate guard opens when this geometry needs its crossing")
  if b.battle_open:
   fight(b);check(b.handle({"type":"battle_close"}).ok,"actual intermediate guard victory crossing")
   reached=walk_to(b,guard)
 check(reached,"actual portals reach final guard; policy does not impose a separate global dtp mark")
 var r: Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
 check(r.ok and choose(b,r,"yes").ok and b.battle_open,"real dbt fixed battle starts")
 if not b.battle_open:b.free();quit(1);return
 fight(b);check(b.handle({"type":"battle_close"}).ok and b.automation.position_map==21015,"real saved dbt Warp enters goddess floor")
 var goddess: Dictionary=source_npc(b,"jaruga/event/ruri01")
 check(walk_to(b,goddess),"real reward component reaches goddess")
 for script in ["jaruga/event/ruri05","jaruga/event/ruri06"]:
  var n: Dictionary=source_npc(b,script)
  check(b.quest_arrival.check_action(b,n,n.branches[0],"reward").is_empty(),"both original bags use same legitimate victory region without new NOW/END predicates")
 var before: Dictionary=b.session.snapshot()
 b.save_path="user://missing-earth-arrival/save.json"
 check(not converse(b,goddess).get("ok",false) and b.session.snapshot()==before,"final core save failure preserves source materials and flags")
 b.save_path=""
 check(converse(b,goddess).get("ok",false) and Rules.flag(b.session.snapshot(),"ended",39) and 2701 in b.session.snapshot().original_items,"actual final core transaction retries and completes END39")
 var old: Vector2i=b.automation.position_cell
 b.automation.position_changed(21015,old+Vector2i.RIGHT)
 check(not b.quest_arrival.check_action(b,goddess,goddess.branches[0],"reward").is_empty(),"project movement cannot retain old goddess proof")
 b.free();print("QUEST ARRIVAL EARTH: %d failures"%failures);quit(1 if failures else 0)
