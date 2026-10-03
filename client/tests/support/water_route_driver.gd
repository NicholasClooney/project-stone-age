extends RefCounted
## Test-only travel driver: actual report_position steps, original gate commands,
## real battles. No arrival receipt, scope, mark, or internal grant is written.
const Route=preload("res://tests/support/original_route_driver.gd")
const Interaction=preload("res://scripts/npc_interaction.gd")
static func install_fixture(b)->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-water-source.json"))
 var ids:Array=fixture.npcs.map(func(value):return str(value.id))
 b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(value):return str(value.id) not in ids)
 b.quest_catalog.npcs.append_array(fixture.npcs)
 b.quest_catalog.items.merge(fixture.items,true)
 if 46 not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(46)
 b.quest_helper.places.set_quest_catalog(b.quest_catalog)
 b.quest_helper.cached_key=""
static func npc(b,script:String)->Dictionary:
 for value in b.quest_catalog.active_npcs():
  if str(value.get("source_script",""))==script:return value
 return {}
static func walk_near(b,target:Dictionary,maps:Array)->bool:
 if target.is_empty():return false
 var start:int=b.automation.position_map;var goal:int=target.map_id
 if start not in maps or goal not in maps:return false
 var queue:Array=[start];var parents:Dictionary={start:start};var cursor:=0
 while cursor<queue.size() and not parents.has(goal):
  var origin:int=queue[cursor];cursor+=1
  for link in b.quest_helper.places.links(origin).values():
   var next:int=link.to_map
   if next in maps and not parents.has(next):parents[next]=origin;queue.append(next)
 if not parents.has(goal):return false
 var route:Array=[];var point:=goal
 while point!=start:route.push_front(point);point=int(parents[point])
 for next in route:
  var crossed:=false;var origin:int=b.automation.position_map
  for link in b.quest_helper.places.links(origin).values():
   if int(link.to_map)!=int(next) or link.has("gate_source") or link.get("disabled",false):continue
   var cell:=Vector2i(int(link.cell[0]),int(link.cell[1]))
   if not Route.walk(b,origin,cell,[origin]).get("ok",false):continue
   if not b.handle({"type":"report_position","map_id":int(next),"cell":link.target}).get("ok",false):return false
   crossed=true;break
  if not crossed:return false
 var cell:=Vector2i(int(target.cell[0]),int(target.cell[1]))
 for offset in Interaction.offsets():
  if Route.walk(b,goal,cell+offset,[goal]).get("ok",false):return true
 return false
static func commit(b,target:Dictionary)->bool:
 var result:Dictionary=b.handle({"type":"quest_talk","npc_id":target.id})
 if not result.get("ok",false):return false
 result=b.handle({"type":"quest_choose","token":result.get("dialogue",{}).get("token",""),"choice":"yes"})
 if result.has("dialogue"):result=b.handle({"type":"quest_choose","token":result.dialogue.token,"choice":"ok"})
 return bool(result.get("ok",false))
static func guard(b,script:String,maps:Array)->bool:
 print("WATER DRIVER guard ",script)
 var target:=npc(b,script)
 if not walk_near(b,target,maps) or not commit(b,target) or not b.battle_open:return false
 for i in range(100):
  var state:Dictionary=b.battle.snapshot()
  if not state.active:break
  var target_index:=0
  for j in range(state.enemies.size()):
   if int(state.enemies[j].hp)>0:target_index=j;break
  b.handle({"type":"battle_command","action":"attack","target":target_index})
 var closed:Dictionary=b.handle({"type":"battle_close"})
 return closed.get("ok",false) and closed.get("outcome","")=="win"
static func cave(b,script:String)->bool:
 var target:=npc(b,script)
 var maps:Array=range(21201,21216)+range(21301,21316)
 if b.automation.position_map in maps and b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell):
  if walk_near(b,target,maps):return true
 # Explicit public approach fixture; every protected interior step is real.
 b.original_quests.pending={}
 b.automation.position_changed(200,Vector2i(74,696))
 if not commit(b,npc(b,"genout/wpm_200_73_696")):return false
 if script=="200/sb_mzl.arg":return walk_near(b,target,range(21201,21209))
 if not guard(b,"200/sb_mzl.arg",range(21201,21209)):return false
 if script=="200/sb_mzn.arg":return walk_near(b,target,range(21208,21215))
 if not guard(b,"200/sb_mzn.arg",range(21208,21215)):return false
 if script in ["genout/wpm_21308_20_10","jaruga/event/hekisei03"]:
  var door:=npc(b,"genout/wpm_21308_20_10")
  if not walk_near(b,door,[21215]+range(21308,21316)):return false
  if script=="genout/wpm_21308_20_10":return true
  if not commit(b,door):return false
 return walk_near(b,target,[int(target.map_id)])
static func lake(b,free_entry:bool)->bool:
 b.original_quests.pending={}
 if free_entry:
  b.automation.position_changed(5000,Vector2i(46,19))
  if not b.handle({"type":"report_position","map_id":5000,"cell":[46,18]}).get("ok",false):return false
  if not b.handle({"type":"report_position","map_id":31301,"cell":[10,10]}).get("ok",false):return false
 else:
  b.automation.position_changed(40,Vector2i(13,2))
  if not commit(b,npc(b,"genout/wpm_40_13_1")):return false
 return walk_near(b,npc(b,"jaruga/event/hekisei04"),[31301,31302])
