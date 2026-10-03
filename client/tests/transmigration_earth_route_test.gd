extends "res://tests/golden_bui_route_test.gd"
## Natural collision walking and original doors, with no synthetic cave visits.
func source(b,script:String)->Dictionary:
 for n in b.quest_catalog.active_npcs():
  if str(n.get("source_script",""))==script:return n
 return {}
func outside_trade(b,script:String)->Dictionary:
 var n:=source(b,script)
 check(b.handle({"type":"quest_visit","npc_id":n.id,"mode":"near"}).ok,"surface helper convenience")
 return trade(b,n.id)
func run()->void:
 var b=fresh(80);b.save_path=""
 complete_core_route(b)
 # Returning along original doors permits the optional original feather route.
 check(portal(b,21014),"original goddess return stair")
 for next in range(21013,21001,-1):
  if b.automation.position_map==21009:check(portal(b,21009),"source stone-bed returns to other bank")
  if not portal(b,next):break
 check(b.automation.position_map==21002,"natural return reaches second-floor feather region")
 if b.automation.position_map==21002:
  check(walk(b,Vector2i(10,10)),"walk to original diary-conditioned area436")
  check(earn_feather(b),"natural source random encounters earn feather after diary consumed")
 b.free()
 print("TRANSMIGRATION EARTH NATURAL ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
func complete_core_route(b)->void:
 Rules.set_flag(b.session._profile,"ended",4,true)
 check(outside_trade(b,"jaruga/event/ruri02").ok,"original request and necklace before full route")
 check(outside_trade(b,"jaruga/event/ruri03").ok,"bound original son diary")
 var gate:=source(b,"genout/wpm_200_359_671")
 check(b.handle({"type":"quest_visit","npc_id":gate.id,"mode":"near"}).ok,"surface entrance approach")
 check(trade(b,gate.id).ok and b.automation.position_map==21001,"original level65+END4 gate enters first floor")
 var reached:Array=[21001]
 for next in range(21002,21015):
  if b.automation.position_map==21003:
   gate=source(b,"genout/wpm_21003_34_10")
   check(trade(b,gate.id).ok and b.automation.position_cell==Vector2i(34,7),"natural approach and source judgement warp")
  if b.automation.position_map==21009:
   var guard:=source(b,"200/sb_dtp.arg")
   check(trade(b,guard.id).ok and b.battle_open,"natural nine-floor guard encounter")
   fight(b);check(b.handle({"type":"battle_close"}).ok,"nine-floor real battle settlement")
  if not portal(b,next):break
  reached.append(next)
 check(reached==range(21001,21015),"all fourteen cave floors reached on collision paths and source doors")
 var final_guard:=source(b,"200/sb_dbt.arg")
 check(trade(b,final_guard.id).ok and b.battle_open,"natural final ten-enemy guard")
 fight(b);check(b.handle({"type":"battle_close"}).ok and b.automation.position_map==21015,"final victory arrives at original goddess landing")
 check(trade(b,source(b,"jaruga/event/ruri01").id).ok and Rules.flag(b.session.snapshot(),"ended",39),"natural full core delivers both source materials")

func earn_feather(b)->bool:
 var origin:Vector2i=b.automation.position_cell
 # Both cells are checked once; repeated encounter steps remain adjacent real
 # report_position commands and do not need to reload/BFS the entire map.
 var data:Dictionary=MapFile.load_map(b.session.world_catalog.file(21002))
 var other:=origin+Vector2i.RIGHT
 if not check(int(data.blocked[other.y*int(data.width)+other.x])==0 and not b.session.world_catalog.links(21002).has(other),"adjacent source encounter cell is walkable and not a portal"):return false
 for attempt in range(100):
  for step in range(1000):
   var cell:=origin+Vector2i.RIGHT if step%2==0 else origin
   if not b.handle({"type":"report_position","map_id":21002,"cell":[cell.x,cell.y]}).get("ok",false):return false
   b.handle({"type":"field_step","map_id":21002,"cell":[cell.x,cell.y],"encounter":true})
   if b.battle_open:break
  if not check(b.battle_open,"original random encounter via field steps"):return false
  fight(b)
  if not check(b.handle({"type":"battle_close"}).ok,"random battle closes through authority"):return false
  if Rules.item_count(b.session.snapshot(),2700)>0:return true
 return false

func walk(b, target: Vector2i, report_missing := true) -> bool:
 var map_id: int = b.automation.position_map
 var data := MapFile.load_map(b.session.world_catalog.file(map_id))
 if not check(not data.is_empty(),"Real original map loaded %d"%map_id):return false
 var start: Vector2i = b.automation.position_cell
 var queue: Array[Vector2i] = [start]
 var prior := {start:start}
 var doors: Dictionary = b.session.world_catalog.links(map_id)
 var occupied:Dictionary={}
 for n in b.quest_catalog.active_npcs():
  if int(n.map_id)==map_id:occupied[Vector2i(int(n.cell[0]),int(n.cell[1]))]=true
 for n in b.session.world_catalog.residents:
  if int(n.map_id)==map_id:occupied[Vector2i(int(n.cell[0]),int(n.cell[1]))]=true
 while not queue.is_empty() and not prior.has(target):
  var cell: Vector2i = queue.pop_front()
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next: Vector2i = cell+offset
   if next.x<0 or next.y<0 or next.x>=int(data.width) or next.y>=int(data.height) or prior.has(next):continue
   if int(data.blocked[next.y*int(data.width)+next.x])!=0 or int(data.ground[next.y*int(data.width)+next.x])==0 or occupied.has(next):continue
   if doors.has(next) and next!=target:continue
   prior[next]=cell
   queue.append(next)
 if not prior.has(target):
  if report_missing:check(false,"Natural collision path %d %s→%s"%[map_id,start,target])
  return false
 var path: Array[Vector2i] = []
 var cursor := target
 while cursor!=start:
  path.push_front(cursor)
  cursor=prior[cursor]
 for cell in path:
  if not check(b.handle({"type":"report_position","map_id":map_id,"cell":[cell.x,cell.y]}).ok,"Real session step report"):return false
 return true
