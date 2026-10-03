extends RefCounted
## The source seventh-floor wall separates the gate from all reward dragons.
const Rules=preload("res://server/original_quests.gd")
const MapFile=preload("res://scripts/map_file.gd")
static var reward_cells:Dictionary={}
static func inside(backend)->bool:
 if backend.automation.position_map!=20807:return false
 if reward_cells.is_empty():
  var map:Dictionary=MapFile.load_map("res://assets/legacy/world/20807.map")
  if map.is_empty():return false
  var queue:Array[Vector2i]=[Vector2i(13,35)];reward_cells[queue[0]]=true
  var cursor:=0
  while cursor<queue.size():
   var cell:Vector2i=queue[cursor];cursor+=1
   for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var next:Vector2i=cell+delta
    if next.x<0 or next.y<0 or next.x>=int(map.width) or next.y>=int(map.height) or reward_cells.has(next):continue
    if int(map.blocked[next.y*int(map.width)+next.x])!=0:continue
    reward_cells[next]=true;queue.append(next)
 return reward_cells.has(backend.automation.position_cell)
static func stage_key(backend)->Array:
 var map_id:int=backend.automation.position_map
 if map_id not in range(20801,20808):return []
 var ready:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  if int(npc.map_id)==map_id and npc.get("events",[]).any(func(event):return int(event)==17):
   ready.append([npc.id,backend.original_quests.branch_for(npc,backend.session.snapshot()),can_navigate(backend,npc)])
 return ["dragon17",map_id,inside(backend),backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell),ready]
static func entry(backend,script:String,index:int=-1)->Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!=script:continue
  for branch in npc.branches:
   if index<0 or int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary)->void:
 var ended:=Rules.flag(profile,"ended",17)
 var started:=Rules.flag(profile,"now",17)
 var flute:=Rules.item_count(profile,2505)>0
 var jewels:bool=[2457,2458,2459].all(func(id):return Rules.item_count(profile,id)>0)
 var arrived:=inside(backend)
 quest.completion_detail="向一楼守护者领龙笛，持笛在四／五／六楼分别遇疾速／刚气／钢格之龙，原玉掉落各80%。持三玉独自通过七楼守卫，再携三玉与龙笛向三龙任选一种奖励；交付才写END17。三玉门只验物不扣玉，领奖收四件。龙枪普通属性按现有装备槽生效；龙铠、龙衣的原奖励装备效果及治愈／猛毒／复活魔法尚未实现，保留原奖励与源资料。原敌特殊技能未恢复。助手为项目便利；从加鲁卡原入口步行穿过七层和三玉门，已合法到达且符合原分支时仅支持近处原地交谈。三玉遇敌步骤仅作说明，不提供洞内瞬移。"
 helper.add_step(backend,profile,quest,"dragon17:flute",entry(backend,"jaruga/event/event17_4",0 if started else 1),not flute and not ended,flute or ended,"向一楼守护者领取或补领龙的魅力之笛")
 for spec in [[20804,404,562,2457,"疾速"],[20805,405,560,2458,"刚气"],[20806,406,559,2459,"钢格"]]:
  var have:bool=Rules.item_count(profile,int(spec[3]))>0
  var step:Dictionary={"id":"dragon17:jade:%d"%int(spec[3]),"npc_id":"","current":started and flute and not have and not ended,"done":have or ended,"actionable":false,"label":"持龙笛在%d楼遇%s之龙，胜后原概率80%%取得龙玉。"%[int(spec[0])-20800,str(spec[4])],"source":{"type":"dragon_cave_encounter"}}
  quest.steps.append(step)
 helper.add_step(backend,profile,quest,"dragon17:gate",entry(backend,"genout/wpm_20807_11_37"),jewels and not arrived and not ended,arrived or ended,"持三颗龙玉独自通过七楼守卫（不消耗玉）")
 for reward in [[1,"龙之衣"],[2,"龙之枪"],[3,"龙之铠"]]:
  helper.add_step(backend,profile,quest,"dragon17:reward:%d"%int(reward[0]),entry(backend,"jaruga/event/event17_%d"%int(reward[0]),0),arrived and flute and jewels and not ended,ended,"三选一：交三玉与龙笛领取%s"%str(reward[1]))
 if jewels and not arrived and not ended:quest.blocked_reason="须亲自通过七楼三玉守卫；助手不会直接进入领奖区域。"
 for step in quest.steps:
  if str(step.get("npc_id","")).is_empty():continue
  var npc:Dictionary=backend.original_quests.npc_by_id(str(step.npc_id))
  var branch:Dictionary=backend.original_quests.branch_for(npc,profile)
  var permitted:bool=can_navigate(backend,npc) and branch==step.get("source",{}).get("branch_data",{})
  if not permitted:
   step.erase("map_id");step.erase("cell");step.current=false;step.actionable=false
   if not bool(step.get("done",false)):step.label+="（须沿原入口与楼梯步行至近谈位置）"
 if backend.automation.position_map not in range(20801,20808):
  quest.blocked_reason="先到加鲁卡的原龙洞入口，再沿原楼梯步行；持笛或持玉不授予洞内到达资格。"
static func can_navigate(backend,npc:Dictionary)->bool:
 if npc.is_empty() or backend.automation.position_map!=int(npc.get("map_id",-1)):return false
 var map_id:int=int(npc.map_id)
 if map_id not in range(20801,20808):return false
 if not backend.quest_arrival.has_arrival(backend,map_id,backend.automation.position_cell):return false
 if not backend.original_quests.allowed(backend,npc):return false
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 if branch.is_empty() or not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return false
 if map_id==20807:
  if str(npc.get("source_script","")).begins_with("jaruga/event/event17_") and not inside(backend):return false
  if str(npc.get("source_script",""))=="genout/wpm_20807_11_37" and inside(backend):return false
 return true
static func destination(_helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if mode not in ["near","arrival"] or not can_navigate(backend,npc):return {}
 var point:Vector2i=backend.automation.position_cell
 return {"map_id":int(npc.map_id),"cell":[point.x,point.y],"npc_id":str(npc.id)}
