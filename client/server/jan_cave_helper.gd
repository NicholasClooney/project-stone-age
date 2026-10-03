extends RefCounted
const Rules=preload("res://server/original_quests.gd")
static func entry(backend, script: String, index: int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper, backend, profile: Dictionary, quest: Dictionary) -> void:
 var event:=int(quest.event)
 var end20:=Rules.flag(profile,"ended",20)
 var end21:=Rules.flag(profile,"ended",21)
 var end22:=Rules.flag(profile,"ended",22)
 var now20:=Rules.flag(profile,"now",20)
 var now21:=Rules.flag(profile,"now",21)
 var flower:bool=2486 in profile.original_items
 var ornament:bool=2487 in profile.original_items
 var letter:bool=2488 in profile.original_items
 var map_id:int=backend.automation.position_map
 var victory_region:int=region_at(helper,backend,20607,Vector2i(36,31)) if map_id==20607 else -1
 var past_guard:bool=map_id==20608 or (victory_region>=0 and region_at(helper,backend,20607,backend.automation.position_cell)==victory_region)
 quest.completion_detail="携花向吉德接取委托，带发饰见强恩后完成20。沙拉接21后先向强恩领取随机山贼装备并完成22，再取家书交吉德完成21。原日志把22写成送家书，但实际22在领装备时完成。洞内助手仅在沿原路线合法抵达、已经走近人物且当前原动作允许时原地交谈；不能用项目瞬移跳过同房间步行。由加鲁卡（285,926）进入洞窟，沿原楼梯、口令门和守卫前进。自动执行尚未开放。"
 if event==20:
  helper.add_step(backend,profile,quest,"jan20:flower",entry(backend,"jaruga/event/event20_1",2),not flower and not now20 and not end20,flower or now20 or end20,"向吉德的朋友领取花")
  helper.add_step(backend,profile,quest,"jan20:request",entry(backend,"jaruga/event/event20_2",1),flower and not now20 and not end20,now20 or end20,"携花向吉德接取寻找女儿的委托")
  helper.add_step(backend,profile,quest,"jan20:ornament",entry(backend,"jaruga/event/event20_3",0),now20 and not ornament and not end20,ornament or end20,"向吉德的儿子领取母亲的发饰")
  var gate_scripts:=["genout/wpm_20604_11_53","genout/wpm_20605_51_4","genout/wpm_20606_9_23"]
  var keywords:=["红色月亮的光芒","蓝色山脉即力量","白色之风即速度"]
  for i in range(3):
   helper.add_step(backend,profile,quest,"jan20:gate%d"%(i+1),entry(backend,gate_scripts[i],-1),now20 and ornament and not end20 and map_id==20604+i,end20 or (map_id>20604+i and map_id<=20608),"原洞窟口令%d：%s"%[i+1,keywords[i]])
  helper.add_step(backend,profile,quest,"jan20:battle",entry(backend,"200/sb_jan1.arg",-1),now20 and ornament and not end20 and map_id==20607 and not past_guard,end20 or past_guard,"挑战山贼三人组；胜利后进入强恩居处")
  helper.add_step(backend,profile,quest,"jan20:meet",entry(backend,"jaruga/event/event20_4",0),now20 and ornament and not end20 and past_guard,end20,"通过洞窟口令与三人组守卫后，携发饰拜访强恩")
 elif event==21:
  helper.add_step(backend,profile,quest,"jan21:mother",entry(backend,"jaruga/event/event20_5",0),end20 and ornament and not now21 and not end21,now21 or end21,"先听强恩妻子讲述沙拉的身世")
  helper.add_step(backend,profile,quest,"jan21:request",entry(backend,"jaruga/event/event20_6",2),end20 and ornament and not now21 and not end21,now21 or end21,"把母亲的发饰交给沙拉，接取回信委托")
  helper.add_step(backend,profile,quest,"jan21:letter",entry(backend,"jaruga/event/event20_6",0),now21 and end22 and not letter and not end21,letter or end21,"先完成22领取装备，再向沙拉领取家书")
  helper.add_step(backend,profile,quest,"jan21:deliver",entry(backend,"jaruga/event/event20_2",0),end20 and now21 and letter and not end21,end21,"把家书交给吉德，领取卡娜的木笛")
  if now21 and not end22:quest.blocked_reason="先向强恩转达沙拉的决定，领取山贼装备（任务22）。"
 else:
  helper.add_step(backend,profile,quest,"jan22:reward",entry(backend,"jaruga/event/event20_4",1),end20 and now21 and not end22,end22,"向强恩转达沙拉的决定，随机领取一件山贼装备")
  if not end22 and (not end20 or not now21):quest.blocked_reason="先找到强恩，再将发饰交给沙拉接取21。"
 # The public approach is a separate project convenience, bound to an actual
 # reviewed gate for server resolution; it never advertises an interior target.
 if map_id not in range(20601,20609):
  var wanted:bool=(now20 and not end20) if event==20 else ((end20 and not end21 and not letter) if event==21 else (now21 and not end22))
  if wanted:
   var gate:Dictionary=entry(backend,"genout/wpm_20604_11_53",-1)
   var outside:Dictionary=public_entrance(helper,backend)
   if not gate.is_empty() and not outside.is_empty():
    quest.steps.append({"id":"jan%d:entrance"%event,"label":"前往加鲁卡原洞窟入口；入洞后沿原路线步行","npc_id":str(gate.npc.id),"map_id":200,"cell":outside.cell,"current":true,"done":false,"actionable":false,"navigation_allowed":true,"source":{"type":"route_entry","npc_id":str(gate.npc.id),"actions":{}}})
 for step in quest.steps:
  if str(step.source.get("type",""))=="route_entry":continue
  var target:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
  step.navigation_allowed=can_navigate(helper,backend,target)
  if not step.navigation_allowed:
   step.erase("map_id");step.erase("cell")
   step.current=false;step.actionable=false
   step.label+="（须沿原入口、楼梯、口令门与守卫合法抵达，并步行到人物附近）"

