extends RefCounted
## Original earth39 sequence; navigation is convenience, never gate authority.
const Rules=preload("res://server/original_quests.gd")
const MapFile=preload("res://scripts/map_file.gd")
static var region_cache:Dictionary={}
const SCRIPTS=["jaruga/event/ruri01","jaruga/event/ruri02","jaruga/event/ruri03","jaruga/event/ruri04","jaruga/event/ruri05","jaruga/event/ruri06","200/sb_dtp.arg","200/sb_dbt.arg","genout/wpm_21003_34_10","genout/wpm_200_359_671","genout/wpm_200_358_671"]
static func owns(npc:Dictionary)->bool:
 return str(npc.get("source_script","")) in SCRIPTS or (str(npc.get("id","_")).is_empty() and int(npc.get("map_id",-1))==21002)
static func entry(backend,script:String,index:int=-1)->Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary)->void:
 var ended:=Rules.flag(profile,"ended",39)
 var started:=Rules.flag(profile,"now",39)
 var diary:=Rules.item_count(profile,2698)>0
 var necklace:=Rules.item_count(profile,2699)>0
 var feather:=Rules.item_count(profile,2700)>0
 var floor_id:int=backend.automation.position_map
 quest.completion_detail="完成成人仪式后向拉鲁接取委托，从伊布取得日记，与项链一同交给蒂亚特，得到大地之绊、魅力+1并完成39。入口需65级及成人仪式；三楼审判接受大地之羽、进行中39或完成39任一项。原版行为：携日记不会遇到掉羽毛的逃走鲁尼帖斯；丢失日记/项链可补领。宝袋消耗全部大地之羽，原85槽随机一件，重复槽保留权重；项目修复：恢复原256字节截断的完整奖池。奖励装备原固定攻击/防御/敏捷/魅力按原装备槽生效；装备魔法/抗性、连击/投掷特殊行为、材料合成与原敌特殊技能尚未实现。项链/羽毛穿戴后须卸下才能满足原背包物品条件。伊布移动原版全服共享，本项目按角色各自计算、重启复位。助手为项目便利，洞内须沿原路步行；仅已合法到达、符合当前原分支并已在近谈范围时保持原地，不代走门、迷宫或守卫。捕宠直达不授予任务到达资格。"
 helper.add_step(backend,profile,quest,"earth39:request",entry(backend,"jaruga/event/ruri02",1),not started and not ended,started or ended,"向拉鲁接取委托并领取项链")
 helper.add_step(backend,profile,quest,"earth39:necklace",entry(backend,"jaruga/event/ruri02",0),started and not necklace and not ended,necklace or ended,"项链遗失后向拉鲁补领")
 helper.add_step(backend,profile,quest,"earth39:diary",entry(backend,"jaruga/event/ruri03",1),started and not diary and not ended,diary or ended,"找到伊布，领取母亲的日记")
 for script in ["genout/wpm_200_359_671","genout/wpm_200_358_671"]:
  helper.add_step(backend,profile,quest,"earth39:entrance:"+script,entry(backend,script),not floor_id in range(21001,21016),floor_id in range(21001,21016),"通过原琉璃入口：65级且已完成成人仪式")
 helper.add_step(backend,profile,quest,"earth39:judgement",entry(backend,"genout/wpm_21003_34_10"),floor_id==21003,false,"大地审判：出示羽毛，或正在进行/已完成琉璃委托")
 helper.add_step(backend,profile,quest,"earth39:guard9",entry(backend,"200/sb_dtp.arg"),floor_id==21009,false,"挑战九楼特洛十敌原队伍")
 helper.add_step(backend,profile,quest,"earth39:guard14",entry(backend,"200/sb_dbt.arg"),floor_id==21014,false,"挑战十四楼布洛十敌原队伍，胜利进入女神所在区域")
 helper.add_step(backend,profile,quest,"earth39:deliver",entry(backend,"jaruga/event/ruri01",0),started and diary and necklace and not ended,ended,"向蒂亚特交日记及项链，领取大地之绊")
 helper.add_step(backend,profile,quest,"earth39:lore",entry(backend,"jaruga/event/ruri04",0 if feather else 1),floor_id==21015,false,"询问女神使者原宿身与宝袋说明")
 for bag in [5,6]:
  helper.add_step(backend,profile,quest,"earth39:bag%d"%bag,entry(backend,"jaruga/event/ruri%02d"%bag,0),feather,false,"%s：交全部羽毛，原85槽随机一件（项目修复截断；不去重）"%("大袋子" if bag==5 else "小袋子"))
 if not diary and not feather:
  var npc:Dictionary={"id":"","map_id":21002,"cell":[10,10],"area_rect":[10,10,10,10]}
  var allowed:bool=can_navigate(helper,backend,npc)
  var area:Dictionary=backend.encounter_catalog.area_at(21002,Vector2i(10,10))
  quest.steps.append({"id":"earth39:feather","npc_id":"","map_id":21002,"cell":[10,10],"current":allowed,"done":false,"actionable":allowed,"label":"可选宝袋：未携日记时在二楼原区域遇逃走鲁尼帖斯，战胜掉落大地之羽；原特殊逃跑战术尚未实现。","source":{"type":"encounter","area_id":int(area.get("id",436)),"area_rect":area.get("rect",[]),"enemy_id":1146,"item_id":2700}})
 for step in quest.steps:
  var npc:Dictionary=step_target(backend,step)
  step.navigation_allowed=can_visit(helper,backend,step)
  if not step.navigation_allowed:
   step.erase("map_id");step.erase("cell");step.current=false;step.actionable=false
   if not bool(step.get("done",false)) and int(npc.get("map_id",-1)) in range(21001,21017) and not can_navigate(helper,backend,npc):
    step.label+="（须沿原路步行到原遇敌区域）" if str(npc.get("id","_")).is_empty() else "（须沿原入口、楼梯及守卫步行至近谈位置）"
 if not Rules.flag(profile,"ended",4):quest.blocked_reason="先完成成人仪式；琉璃入口另需65级。"
 elif int(profile.player.level)<65:quest.blocked_reason="可以先领取委托；琉璃洞窟入口需要65级。"
