extends RefCounted
## Water46 only. Navigation never crosses a source door or guard component.
const Rules=preload("res://server/original_quests.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Interaction=preload("res://scripts/npc_interaction.gd")
var regions:Dictionary={}
var npc_cache:Array=[]
var npc_cache_key:Array=[]
func active_npcs(backend)->Array:
 var key:Array=[backend.quest_catalog.get_instance_id(),backend.quest_catalog.enabled_events.duplicate(),backend.original_quests.npc_state.version]
 if key!=npc_cache_key:
  npc_cache_key=key;npc_cache=backend.quest_catalog.active_npcs();regions.clear()
 return npc_cache

func owns(npc:Dictionary)->bool:
 return npc.get("events",[]).any(func(event):return int(event)==46) or (str(npc.get("id","")).is_empty() and (int(npc.get("map_id",-1))==30305 or int(npc.get("map_id",-1)) in range(21201,21216)) and not npc.get("area_rect",[]).is_empty())

func region(helper,backend,map_id:int,point:Vector2i)->int:
 var npcs:Array=active_npcs(backend)
 if not regions.has(map_id):
  helper.places.set_quest_catalog(backend.quest_catalog)
  var data:Dictionary=MapFile.load_map(helper.places.file(map_id))
  if data.is_empty():return -1
  var occupied:Dictionary={}
  for npc in npcs:
   if int(npc.map_id)==map_id:occupied[Vector2i(int(npc.cell[0]),int(npc.cell[1]))]=true
  var links:Dictionary=helper.places.links(map_id)
  var labels:Dictionary={};var serial:=0
  for y in range(int(data.height)):
   for x in range(int(data.width)):
    var seed:=Vector2i(x,y)
    if labels.has(seed) or not helper.safe(data,seed,occupied,links):continue
    serial+=1;labels[seed]=serial
    var queue:Array[Vector2i]=[seed];var cursor:=0
    while cursor<queue.size():
     var cell:Vector2i=queue[cursor];cursor+=1
     for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
      var next:Vector2i=cell+delta
      if labels.has(next) or not helper.safe(data,next,occupied,links):continue
      labels[next]=serial;queue.append(next)
  regions[map_id]=labels
 return int(regions[map_id].get(point,-1))

func protected_map(map_id:int)->bool:
 return map_id in range(21201,21316) or map_id in [31301,31302] or map_id in range(30301,30308)

func stage_key(helper,backend)->Array:
 var map_id:int=backend.automation.position_map
 var cell:Vector2i=backend.automation.position_cell
 if not protected_map(map_id):return []
 var profile:Dictionary=backend.session._profile
 var permissions:Array=[]
 for npc in active_npcs(backend):
  if int(npc.map_id)!=map_id or not owns(npc):continue
  var branch:Dictionary=backend.original_quests.branch_for(npc,profile)
  var near:bool=cell-Vector2i(int(npc.cell[0]),int(npc.cell[1])) in Interaction.offsets()
  permissions.append([npc.id,near,backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty()])
 return [map_id,region(helper,backend,map_id,cell),backend.quest_arrival.has_arrival(backend,map_id,cell),permissions]

func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"]:return {}
 var map_id:=int(npc.map_id)
 var at:Vector2i=backend.automation.position_cell
 if protected_map(map_id):
  if int(backend.automation.position_map)!=map_id or not backend.quest_arrival.has_arrival(backend,map_id,at):return {}
  var component:=region(helper,backend,map_id,at)
  if component<0:return {}
  if str(npc.get("id","")).is_empty():
   var rect:Array=npc.get("area_rect",[])
   if rect.size()!=4 or at.x<int(rect[0]) or at.y<int(rect[1]) or at.x>int(rect[2]) or at.y>int(rect[3]):return {}
  else:
   var actual:Dictionary=backend.original_quests.npc_by_id(str(npc.id))
   if actual.is_empty():return {}
   var branch:Dictionary=backend.original_quests.branch_for(actual,backend.session.snapshot())
   if branch.is_empty() or not backend.quest_arrival.check_action(backend,actual,branch,str(branch.get("type",""))).is_empty():return {}
   var target:=Vector2i(int(actual.cell[0]),int(actual.cell[1]))
   if at-target not in Interaction.offsets():return {}
   if not Interaction.offsets().any(func(offset):return region(helper,backend,map_id,target+offset)==component):return {}
  # Even a same-room jump would revoke legitimate arrival. Both modes only
  # keep the current authority position after original branch/range checks.
  return {"map_id":map_id,"cell":[at.x,at.y],"npc_id":str(npc.get("id",""))}
 # Public gate approaches need a safe adjacent cell, not a flood fill of
 # every outdoor tile. This is the same safe predicate used by region().
 helper.places.set_quest_catalog(backend.quest_catalog)
 var data:Dictionary=MapFile.load_map(helper.places.file(map_id))
 if data.is_empty():return {}
 var occupied:Dictionary={}
 for actual in active_npcs(backend):
  if int(actual.map_id)==map_id:occupied[Vector2i(int(actual.cell[0]),int(actual.cell[1]))]=true
 var links:Dictionary=helper.places.links(map_id)
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 for offset in Interaction.offsets():
  var point:Vector2i=target+offset
  if helper.safe(data,point,occupied,links):return {"map_id":map_id,"cell":[point.x,point.y],"npc_id":str(npc.get("id",""))}
 return {}

func can_visit(helper,backend,step:Dictionary)->bool:
 if not step.get("current",false) or step.get("done",false):return false
 var npc:Dictionary
 if str(step.get("npc_id","")).is_empty():
  npc={"id":"","map_id":step.get("map_id",-1),"cell":step.get("cell",[]),"area_rect":step.get("source",{}).get("area_rect",[])}
 else:
  if not step.get("actionable",false):return false
  npc=backend.original_quests.npc_by_id(str(step.npc_id))
  if npc.is_empty():return false
  var selected:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
  if selected!=step.get("source",{}).get("branch_data",{}):return false
 return npc.get("cell",[]).size()==2 and not destination(helper,backend,npc,"near").is_empty()

func entry(backend,script:String,index:int)->Dictionary:
 for npc in active_npcs(backend):
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if int(branch.get("source_branch_index",0))==index:return {"npc":npc,"branch":branch}
 return {}

func hunt_step(helper,backend,active:bool,done:bool,shell:bool=false)->Dictionary:
 var map_id:=21209 if shell else 30305
 var area_id:=581 if shell else 570
 var group_id:=723 if shell else 718
 var enemy_id:=1335 if shell else 1324
 var item_id:=2766 if shell else 2767
 for area in backend.encounter_catalog.data.get("areas",[]):
  if int(area.id)!=area_id or int(area.map_id)!=map_id:continue
  var rect:Array=area.rect
  for y in range(int(rect[1]),int(rect[3])+1,4):
   for x in range(int(rect[0]),int(rect[2])+1,4):
    var point:=Vector2i(x,y)
    var component:=region(helper,backend,map_id,point)
    if component<0:continue
    if int(backend.automation.position_map)==map_id and component!=region(helper,backend,map_id,backend.automation.position_cell):continue
    if int(backend.encounter_catalog.area_at(map_id,point).get("id",-1))!=area_id:continue
    return {"id":"water46:shell" if shell else "water46:stone","npc_id":"","map_id":map_id,"cell":[x,y],"current":active,"done":done,"actionable":false,"label":"可选：碧青9层原敌1335（组723），水苍之贝20/1000；保留其他原掉落" if shell else "石之岛原敌1324（组718）：深蓝石800/1000（须先亲自抵达本层）","source":{"type":"encounter","area_id":area_id,"area_rect":rect.duplicate(),"enemy_id":enemy_id,"group_id":group_id,"item_id":item_id}}
 return {}

func steps(helper,backend,profile:Dictionary,quest:Dictionary)->void:
 var now:=Rules.flag(profile,"now",46);var ended:=Rules.flag(profile,"ended",46)
 var ready:=int(profile.player.level)>=65 and Rules.flag(profile,"ended",4) and [39,40,42].any(func(e):return Rules.flag(profile,"ended",e))
 var crystal:=Rules.item_count(profile,2769)>0
 quest.completion_detail="65级、成人礼END4及地39／火40／风42任一完成可接。沿原碧青洞窟两场十敌战到女神；石之岛取得深蓝石，经40的300石币原门或福尔德5000（46,18）普通门进湖取群青水，经后方洞窟原材料门找贤者合成，再交水晶获得水戒与魅力+1。原版行为：贤者合成保留无水晶的OR分支，但助手不绕材料门。水苍之贝可选大小箱：原36槽重复权重，一次消耗身上全部水苍之贝；新贝可再换。助手仅在沿原路合法抵达且已靠近人物时保持原地；洞内须步行通过原门／战斗。项目捕宠直达不授予任务资格。原特殊技能未恢复，使用现AI；装备魔法／抗性仅资料标记，未生效。"
 var requests:Array=[]
 for i in range(3):requests.append(entry(backend,"jaruga/event/hekisei",i))
 helper.add_step(backend,profile,quest,"water46:request",helper.pick(backend,profile,requests),ready and not now and not ended,now or ended,"请艾尼基使者接取水的加护（地／火／风任一）")
 var active:=now and not ended
 for route in [["front","genout/wpm_300_247_222","300（247,222）→石之岛1层"],["rear","genout/wpm_300_182_162","300（182,162）→石之岛7层"]]:
  helper.add_step(backend,profile,quest,"water46:stone-door:"+str(route[0]),entry(backend,str(route[1]),0),active and not crystal and Rules.item_count(profile,2767)==0,false,"可选原入口："+str(route[2])+"（65级＋成人礼）")
 var stone:=hunt_step(helper,backend,active and not crystal and Rules.item_count(profile,2767)==0,crystal or ended or Rules.item_count(profile,2767)>0)
 if not stone.is_empty():quest.steps.append(stone)
 var has_shell:=Rules.item_count(profile,2766)>0
 var shell:=hunt_step(helper,backend,(active or ended) and not has_shell,false,true)
 if not shell.is_empty():quest.steps.append(shell)
 helper.add_step(backend,profile,quest,"water46:entrance",entry(backend,"genout/wpm_200_73_696",0),active or has_shell,false,"亲自通过65级＋成人礼原入口")
 for guard in ["mzl","mzn"]:
  helper.add_step(backend,profile,quest,"water46:guard:"+guard,entry(backend,"200/sb_"+guard+".arg",0),active or has_shell,false,"沿碧青洞窟挑战原十敌守卫（现有AI）")
 helper.add_step(backend,profile,quest,"water46:explain",entry(backend,"jaruga/event/hekisei01",2),active and not crystal,false,"听艾尼基说明水晶材料")
 helper.add_step(backend,profile,quest,"water46:lake-door",entry(backend,"genout/wpm_40_13_1",0),active and not crystal and Rules.item_count(profile,2768)==0,false,"可选：从原收费门前往群青湖（300石币；另可走福尔德普通门）")
 helper.add_step(backend,profile,quest,"water46:water",entry(backend,"jaruga/event/hekisei04",1),active and not crystal and Rules.item_count(profile,2768)==0,false,"向菲伊领取／补领群青水")
 helper.add_step(backend,profile,quest,"water46:sage-door",entry(backend,"genout/wpm_21308_20_10",0),active and not crystal,false,"亲自通过贤者原材料门（深蓝石＋群青水）")
 helper.add_step(backend,profile,quest,"water46:crystal",entry(backend,"jaruga/event/hekisei03",1),active and not crystal,crystal or ended,"请贤者合成（原版行为：保留无水晶OR分支）")
 helper.add_step(backend,profile,quest,"water46:reward",entry(backend,"jaruga/event/hekisei01",0),active and crystal,ended,"交碧青水晶，领取水戒与水的加护")
 helper.add_step(backend,profile,quest,"water46:back-entrance",entry(backend,"genout/wpm_200_316_711",0),ended and has_shell,false,"可选原回程入口（END46＋水苍之贝）")
 for box in ["05","06"]:
  helper.add_step(backend,profile,quest,"water46:box:"+box,entry(backend,"jaruga/event/hekisei"+box,0),Rules.item_count(profile,2766)>0,false,"选择%s箱：原36槽，一次收取全部水苍之贝"%("小" if box=="05" else "大"))
 if not ready and not now and not ended:quest.blocked_reason="须65级、成人礼END4与地39／火40／风42任一完成。"
 elif active and not crystal:quest.blocked_reason="深蓝石：石之岛30305原敌1324掉落800/1000；群青水：40收费门或福尔德普通门进入湖区后31302菲伊。沿原门前往后方洞窟，助手不跨门或守卫。"
