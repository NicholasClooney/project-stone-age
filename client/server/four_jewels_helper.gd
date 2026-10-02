extends RefCounted
static var targets:Dictionary={}
const Rules=preload("res://server/original_quests.gd")
const PARTS=[{"group":711,"enemy":1305,"item":2760,"name":"地"},{"group":712,"enemy":1306,"item":2761,"name":"水"},{"group":713,"enemy":1307,"item":2763,"name":"风"},{"group":714,"enemy":1308,"item":2762,"name":"火"}]
static func entry(backend,index:int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!="extra/event/hougyoku":continue
  for branch in npc.branches:
   if int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func hunting(helper,backend,part:Dictionary) -> Dictionary:
 var key:="%d:%d"%[backend.encounter_catalog.get_instance_id(),int(part.item)]
 if targets.has(key):return targets[key].duplicate(true)
 for area in backend.encounter_catalog.data.get("areas",[]):
  if not area.groups.any(func(g):return int(g.id)==int(part.group)):continue
  if helper.places.info(int(area.map_id)).is_empty():continue
  var rect:Array=area.rect
  # Only use a walkable point actually won by this source area priority.
  # A geometric rectangle midpoint can fall in a different overlapping area.
  for y in range(int(rect[1]),int(rect[3])+1,8):
   for x in range(int(rect[0]),int(rect[2])+1,8):
    var target:Dictionary=helper.destination(backend,{"id":"","map_id":int(area.map_id),"cell":[x,y],"area_rect":rect},"near")
    if target.is_empty():continue
    var actual:Dictionary=backend.encounter_catalog.area_at(int(area.map_id),Vector2i(int(target.cell[0]),int(target.cell[1])))
    if int(actual.get("id",-1))!=int(area.id):continue
    targets[key]={"id":"jewels:hunt:%d"%int(part.item),"npc_id":"","map_id":int(area.map_id),"cell":target.cell,"source":{"type":"encounter","area_id":int(area.id),"area_rect":rect.duplicate(),"enemy_id":int(part.enemy),"item_id":int(part.item),"group_id":int(part.group),"area_source_line":int(area.get("source_line",0))}}
    return targets[key].duplicate(true)
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",45)
 var started:=Rules.flag(profile,"now",45)
 var crystal:bool=2764 in profile.original_items
 helper.add_step(backend,profile,quest,"jewels:request",entry(backend,1),not started and not ended,started or ended,"向村子的学者领取结晶石（角色60级）")
 var complete:=true
 for part in PARTS:
  var count:int=profile.original_items.count(int(part.item))
  complete=complete and count>0
  var step:=hunting(helper,backend,part)
  if step.is_empty():step={"id":"jewels:hunt:%d"%int(part.item),"npc_id":"","source":{"type":"item_requirement"}}
  step.current=crystal and count==0 and not ended
  step.done=count>0 or ended
  step.actionable=step.current and step.has("map_id")
  step.label="持结晶石寻找%s宝珠敌，战斗随机掉落（当前%d）；持有此珠时原条件组不再出现"%[part.name,count]
  quest.steps.append(step)
 helper.add_step(backend,profile,quest,"jewels:return",entry(backend,0),crystal and complete and not ended,ended,"把结晶石与四宝珠交给学者，领取月光的手镯并完成45")
 if started and not crystal and not ended:
  quest.blocked_reason="结晶石已丢失：向学者取消再重新接取；原取消扣1魅力。"
  helper.add_step(backend,profile,quest,"jewels:recover",entry(backend,1),true,false,"结晶石丢失：找学者取消再接取")
 if int(profile.player.level)<60 and not ended:quest.blocked_reason="接取与交付均需角色60级。"
 quest.completion_detail="四宝玉任务只使用实际绑定的学者；持结晶石才加入四种原条件遭遇组。宝珠随机掉落，地/火100‰、水/风500‰，不是每战必得。普通装备属性与原魔法标签分开；复活守护未生效。原敌特殊战术/技能未恢复，使用现有AI。原版NPC位置为全服共享，本项目按角色各自计算，服务器重启复位。助手瞬移为项目便利，自动执行尚未开放。"
