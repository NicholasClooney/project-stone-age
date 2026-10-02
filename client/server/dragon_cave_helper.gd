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
static func stage_key(backend)->Array:return [inside(backend)]
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
 quest.completion_detail="向一楼守护者领龙笛，持笛在四／五／六楼分别遇疾速／刚气／钢格之龙，原玉掉落各80%。持三玉独自通过七楼守卫，再携三玉与龙笛向三龙任选一种奖励；交付才写END17。三玉门只验物不扣玉，领奖收四件。龙枪普通属性按现有装备槽生效；龙铠、龙衣的躯干装备槽及治愈／猛毒／复活魔法尚未实现，保留原奖励与源资料。原敌特殊技能未恢复。助手为项目导航便利，不绕过三玉门、不自动执行。"
 helper.add_step(backend,profile,quest,"dragon17:flute",entry(backend,"jaruga/event/event17_4",0 if started else 1),not flute and not ended,flute or ended,"向一楼守护者领取或补领龙的魅力之笛")
 for spec in [[20804,404,562,2457,"疾速"],[20805,405,560,2458,"刚气"],[20806,406,559,2459,"钢格"]]:
  var have:bool=Rules.item_count(profile,int(spec[3]))>0
  var step:Dictionary={"id":"dragon17:jade:%d"%int(spec[3]),"npc_id":"","current":started and flute and not have and not ended,"done":have or ended,"actionable":false,"label":"持龙笛在%d楼遇%s之龙，胜后原概率80%%取得龙玉。"%[int(spec[0])-20800,str(spec[4])],"source":{"type":"dragon_cave_encounter"}}
  var info:Dictionary=helper.places.info(int(spec[0]));var cell:Array=info.get("spawn",[])
  if cell.size()==2:
   var area:Dictionary=backend.encounter_catalog.area_at(int(spec[0]),Vector2i(int(cell[0]),int(cell[1])))
   if not area.is_empty():
    var point:Dictionary=helper.destination(backend,{"id":"","map_id":int(spec[0]),"cell":cell,"area_rect":area.rect},"near")
    if not point.is_empty():
     step.map_id=int(spec[0]);step.cell=point.cell;step.actionable=step.current
     step.source={"type":"encounter","area_id":int(area.id),"area_rect":area.rect.duplicate(),"enemy_id":int(spec[2]),"item_id":int(spec[3]),"requires_item":2505}
  quest.steps.append(step)
 helper.add_step(backend,profile,quest,"dragon17:gate",entry(backend,"genout/wpm_20807_11_37"),jewels and not arrived and not ended,arrived or ended,"持三颗龙玉独自通过七楼守卫（不消耗玉）")
 for reward in [[1,"龙之衣"],[2,"龙之枪"],[3,"龙之铠"]]:
  helper.add_step(backend,profile,quest,"dragon17:reward:%d"%int(reward[0]),entry(backend,"jaruga/event/event17_%d"%int(reward[0]),0),arrived and flute and jewels and not ended,ended,"三选一：交三玉与龙笛领取%s"%str(reward[1]))
 if jewels and not arrived and not ended:quest.blocked_reason="须亲自通过七楼三玉守卫；助手不会直接进入领奖区域。"
static func destination(helper,backend,npc:Dictionary,mode:String)->Dictionary:
 if str(npc.get("source_script","")).begins_with("jaruga/event/event17_") and int(npc.map_id)==20807 and not inside(backend):return {}
 var plain:=npc.duplicate(true);plain.events=[]
 if str(npc.get("source_script",""))=="genout/wpm_20807_11_37":
  # Seed navigation on the source entrance component only. Two-tile NPC
  # interaction neighbours otherwise include cells across the wall.
  plain.id="";plain.cell=[11,38];plain.area_rect=[11,38,11,38]
 var result:Dictionary=helper.destination(backend,plain,mode)
 if not result.is_empty():result.npc_id=str(npc.id)
 return result
