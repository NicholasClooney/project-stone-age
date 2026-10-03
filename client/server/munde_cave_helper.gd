extends RefCounted
## Source stages and position-derived navigation; no synthetic progress flags.
const Rules=preload("res://server/original_quests.gd")
static func entry(backend, script: String, index: int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs_by_source(script):
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",9)
 var now9:=Rules.flag(profile,"now",9)
 var now10:=Rules.flag(profile,"now",10)
 var now11:=Rules.flag(profile,"now",11)
 var end10:=Rules.flag(profile,"ended",10)
 var end11:=Rules.flag(profile,"ended",11)
 var end12:=Rules.flag(profile,"ended",12)
 var stone10:bool=2419 in profile.original_items
 var stone11:bool=2420 in profile.original_items
 var in_cave:bool=backend.automation.position_map in range(11101,11108)
 var victory_region:int=region_at(helper,backend,Vector2i(23,35)) if backend.automation.position_map==11107 else -1
 var past_guard:bool=victory_region>=0 and region_at(helper,backend,backend.automation.position_cell)==victory_region
 quest.completion_detail="成人仪式完成且等级30以上可接。取回两村守护石后，首次须先交卡坦石，再交霍特尔石，最后回柯尔克村姑领取黄色大首饰；只有最后回报才完成整项日志。洞窟暗号为“在卡坦有梦德”。洞内助手仅在沿原路线合法抵达、步行走近人物且原动作允许时原地交谈；不能跳过同房间步行。洞窟各层必须走原楼梯，族长侧需先战胜守卫。自动执行尚未开放。"
 helper.add_step(backend,profile,quest,"munde9:request",entry(backend,"sainasu/event/event09",1),not now9 and not ended,now9 or ended,"向柯尔克村姑接取委托")
 helper.add_step(backend,profile,quest,"munde11:request",entry(backend,"sainasu/event/event11",2 if now10 else 3),now9 and not now11 and not end11,now11 or end11,"向卡坦青年了解守护石")
 helper.add_step(backend,profile,quest,"munde10:request",entry(backend,"sainasu/event/event10",2 if now11 else 3),now9 and not now10 and not end10,now10 or end10,"向霍特尔村姑了解守护石")
 helper.add_step(backend,profile,quest,"munde9:gate",entry(backend,"genout/wpm_100_443_127",-1),now9 and now10 and now11 and not stone10 and not stone11 and not end12 and not in_cave,in_cave or stone10 or stone11 or end12,"向井边盗贼说出原暗号：在卡坦有梦德")
 helper.add_step(backend,profile,quest,"munde9:battle",entry(backend,"100/sb_go.arg",-1),now9 and now10 and now11 and not stone10 and not stone11 and not end12 and backend.automation.position_map==11107 and not past_guard,past_guard or stone10 or stone11 or end12,"挑战悟与唐的原四敌队伍；胜利后传送通过守卫")
 helper.add_step(backend,profile,quest,"munde12:stones",entry(backend,"sainasu/event/event12",0),now9 and now10 and now11 and not stone10 and not stone11 and not end12 and past_guard,stone10 or stone11 or end12,"通过洞窟暗号与悟唐守卫后，向梦德领取两村守护石")
 helper.add_step(backend,profile,quest,"munde11:deliver",entry(backend,"sainasu/event/event11",0 if end10 else 1),now11 and stone11 and not end11,end11,"首次先交卡坦守护石，领取芙雷雅铠并增加1魅力")
 helper.add_step(backend,profile,quest,"munde10:deliver",entry(backend,"sainasu/event/event10",0),end11 and now10 and stone10 and not end10,end10,"再交霍特尔守护石，领取勾玉并完成两村回报")
 helper.add_step(backend,profile,quest,"munde9:deliver",entry(backend,"sainasu/event/event09",0),end10 and end11 and end12 and not ended,ended,"回柯尔克村姑处领取黄色大首饰最终谢礼")
 for step in quest.steps:
  var target:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
  step.navigation_allowed=can_navigate(helper,backend,target)
  if not step.navigation_allowed:
   step.erase("map_id");step.erase("cell")
   step.current=false;step.actionable=false
   step.label+="（需沿原入口、楼梯与守卫到达此区域；不可跳过）"
 if not ended and (int(profile.player.level)<30 or not Rules.flag(profile,"ended",4)):quest.blocked_reason="需要等级30以上，并先完成成人仪式。"

const MapFile=preload("res://scripts/map_file.gd")
static var region_cache:Dictionary={}
static func owns(npc:Dictionary)->bool:
 return str(npc.get("source_script","")) in ["sainasu/event/event09","sainasu/event/event10","sainasu/event/event11","sainasu/event/event12","100/sb_go.arg","100/sb_dan.arg","genout/wpm_100_443_127"]
static func region_data(helper,backend)->Dictionary:
 var path:String=helper.places.file(11107)
 var occupied:Dictionary={}
 for resident in helper.places.residents:
  if int(resident.map_id)==11107:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 for npc in backend.quest_catalog.active_npcs():
  if int(npc.map_id)==11107:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 var links:Dictionary=helper.places.links(11107)
 var key:String=path+JSON.stringify(occupied.keys())+JSON.stringify(links.keys())
 if region_cache.has(key):return region_cache[key]
 if not helper.maps.has(11107):helper.maps[11107]=MapFile.load_map(path)
 var data:Dictionary=helper.maps[11107]
 if data.is_empty():return {}
 var labels:Dictionary={};var group:=0
 for y in range(int(data.height)):
  for x in range(int(data.width)):
   var start:=Vector2i(x,y)
   if labels.has(start) or not helper.safe(data,start,occupied,links):continue
   group+=1;labels[start]=group
   var queue:Array[Vector2i]=[start];var cursor:=0
   while cursor<queue.size():
    var point:Vector2i=queue[cursor];cursor+=1
    for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
     var next:Vector2i=point+offset
     if labels.has(next) or not helper.safe(data,next,occupied,links):continue
     labels[next]=group;queue.append(next)
 var result:Dictionary={"labels":labels,"portals":links}
 region_cache[key]=result
 return result
static func region_at(helper,backend,cell:Vector2i)->int:
 var data:Dictionary=region_data(helper,backend)
 var labels:Dictionary=data.get("labels",{})
 if labels.has(cell):return int(labels[cell])
 # A source staircase may publish its occupied portal cell as the landing.
 # Resolve only a single adjacent component; never bridge two regions.
 if not data.get("portals",{}).has(cell):return -1
 var regions:Array=[]
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  var id:int=int(labels.get(cell+offset,-1))
  if id>=0 and not id in regions:regions.append(id)
 return int(regions[0]) if regions.size()==1 else -1
static func stage_key(helper,backend)->Array:
 var map_id:int=backend.automation.position_map
 if not map_id in range(11101,11108):return []
 var nearby:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if owns(npc) and int(npc.map_id)==map_id and can_navigate(helper,backend,npc):nearby.append(str(npc.id))
 nearby.sort()
 return ["munde",map_id,region_at(helper,backend,backend.automation.position_cell) if map_id==11107 else -1,backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell),nearby]
static func can_visit(step:Dictionary)->bool:
 return bool(step.get("navigation_allowed",false))
static func can_navigate(helper,backend,npc:Dictionary)->bool:
 if npc.is_empty():return false
 if int(npc.map_id)!=11107:return true
 if backend.automation.position_map!=11107:return false
 if not backend.quest_arrival.has_arrival(backend,11107,backend.automation.position_cell):return false
 var delta:Vector2i=backend.automation.position_cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if maxi(absi(delta.x),absi(delta.y))>2:return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
 if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return false
 var current:int=region_at(helper,backend,backend.automation.position_cell)
 if current<0:return false
 var labels:Dictionary=region_data(helper,backend).get("labels",{})
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  if int(labels.get(target+offset,-2))==current:return true
 return false

static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"] or int(npc.get("map_id",-1))!=11107 or not can_navigate(helper,backend,npc):return {}
 # Recheck authority for both raw NPC and helper-step requests. No different
 # neighbour, arrival flood, or same-room teleport can preserve a false route.
 var cell:Vector2i=backend.automation.position_cell
 return {"map_id":11107,"cell":[cell.x,cell.y],"npc_id":str(npc.id)}
