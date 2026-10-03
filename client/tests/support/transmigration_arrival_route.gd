extends RefCounted
## Isolated original catalog/mapwarp fixtures; no route/stage/mark grants.
const Route=preload("res://tests/support/original_route_driver.gd")
const Interaction=preload("res://scripts/npc_interaction.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
static func install(b, portal_fixture:bool=true)->void:
 var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json"))
 var ids:Array=source.npcs.map(func(n):return str(n.id))
 b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id) not in ids)
 b.quest_catalog.npcs.append_array(source.npcs)
 b.quest_catalog.items.merge(source.items,true)
 for event in [48,49,50,51,52]:
  if event not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(event)
 b.quest_helper.places.set_quest_catalog(b.quest_catalog)
 if not portal_fixture:return
 var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-arrival-portals.json"))
 # The basic cave fixture does not add public prison endpoints; dedicated
 # prison tests use the actual imported world with portal_fixture=false.
 for p in oracle.portals:
  if int(p.to_map)==117:continue
  var key:=str(int(p.from_map))
  if not b.quest_helper.places.portals.has(key):b.quest_helper.places.portals[key]={}
  b.quest_helper.places.portals[key][Vector2i(int(p.cell[0]),int(p.cell[1]))]=p.duplicate(true)
static func npc(b,script:String)->Dictionary:return Travel.npc(b,script)
static func commit(b,script:String)->bool:return Travel.commit(b,npc(b,script))
static func near(b,script:String,maps:Array)->bool:
 var n:=npc(b,script)
 if n.is_empty():return false
 for delta in Interaction.offsets():
  if Route.walk(b,int(n.map_id),Vector2i(int(n.cell[0]),int(n.cell[1]))+delta,maps).get("ok",false):return true
 return false
static func entry(b)->bool:
 # Only the publicly accessible outside position is a fixture.
 b.automation.position_changed(300,Vector2i(102,228))
 if not commit(b,"genout/wpm_300_103_228"):return false
 if not near(b,"genout/wpm_300_108_225",[300]):return false
 return commit(b,"genout/wpm_300_108_225")
