extends RefCounted
## Fire40 source branches; navigation is confined to the current walkable component.
const Rules=preload("res://server/original_quests.gd")
const MapFile=preload("res://scripts/map_file.gd")
const PREFIX="giiru/event/sink/"
const GATES=["genout/wpm_20301_200_39","genout/wpm_30502_45_41","genout/wpm_30503_26_5"]
const GUARDS=["300/sb_hba7.arg","300/sb_hba9.arg","300/sb_hpa.arg"]
var region_cache:Dictionary={}
func owns(npc:Dictionary)->bool:
 var script:=str(npc.get("source_script",""))
 return script.begins_with(PREFIX) or script in GATES or script in GUARDS or script=="genout/ss_30504_10_11"
func route_protected(map_id:int)->bool:
 # Public village, lake elder and30504 shop have no pilgrimage requirement.
 return map_id in range(30001,30017) or map_id in range(20301,20310) or map_id in [30501,30502,30503]
func arrival_ready(backend,npc:Dictionary)->bool:
 var map_id:int=int(npc.map_id)
 if not route_protected(map_id):return true
 var cell:Vector2i=backend.automation.position_cell
 if not backend.quest_arrival.has_arrival(backend,map_id,cell):return false
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if maxi(absi(cell.x-target.x),absi(cell.y-target.y))>2:return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 return backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty()
func stage_key(helper,backend)->Array:
 var map_id:int=backend.automation.position_map
 var relevant:=false
 for npc in backend.quest_catalog.npcs:
  if owns(npc) and int(npc.map_id)==map_id:relevant=true;break
 for state in backend.quest_catalog.npc_overrides.values():
  if int(state.get("map_id",-1))==map_id:relevant=true;break
 var ready_npcs:Array=[]
 if relevant and route_protected(map_id):
  for npc in backend.quest_catalog.active_npcs():
   if owns(npc) and int(npc.map_id)==map_id and arrival_ready(backend,npc):ready_npcs.append(str(npc.id))
 return ["fire",map_id,region_at(helper,backend,map_id,backend.automation.position_cell) if relevant else -1,backend.original_quests.npc_state.version,ready_npcs]
