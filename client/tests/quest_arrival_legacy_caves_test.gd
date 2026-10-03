extends "res://tests/brothers_golden_quests_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Policy=preload("res://server/quest_arrival_policy.gd")
func run()->void:
 var b=fresh()
 var cases: Array=[
  [200,20101,20105,"jaruga/event/event01_2"],
  [200,20401,20406,"jaruga/event/event07_2@20406:36:34"],
  [200,20501,20508,"jaruga/event/20501ev1"],
  [100,11001,11006,"sainasu/event/event15_1"],
  [100,10701,10705,"100/sb_nusu3.arg@10705:44:41"],
  [300,31801,31806,"giiru/event/giruev2_1@31805:19:21"],
 ]
 for row in cases:
  var n: Dictionary=b.original_quests.npc_by_id(str(row[3]))
  var maps: Array=range(int(row[1]),int(row[2])+1)
  var count: int=0
  for resident in b.quest_catalog.active_npcs():
   if int(resident.map_id) not in maps:continue
   b.automation.position_changed(int(resident.map_id),Vector2i(int(resident.cell[0])+1,int(resident.cell[1])))
   for branch in resident.get("branches",[]):
    if str(branch.type) in ["CLEAN","MESSAGE"] and branch.get("actions",{}).is_empty():continue
    var before: Dictionary=b.session.snapshot()
    var denied: Dictionary=b.original_quests.transact(b,before,branch,"reward","",str(resident.id))
    check(not denied.ok and str(denied.get("reason","")).begins_with("项目补充") and b.session.snapshot()==before,"final transaction rejects project source "+str(resident.id)+"/"+str(branch.type))
    count+=1
  check(count>0,"case has actual protected action branches "+str(row[1]))
  var entrance: Dictionary={}
  for link in b.quest_helper.places.links(int(row[0])).values():
   if int(link.to_map)==int(row[1]) and not link.has("gate_source") and not bool(link.get("disabled",false)):entrance=link;break
  check(not entrance.is_empty(),"reviewed original public entrance exists "+str(row[1]))
  if entrance.is_empty():continue
  b.automation.position_changed(int(row[0]),Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
  check(b.handle({"type":"report_position","map_id":int(row[1]),"cell":entrance.target}).ok and b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"exact original entrance starts independent cave route")
  if int(row[1])==20101:
   # Preexisting public request is a fixture, never an arrival grant. The
   # driver must cross all five real maps before the actual doctor exchange.
   Rules.set_flag(b.session._profile,"now",1,true)
   check(Route.exchange_from_route(b,str(n.id),maps).get("ok",false) and 2401 in b.session.snapshot().original_items,"tightened helper pure geometry supports real five-floor exchange")
  var reached: bool=false
  for delta in [Vector2i.UP,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.DOWN]:
   var point: Vector2i=Vector2i(int(n.cell[0]),int(n.cell[1]))+delta
   if not Route.path(b,int(n.map_id),point,maps).is_empty():
    reached=Route.walk(b,int(n.map_id),point,maps).get("ok",false);break
  check(reached and b.quest_arrival.check_action(b,n,n.branches[0],"reward").is_empty(),"actual collision/portal path reaches original deep terminal "+str(n.id))
  # A project placement on an interior door cannot become a new root.
  var internal: Dictionary={}
  for link in b.quest_helper.places.links(int(row[1])).values():
   if int(link.to_map) in maps and not link.has("gate_source") and not bool(link.get("disabled",false)):internal=link;break
  if not internal.is_empty():
   b.automation.position_changed(int(row[1]),Vector2i(int(internal.cell[0]),int(internal.cell[1])))
   b.handle({"type":"report_position","map_id":int(internal.to_map),"cell":internal.target})
   check(not b.quest_arrival.has_arrival(b,b.automation.position_map,b.automation.position_cell),"interior original portal cannot launder project arrival")
 for map_id in [1000,2000,3000,3110,1300,1400,1112,30600,6000,100,200,300,400]:
  check(Policy.scope(map_id).is_empty(),"public village return and field reward keeps source conditions "+str(map_id))
 b.free();print("QUEST ARRIVAL LEGACY CAVES: %d failures"%failures);quit(1 if failures else 0)
