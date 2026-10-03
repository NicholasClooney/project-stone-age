extends RefCounted
## Wind stages are source branches; navigation cannot cross a source component.
const Rules=preload("res://server/original_quests.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Munde=preload("res://server/munde_cave_helper.gd")
const PREFIX="sainasu/event/"
var regions:Dictionary={}
func owns(npc:Dictionary)->bool:
 return str(npc.get("source_script","")) in [PREFIX+"genou_1",PREFIX+"genou_2",PREFIX+"genou_3",PREFIX+"genou_4",PREFIX+"event12","100/sb_kbu.arg","100/sb_kgi.arg","genout/wpm_100_278_325","genout/wpm_11206_5_42"]
func stage_key(helper,backend)->Array:
 var map_id:int=backend.automation.position_map
 var eligibility:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if owns(npc) and int(npc.map_id)==map_id:eligibility.append([str(npc.id),legitimate(backend,npc)])
 return [map_id,backend.original_quests.npc_state.version,region_at(helper,backend,map_id,backend.automation.position_cell) if map_id in range(11201,11216) else -1,eligibility]
func entry(backend,script:String,index:int=-1,npc_id:String="")->Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script or not npc_id.is_empty() and str(npc.id)!=npc_id:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
func steps(helper,backend,profile:Dictionary,quest:Dictionary)->void:
 var now41:=Rules.flag(profile,"now",41);var end41:=Rules.flag(profile,"ended",41)
 var now42:=Rules.flag(profile,"now",42);var end42:=Rules.flag(profile,"ended",42)
 var harp:bool=Rules.item_count(profile,2736)>0
 quest.completion_detail="70级且完成成人礼可从萨伊纳斯(278,325)进入玄黄。沿原楼梯取手环、挑战两处守卫及顶层十敌，先向威尔接41，再向姆哈萨接42；进入梦德洞窟须亲自说原口令“在卡坦有梦德”并通过悟唐守卫，交谈先按梦德原分支，再领竖琴完成41；回威尔交琴才完成42。丢琴可在42进行中补领。原版行为：高档献宠需END4/42与普通布鲁顿≥61、不需环，消费可选≥60；中档≥43、低档≥1需环、不查END4/42，原高档优先。项目补充：多只可交宠由玩家选UID。回程门只收背包手环；助手仅在已沿原路合法抵达且当前可对话时保持原地；洞内沿原路步行，不用项目瞬移跳门、楼梯或守卫。原守卫为全服共享，本项目按角色各自计算、严格超过180秒复活；特殊AI未恢复。"
 add(helper,backend,profile,quest,"entry",entry(backend,"genout/wpm_100_278_325"),not end42,false,"进入玄黄洞窟（70级及成人礼原门）")
 add(helper,backend,profile,quest,"bracelet",entry(backend,PREFIX+"genou_4",0),not Rules.item_count(profile,2758)>0,false,"领取风之手环；缺失时原版可补领")
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))=="100/sb_kbu.arg":
   add(helper,backend,profile,quest,"guard:"+str(npc.id),{"npc":npc,"branch":npc.branches[0]},not end42,false,"击败挡路十敌守卫；个人180秒冷却")
 add(helper,backend,profile,quest,"summit",entry(backend,"100/sb_kgi.arg"),not end42,false,"挑战顶层原十敌，胜利后传送至风神殿")
 add(helper,backend,profile,quest,"request41",entry(backend,PREFIX+"genou_1",3),not now41 and not end41,now41 or end41,"向威尔领取找回风之竖琴的请求")
 add(helper,backend,profile,quest,"request42",entry(backend,PREFIX+"genou_3",1),now41 and not now42 and not end42,now42 or end42,"向萨伊纳斯姆哈萨了解被盗竖琴")
 add(helper,backend,profile,quest,"harp",entry(backend,PREFIX+"event12",2 if end41 else 3),now42 and not harp and not end42,harp or end42,"通过梦德原口令与悟唐守卫后领取竖琴；原梦德奖励优先")
 add(helper,backend,profile,quest,"finish42",entry(backend,PREFIX+"genou_1",0),end41 and now42 and harp and not end42,end42,"向威尔交竖琴，领取风之锁并完成42")
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=PREFIX+"genou_2":continue
  var chosen:Dictionary=backend.original_quests.branch_for(npc,profile)
  if chosen.is_empty():continue
  add(helper,backend,profile,quest,"offering:"+str(npc.id),{"npc":npc,"branch":chosen},true,false,"可选献宠（三档原条件与优先序；每次消耗一只所选宠物）")
  if not quest.steps.is_empty():quest.steps[-1].optional=true
 add(helper,backend,profile,quest,"return",entry(backend,"genout/wpm_11206_5_42"),true,false,"回程原门：收回背包中的风之手环")
 if not Rules.flag(profile,"ended",4) or int(profile.player.level)<70:quest.blocked_reason="玄黄原入口须70级并完成成人礼；可选献宠的原条件另行判断。"