func steps(helper,backend,profile:Dictionary,quest:Dictionary)->void:
 var now:=Rules.flag(profile,"now",40)
 var ended:=Rules.flag(profile,"ended",40)
 var feather:bool=2706 in profile.original_items
 quest.completion_detail="完成成人仪式后向达那村真红接取仪式，寻找不死鸟取得羽毛，沿原入口、楼梯及十敌守卫抵达伊拉交付，才完成火40。深红入口要求65级及成人仪式。可选水壶须在巴那姆商店花1150石币购买，再向湖边老人亲自说出“很多／一半／一点点”。恐龙按原水壶编号换水；火使者先处理进行中任务及原始水壶说明，再按剩余壶兑奖。原版行为：裸编号交付会收走所有同编号壶，只给一次结果。NPC移动原为全服共享，本项目按角色计算、重启复位。助手为项目便利；洞内必须沿原路线步行、过门和胜战，合法到达且已在NPC近旁时仅保持原地对话，不能用瞬移代走。原战术特殊技能、魔法及抗性尚未恢复，沿用现有AI。"
 for npc in backend.quest_catalog.active_npcs():
  if not owns(npc):continue
  var script:=str(npc.get("source_script",""))
  if str(npc.get("kind",""))=="original_jug_shop":
   quest.steps.append({"id":"fire40:buy-jug","label":"巴那姆商店：1150石币购买一只空壶","npc_id":str(npc.id),"map_id":int(npc.map_id),"cell":npc.cell.duplicate(),"current":true,"done":false,"actionable":int(profile.player.gold)>=1150 and Rules.Session.bag_slots(profile)<15,"source":{"type":"original_jug_shop","npc_id":str(npc.id)}})
   continue
  var selected:Dictionary=backend.original_quests.branch_for(npc,profile)
  if selected.is_empty():continue
  var current:=true
  var done:=false
  var label:=""
  if script==PREFIX+"sink07":
   current=not now and not ended;done=now or ended;label="向真红接取火精灵仪式"
  elif script==PREFIX+"sink01":
   current=now and not feather and not ended;done=feather or ended;label="寻找不死鸟领取羽毛；领取后它会移动"
  elif script==PREFIX+"sink02":
   current=now and feather and not ended;done=ended;label="向伊拉交付不死鸟羽毛，领取火羽饰品并完成40"
  elif script in GUARDS:label="挑战原十敌守卫；胜利后通过守卫"
  elif script=="genout/wpm_20301_200_39":label="不死鸟原门：成人仪式及火40进行中或已完成"
  elif script in GATES:label="通过原65级、成人仪式入口"
  elif script==PREFIX+"sink03":label="湖边老人：水量口令或多余空壶退款1149石币"
  elif script==PREFIX+"sink06":label="火使者：按原优先序以水壶兑换随机奖品"
  elif script=="genout/ss_30504_10_11":label="巴那姆商店：1150石币购买空壶"
  else:label="给恐龙喝水：按原水壶编号转换，交付后恐龙移动"
  helper.add_step(backend,profile,quest,"fire40:"+str(npc.id),{"npc":npc,"branch":selected},current,done,label)
  if script==PREFIX+"sink03":
   for branch in npc.branches:
    if not branch.has("spoken_keyword"):continue
    helper.add_step(backend,profile,quest,"fire40:water:"+str(branch.spoken_keyword),{"npc":npc,"branch":branch},2708 in profile.original_items,false,"向老人亲自输入原口令："+str(branch.spoken_keyword))
 for step in quest.steps:
  var npc:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
  step.navigation_allowed=can_navigate(helper,backend,npc)
  if not step.navigation_allowed:
   step.erase("map_id");step.erase("cell")
   step.current=false;step.actionable=false
   step.label+="（须沿原路线到达当前楼层同一侧）"
 if not ended and not Rules.flag(profile,"ended",4):quest.blocked_reason="先完成成人仪式。"
func can_visit(helper,backend,step:Dictionary)->bool:
 return bool(step.get("navigation_allowed",false)) and can_navigate(helper,backend,backend.original_quests.npc_by_id(str(step.get("npc_id",""))))
func region_data(helper,backend,map_id:int)->Dictionary:
 var path:String=helper.places.file(map_id)
 var key:String="%s:%d:%d"%[path,backend.quest_catalog.get_instance_id(),backend.original_quests.npc_state.version]
 if region_cache.has(key):return region_cache[key]
 if region_cache.size()>32:region_cache.clear()
 var occupied:Dictionary={}
 for resident in helper.places.residents:
  if int(resident.map_id)==map_id:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 for npc in backend.quest_catalog.active_npcs():
  if int(npc.map_id)==map_id:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 var links:Dictionary=helper.places.links(map_id)
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
func region_at(helper,backend,map_id:int,cell:Vector2i)->int:
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
func can_navigate(helper,backend,npc:Dictionary)->bool:
 if npc.is_empty() or not owns(npc):return false
 var map_id:int=int(npc.map_id)
 if backend.automation.position_map!=map_id or not arrival_ready(backend,npc):return false
 var current:int=region_at(helper,backend,map_id,backend.automation.position_cell)
 if current<0:return false
 var labels:Dictionary=region_data(helper,backend,map_id).get("labels",{})
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  if int(labels.get(target+offset,-2))==current:return true
 return false

func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 var map_id:int=int(npc.get("map_id",-1))
 if mode not in ["near","arrival"] or not can_navigate(helper,backend,npc):return {}
 if route_protected(map_id):
  var cell:Vector2i=backend.automation.position_cell
  return {"map_id":map_id,"cell":[cell.x,cell.y],"npc_id":str(npc.id)}
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