static func step_target(backend,step:Dictionary)->Dictionary:
 if str(step.get("id",""))=="earth39:feather" and str(step.get("npc_id","_")).is_empty() and int(step.get("map_id",-1))==21002 and step.get("cell",[])==[10,10]:
  return {"id":"","map_id":21002,"cell":[10,10]}
 return backend.original_quests.npc_by_id(str(step.get("npc_id","")))
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
 if not map_id in range(21001,21016):return []
 var ready:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if owns(npc) and int(npc.map_id)==map_id:
   var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
   ready.append([npc.id,branch,can_navigate(helper,backend,npc)])
 return ["earth",map_id,region_at(helper,backend,map_id,backend.automation.position_cell),backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell),ready]
static func can_visit(helper,backend,step:Dictionary)->bool:
 var npc:Dictionary=step_target(backend,step)
 if not can_navigate(helper,backend,npc):return false
 if str(npc.get("id","_")).is_empty():return bool(step.get("current",false))
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 return not branch.is_empty() and branch==step.get("source",{}).get("branch_data",{}) and bool(step.get("current",false)) and bool(step.get("actionable",false))
static func can_navigate(helper,backend,npc:Dictionary)->bool:
 if npc.is_empty():return false
 var map_id:int=int(npc.map_id)
 if not map_id in range(21001,21016):return true
 if backend.automation.position_map!=map_id:return false
 var point:Vector2i=backend.automation.position_cell
 if not backend.quest_arrival.has_arrival(backend,map_id,point):return false
 if str(npc.get("id","_")).is_empty():return npc.get("cell",[])==[point.x,point.y]
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 if branch.is_empty() or not backend.original_quests.allowed(backend,npc):return false
 if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return false
 var current:int=region_at(helper,backend,map_id,backend.automation.position_cell)
 if current<0:return false
 var labels:Dictionary=region_data(helper,backend,map_id).get("labels",{})
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  if int(labels.get(target+offset,-2))==current:return true
 return false

static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 var map_id:int=int(npc.get("map_id",-1))
 if mode not in ["near","arrival"] or not can_navigate(helper,backend,npc):return {}
 if not map_id in range(21001,21016):
  var plain:Dictionary=npc.duplicate(true)
  plain.events=[];plain.erase("source_script")
  return helper.destination(backend,plain,mode)
 # Both modes keep the already-authorized near position. Any project
 # displacement would revoke the common arrival proof, even within one room.
 var point:Vector2i=backend.automation.position_cell
 return {"map_id":map_id,"cell":[point.x,point.y],"npc_id":str(npc.id)}