const MapFile=preload("res://scripts/map_file.gd")
static var region_cache:Dictionary={}
static func owns(npc:Dictionary)->bool:
 return str(npc.get("source_script","")) in ["jaruga/event/event20_1","jaruga/event/event20_2","jaruga/event/event20_3","jaruga/event/event20_4","jaruga/event/event20_5","jaruga/event/event20_6","200/sb_jan1.arg","200/sb_jan2.arg","200/sb_jan3.arg","genout/wpm_20604_11_53","genout/wpm_20605_51_4","genout/wpm_20606_9_23"]
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
 if not map_id in range(20601,20609):return []
 var nearby:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if owns(npc) and int(npc.map_id)==map_id and can_navigate(helper,backend,npc):nearby.append(str(npc.id))
 nearby.sort()
 return ["jan",map_id,region_at(helper,backend,map_id,backend.automation.position_cell),backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell),nearby]
static func can_visit(step:Dictionary)->bool:
 return bool(step.get("navigation_allowed",false))
static func can_navigate(helper,backend,npc:Dictionary)->bool:
 if npc.is_empty():return false
 var map_id:int=int(npc.map_id)
 if not map_id in range(20601,20609):return true
 if backend.automation.position_map!=map_id:return false
 if not backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell):return false
 var target_cell:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if maxi(absi(backend.automation.position_cell.x-target_cell.x),absi(backend.automation.position_cell.y-target_cell.y))>2:return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
 if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return false
 var current:int=region_at(helper,backend,map_id,backend.automation.position_cell)
 if current<0:return false
 var labels:Dictionary=region_data(helper,backend,map_id).get("labels",{})
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  if int(labels.get(target+offset,-2))==current:return true
 return false

static func public_entrance(helper,backend)->Dictionary:
 for portal in helper.places.links(200).values():
  if int(portal.to_map)!=20601 or portal.get("disabled",false) or portal.has("gate_source"):continue
  var outside:Dictionary=helper.destination(backend,{"id":"","events":[],"map_id":200,"cell":portal.cell},"near")
  if not outside.is_empty():outside.npc_id=""
  return outside
 return {}

static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 var map_id:int=int(npc.get("map_id",-1))
 if mode not in ["near","arrival"] or not owns(npc) or not map_id in range(20601,20609):return {}
 if backend.automation.position_map not in range(20601,20609):return public_entrance(helper,backend)
 if not can_navigate(helper,backend,npc):return {}
 # Both buttons are a no-op at the authority's current legal talk position.
 # Never choose a different neighbour or flood to another point in this room.
 var cell:Vector2i=backend.automation.position_cell
 return {"map_id":map_id,"cell":[cell.x,cell.y],"npc_id":str(npc.id)}
