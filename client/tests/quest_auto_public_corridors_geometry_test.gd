extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Candidate audit only: no production whitelist changes or executor claims.
## Reads actual imported maps; prints each accepted/rejected directional lane.
const Backend=preload("res://server/backend.gd")
const Navigation=preload("res://server/quest_auto_navigation.gd")
const Arrival=preload("res://server/quest_arrival_policy.gd")
const DATA:="res://tests/fixtures/quest-auto-public-corridor-candidates.json"
var failures:=0
var assertions:=0
var accepted:Array=[]
var rejected:Array=[]
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func point(value:Array)->Vector2i:return Vector2i(int(value[0]),int(value[1]))
func same_link(actual:Dictionary,expected:Dictionary)->bool:
 if actual.size()!=expected.size():return false
 for field in expected:
  if not actual.has(field):return false
  if field in ["from_map","to_map"]:
   if float(actual[field])!=float(expected[field]):return false
  elif actual[field]!=expected[field]:return false
 return true
func public_candidate(nav,b,map_id:int,cell:Vector2i,occupied:Dictionary)->bool:
 # A necessary geometric predicate, NOT acceleration authorization.
 if not Arrival.scope(map_id).is_empty():return false
 if map_id in [10201,10202,10203,120,121]:return false
 if Arrival.approach_cell("transmigration_entry",map_id,cell):return false
 # Keep both original outdoor gate actors and the exit lip out as well.
 if map_id==300 and cell in [Vector2i(103,228),Vector2i(108,225)]:return false
 if b.quest_helper.places.links(map_id).has(cell):return false
 return nav.floor_cell(b,map_id,cell,occupied)
func classify(nav,b,lane:Dictionary)->Dictionary:
 var map_id:=int(lane.map)
 var start:=point(lane.start)
 var door:=point(lane.door)
 var link:Dictionary=b.quest_helper.places.links(map_id).get(door,{})
 if not same_link(link,lane.link):return {"reason":"current source link differs"}
 if link.has("gate_source") or link.has("requires_time") or bool(link.get("disabled",false)) or not nav.usable(b,link):return {"reason":"original door is restricted/unavailable"}
 var known_start:=false
 for source in lane.start_sources:
  var current:Dictionary=b.quest_helper.places.links(int(source.from_map)).get(point(source.cell),{})
  if same_link(current,source) and int(current.to_map)==map_id and point(current.target)==start:known_start=true
 if not known_start:return {"reason":"original landing source no longer exists"}
 var occupied:Dictionary=nav.blocked(b,map_id)
 b.automation.position_changed(map_id,start,false,"project")
 var path:Array=nav.local_path(b,map_id,start,door,occupied)
 if path.size()<4:return {"reason":"no usable A path or no public interior prefix"}
 if point(path[0].cell)!=start or point(path[-1].cell)!=door:return {"reason":"A path endpoint mismatch"}
 for index in range(1,path.size()-1):
  var cell:=point(path[index].cell)
  if not public_candidate(nav,b,map_id,cell,occupied):return {"reason":"A path enters blocked/protected/portal cell: "+str(cell)}
  var previous:=point(path[index-1].cell)
  if absi(previous.x-cell.x)+absi(previous.y-cell.y)!=1:return {"reason":"nonadjacent A path"}
 var outside:=point(path[-2].cell)
 if absi(outside.x-door.x)+absi(outside.y-door.y)!=1:return {"reason":"outside cell is not immediately before original door"}
 # A blocked public endpoint must never remain an allowed B destination.
 var obstructed:=occupied.duplicate()
 obstructed[outside]=true
 check(not public_candidate(nav,b,map_id,outside,obstructed),"Occupied destination cannot be authorized")
 check(not public_candidate(nav,b,map_id,door,occupied),"Original door remains a separate real step")
 return {"reason":"","cells":path.size()-1,"outside":[outside.x,outside.y],"start_is_portal":b.quest_helper.places.links(map_id).has(start)}
func run()->void:
 var began:=Clock.ticks_msec()
 var table=JSON.parse_string(FileAccess.get_file_as_string(DATA))
 if not table is Dictionary:check(false,"Candidate table loads");quit(1);return
 check(table.lanes.size()==37,"Review contains exactly 37 new directional candidates")
 var identities:Dictionary={}
 var b=Backend.new()
 var nav=Navigation.new()
 for lane in table.lanes:
  check(not identities.has(lane.id),"Each candidate has a unique audit identity")
  identities[lane.id]=true
  var result:=classify(nav,b,lane)
  result.id=lane.id
  result.map=lane.map
  result.beneficiaries=lane.beneficiaries.duplicate()
  if str(result.reason).is_empty():accepted.append(result)
  else:rejected.append(result)
  print("PUBLIC_CANDIDATE ",JSON.stringify(result))
 for map_id in [10201,10202,10203,10204,120,121,20101,20401,20406,118,119,122,32001]:
  check(not public_candidate(nav,b,map_id,Vector2i(10,10),{}),"Caves and script entry pockets never become public by scope omission")
 for cell in [Vector2i(105,228),Vector2i(108,225),Vector2i(103,228),Vector2i(109,226)]:
  check(not public_candidate(nav,b,300,cell,{}),"Outer/inner gate and approach pocket always excluded")
 print("PUBLIC_CANDIDATE_SUMMARY ",JSON.stringify({"accepted":accepted.size(),"rejected":rejected.size(),"assertions":assertions,"failures":failures,"wall_ms":Clock.ticks_msec()-began}))
 b.free()
 quit(1 if failures else 0)