func add(helper,backend,profile:Dictionary,quest:Dictionary,id:String,source:Dictionary,current:bool,done:bool,label:String)->void:
 if source.is_empty():return
 var allowed:=can_navigate(helper,backend,source.npc)
 helper.add_step(backend,profile,quest,"wind%d:"%int(quest.event)+id,source,current,done,label)
 if quest.steps.is_empty():return
 var step:Dictionary=quest.steps[-1]
 step.navigation_allowed=allowed
 if not allowed:
  step.current=false;step.actionable=false
  step.erase("map_id");step.erase("cell")
  step.label+="（须沿原路到达人物附近）"
func can_visit(helper,backend,step:Dictionary)->bool:
 if not bool(step.get("navigation_allowed",false)):return false
 var npc:Dictionary=backend.original_quests.npc_by_id(str(step.get("npc_id","")))
 return not npc.is_empty() and owns(npc) and can_navigate(helper,backend,npc)
func region_data(helper,backend,map_id:int)->Dictionary:
 var occupied:Dictionary={}
 for resident in helper.places.residents:
  if int(resident.map_id)==map_id:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 for npc in backend.quest_catalog.active_npcs():
  if int(npc.map_id)==map_id:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
 var links:Dictionary=helper.places.links(map_id)
 var key:String=str(map_id)+JSON.stringify(occupied.keys())+JSON.stringify(links.keys())
 if regions.has(key):return regions[key]
 if not helper.maps.has(map_id):helper.maps[map_id]=MapFile.load_map(helper.places.file(map_id))
 var data:Dictionary=helper.maps[map_id]
 if data.is_empty():return {}
 var labels:Dictionary={};var serial:=0
 for y in range(int(data.height)):
  for x in range(int(data.width)):
   var seed:=Vector2i(x,y)
   if labels.has(seed) or not helper.safe(data,seed,occupied,links):continue
   serial+=1;labels[seed]=serial
   var queue:Array[Vector2i]=[seed];var cursor:=0
   while cursor<queue.size():
    var point:Vector2i=queue[cursor];cursor+=1
    for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
     var next:Vector2i=point+delta
     if not labels.has(next) and helper.safe(data,next,occupied,links):labels[next]=serial;queue.append(next)
 var result:Dictionary={"labels":labels,"portals":links}
 # Personal guardian visibility can change; retain only the latest geometry.
 regions.clear();regions[key]=result
 return result
func region_at(helper,backend,map_id:int,cell:Vector2i)->int:
 if map_id==11107:return Munde.region_at(helper,backend,cell)
 var data:Dictionary=region_data(helper,backend,map_id)
 var labels:Dictionary=data.get("labels",{})
 if labels.has(cell):return int(labels[cell])
 if not data.get("portals",{}).has(cell):return -1
 var adjacent:Array=[]
 for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
  var id:int=int(labels.get(cell+delta,-1))
  if id>=0 and not id in adjacent:adjacent.append(id)
 return int(adjacent[0]) if adjacent.size()==1 else -1
func legitimate(backend,npc:Dictionary)->bool:
 if int(npc.get("map_id",-1))==100:return true
 if not backend.quest_arrival.has_arrival(backend,int(npc.map_id),backend.automation.position_cell):return false
 var offset:Vector2i=backend.automation.position_cell-Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if maxi(absi(offset.x),absi(offset.y))>2:return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session._profile)
 return backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty()
func can_navigate(helper,backend,npc:Dictionary)->bool:
 var map_id:=int(npc.get("map_id",-1))
 if map_id==100:return true
 if not legitimate(backend,npc):return false
 if map_id==11107:return Munde.can_navigate(helper,backend,npc)
 if not map_id in range(11201,11216) or int(backend.automation.position_map)!=map_id:return false
 var current:=region_at(helper,backend,map_id,backend.automation.position_cell)
 if current<0:return false
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 var labels:Dictionary=region_data(helper,backend,map_id).get("labels",{})
 for delta in preload("res://scripts/npc_interaction.gd").offsets():
  if int(labels.get(target+delta,-1))==current:return true
 return false
func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"] or not can_navigate(helper,backend,npc):return {}
 var map_id:=int(npc.map_id)
 if map_id==100:
  var plain:=npc.duplicate(true);plain.events=[];plain.source_script=""
  return helper.destination(backend,plain,mode)
 # A real project relocation would invalidate continuous arrival. Preserve
 # the legal standing position and let the original transaction recheck it.
 var cell:Vector2i=backend.automation.position_cell
 return {"map_id":map_id,"cell":[cell.x,cell.y],"npc_id":str(npc.id)}
