extends RefCounted
const Rules=preload("res://server/original_quests.gd")
static func entry(backend, script: String, index: int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs_by_source(script):
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",13)
 var started:=Rules.flag(profile,"now",13)
 var footprint:bool=2431 in profile.original_items
 var treasures:bool=[2428,2429,2430].all(func(i):return i in profile.original_items)
 quest.completion_detail="等级16以上向萨顿领盗贼足迹，携足迹挑战三个盗贼，带回三件家宝领取秘药。完成时补记14是依据编号登记的项目补充。原版行为：可重复；青年确认后仅清任务13，加点项14保留。守卫原版全服共享，本项目按角色各自计算：击败后仅自己隐藏，严格超过300秒恢复，服务器重启复位。助手只送公开入口或合法近处原地，洞内须沿原路且限同层连通区域；由南岛（132,421）进入盗贼洞窟，沿原楼梯寻找各层盗贼；自动执行尚未开放。"
 helper.add_step(backend,profile,quest,"saton13:request",entry(backend,"sainasu/event/event13_1",2),not started and not ended,started or ended,"向老人萨顿领取盗贼们的足迹")
 helper.add_step(backend,profile,quest,"saton13:footprint",entry(backend,"sainasu/event/event13_1",1),started and not footprint and not treasures and not ended,footprint or ended,"足迹丢失：向萨顿免费补领")
 for i in range(3):
  var held:bool=(2428+i) in profile.original_items
  helper.add_step(backend,profile,quest,"saton13:battle%d"%(i+1),entry(backend,"100/sb_nusu%d.arg"%(i+1),-1),started and footprint and not held and not ended,held or ended,"携足迹挑战盗贼，取回第%d件家宝"%(i+1))
 helper.add_step(backend,profile,quest,"saton13:deliver",entry(backend,"sainasu/event/event13_1",0),started and treasures and not ended,ended,"带回三件家宝，领取萨顿家的秘药并补记14")
 if not ended and int(profile.player.level)<16:quest.blocked_reason="需要等级16以上。"
 # Existing restart_steps appends the source CLEAN branch; do not duplicate it.
 for step in quest.steps:
  var target:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
  step.navigation_allowed=can_navigate(helper,backend,target)
  if not step.navigation_allowed:
   step.erase("map_id");step.erase("cell")
   step.current=false;step.actionable=false
   step.label+="（须沿原楼梯到达该区域；已击败的守卫按角色冷却）"

const MapFile=preload("res://scripts/map_file.gd")
static var region_cache:Dictionary={}
static func owns(npc:Dictionary)->bool:
 return str(npc.get("source_script","")) in ["sainasu/event/event13_1","sainasu/event/event13_2","100/sb_nusu1.arg","100/sb_nusu2.arg","100/sb_nusu3.arg"]
static func region_data(helper,backend,map_id:int)->Dictionary:
 var path:String=helper.places.file(map_id)
 var occupied:Dictionary={}
 for resident in helper.places.residents:
  if int(resident.map_id)==map_id:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 for npc in backend.quest_catalog.active_npcs():
  if int(npc.map_id)==map_id:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 var links:Dictionary=helper.places.links(map_id)
 var key:String=path+JSON.stringify(occupied.keys())+JSON.stringify(links.keys())
 if region_cache.has(key):return region_cache[key]
 if not helper.maps.has(map_id):helper.maps[map_id]=MapFile.load_map(path)
 var data:Dictionary=helper.maps[map_id]
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
static func region_at(helper,backend,map_id:int,cell:Vector2i)->int:
 var data:Dictionary=region_data(helper,backend,map_id)
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
 if not map_id in range(10701,10706):return []
 var cell:Vector2i=backend.automation.position_cell
 var nearby:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if int(npc.map_id)!=map_id or not owns(npc):continue
  var delta:=cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
  if maxi(absi(delta.x),absi(delta.y))<=2:nearby.append(str(npc.id))
 return ["saton",map_id,region_at(helper,backend,map_id,cell),backend.quest_arrival.has_arrival(backend,map_id,cell),nearby]
static func can_visit(helper,backend,step:Dictionary)->bool:
 return can_navigate(helper,backend,backend.original_quests.npc_by_id(str(step.get("npc_id",""))))
static func can_navigate(helper,backend,npc:Dictionary)->bool:
 if npc.is_empty():return false
 if int(npc.map_id) not in range(10701,10706):return true
 return not destination(helper,backend,npc,"near").is_empty()
static func same_component(helper,backend,npc:Dictionary)->bool:
 if npc.is_empty():return false
 var map_id:int=int(npc.map_id)
 if not map_id in range(10701,10706):return true
 if backend.automation.position_map!=map_id:return false
 var current:int=region_at(helper,backend,map_id,backend.automation.position_cell)
 if current<0:return false
 var labels:Dictionary=region_data(helper,backend,map_id).get("labels",{})
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  if int(labels.get(target+offset,-2))==current:return true
 return false

static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 var target:Dictionary=preload("res://server/legacy_cave_helper.gd").destination(helper,backend,npc,mode)
 if target.is_empty():return {}
 if int(target.map_id) in range(10701,10706) and not same_component(helper,backend,npc):return {}
 return target

# Original component geometry for route audits only; it never authorizes travel.
static func walk_destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 var map_id:int=int(npc.get("map_id",-1))
 if mode not in ["near","arrival"] or not map_id in range(10701,10706) or not same_component(helper,backend,npc):return {}
 var current:int=region_at(helper,backend,map_id,backend.automation.position_cell)
 if current<0:return {}
 var labels:Dictionary=region_data(helper,backend,map_id).get("labels",{})
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 var queue:Array[Vector2i]=[]
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  var point:Vector2i=target+offset
  if int(labels.get(point,-1))==current:queue.append(point)
 if queue.is_empty():return {}
 if mode=="near":return {"map_id":map_id,"cell":[queue[0].x,queue[0].y],"npc_id":str(npc.id)}
 var spawn:Array=helper.places.info(map_id).get("spawn",[])
 if spawn.size()!=2:return {}
 var origin:=Vector2i(int(spawn[0]),int(spawn[1]))
 var seen:Dictionary={}
 for point in queue:seen[point]=true
 var cursor:=0
 while cursor<queue.size():
  var point:Vector2i=queue[cursor];cursor+=1
  if maxi(absi(point.x-origin.x),absi(point.y-origin.y))<=32:return {"map_id":map_id,"cell":[point.x,point.y],"npc_id":str(npc.id)}
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next:Vector2i=point+offset
   if not seen.has(next) and int(labels.get(next,-1))==current:seen[next]=true;queue.append(next)
 return {}
