extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
const FIRE_FIXTURE="res://tests/fixtures/transmigration-fire-source.json"
func setup_fire():
 var b=fresh()
 var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FIRE_FIXTURE))
 # Pinned source fixture through the real catalog/transaction/backend, not
 # production descriptor activation and never invented arrival evidence.
 b.quest_catalog.npcs.append_array(source.npcs.duplicate(true))
 b.quest_catalog.items.merge(source.items)
 b.quest_catalog.enabled_events.append(40)
 return b
func npc(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==script:return n
 return {}
func battle_at(b,script:String,cell:Vector2i)->bool:
 var n: Dictionary=npc(b,script)
 var point: Vector2i=cell
 for delta in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
  var candidate: Vector2i=Vector2i(int(n.cell[0]),int(n.cell[1]))+delta
  if not Route.path(b,int(n.map_id),candidate,range(30001,30017)).is_empty():point=candidate;break
 var moved: Dictionary=Route.walk(b,int(n.map_id),point,range(30001,30017))
 check(moved.get("ok",false),"consecutive original cave route reaches "+script)
 if not moved.get("ok",false):return false
 var r: Dictionary=b.handle({"type":"quest_talk","npc_id":n.id})
 check(r.ok and choose(b,r,"yes").ok and b.battle_open,"actual source fixed battle "+script)
 if not b.battle_open:return false
 fight(b)
 check(b.handle({"type":"battle_close"}).ok,"real saved victory Warp "+script)
 return not b.battle_open
func run()->void:
 var b=setup_fire()
 var sage: Dictionary=npc(b,"giiru/event/sink/sink02")
 for script in ["giiru/event/sink/sink01","giiru/event/sink/sink02","giiru/event/sink/sink06","giiru/event/sink/sink044","giiru/event/sink/sink044a","giiru/event/sink/sink044b","giiru/event/sink/sink044c","giiru/event/sink/sink055","giiru/event/sink/sink055a"]:
  var n: Dictionary=npc(b,script)
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  for branch in n.branches:
   for raw in str(branch.get("actions",{}).get("NpcWarp","")).split(",",false):
    check(Policy.scope(int(raw.split(".")[0]))==Policy.scope(int(n.map_id)),"every actual mobile NPC destination remains in its reviewed scope")
   check(not b.quest_arrival.check_action(b,n,branch,"reward").is_empty(),"project arrival refuses source branch "+script)
 for id in [300,5106,30504]:check(Policy.scope(id).is_empty(),"public request/water/shop has no invented pilgrimage "+str(id))
 check(Policy.portal_root(200,20301) and not Policy.portal_root(20302,20306),"public phoenix entrance allowed but interior portal cannot create root")
 check(Route.complete_adult(b).get("ok",false),"actual adult prerequisite")
 b.automation.position_changed(5106,Vector2i(26,16))
 var request: Dictionary=b.handle({"type":"quest_talk","npc_id":npc(b,"giiru/event/sink/sink07").id})
 check(choose(b,request,"yes").ok and Rules.flag(b.session.snapshot(),"now",40),"public village actual REQUEST40 without cave qualification")
 var gate: Dictionary=npc(b,"genout/wpm_30502_45_41")
 b.automation.position_changed(30502,Vector2i(45,42))
 var r: Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
 b.save_path="user://missing-fire-arrival/save.json"
 check(not choose(b,r,"yes").ok and not b.quest_arrival.has_arrival(b,30001,Vector2i(29,14)),"failed gate save grants no cave arrival")
 b.save_path="";r=b.handle({"type":"quest_talk","npc_id":gate.id})
 check(choose(b,r,"yes").ok and b.quest_arrival.has_arrival(b,30001,Vector2i(29,14)),"actual adult-level FREEWARP grants first route")
 if not battle_at(b,"300/sb_hba7.arg",Vector2i(16,12)):b.free();quit(1);return
 check(Route.walk(b,30016,Vector2i(26,67),range(30001,30017)).ok,"original 30008 portal reaches final guard front")
 check(not b.quest_arrival.check_action(b,sage,sage.branches[0],"reward").is_empty(),"30016 prebattle arrival is not Ira eligibility")
 if not battle_at(b,"300/sb_hpa.arg",Vector2i(26,67)):b.free();quit(1);return
 check(b.automation.position_cell==Vector2i(26,63) and b.quest_arrival.check_action(b,sage,sage.branches[0],"reward").is_empty(),"source hpa Warp26,63 grants reward component")
 check(Route.walk(b,30016,Vector2i(26,32),[30016]).ok,"actual reward component connects landing to Ira")
 for n in b.quest_catalog.active_npcs():
  if Policy.source(n)=="giiru/event/sink/sink06":
   for branch in n.branches:check(b.quest_arrival.check_action(b,n,branch,"reward").is_empty(),"seven reward pools share legitimate final component")
 b.automation.position_changed(30016,Vector2i(26,33))
 check(not b.quest_arrival.check_action(b,sage,sage.branches[0],"reward").is_empty(),"same-component project movement revokes final proof")
 b.free();print("QUEST ARRIVAL FIRE: %d failures"%failures);quit(1 if failures else 0)
