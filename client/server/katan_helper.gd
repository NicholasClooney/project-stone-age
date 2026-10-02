extends RefCounted
const Rules=preload("res://server/original_quests.gd")
const NAMES={221:"克邦凯斯",222:"加克拉",223:"加格",224:"邦恩吉"}
static func entry(backend,index:int) -> Dictionary:
 for npc in backend.quest_catalog.active_npcs():
  if str(npc.get("source_script",""))!="seimu/event/event02_1":continue
  for branch in npc.branches:
   if int(branch.get("source_branch_index",-1))==index:return {"npc":npc,"branch":branch}
 return {}
static func capture(helper,backend,species:int) -> Dictionary:
 # Pick ordinary source encounters that can be trained UP to25. Unlike the
 # doctor's helper, these four templates live on more than one map.
 var data:Dictionary=backend.encounter_catalog.data
 for area in data.get("areas",[]):
  if helper.places.info(int(area.map_id)).is_empty():continue
  if area.get("invalid_weights",false) or int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:continue
  for choice in area.groups:
   var group:Dictionary=data.get("groups",{}).get(str(int(choice.id)),{})
   if group.get("invalid_weights",false) or int(group.get("requires_item",-1))>=0 or int(group.get("excludes_item",-1))>=0:continue
   for member in group.get("enemies",[]):
    var enemy:Dictionary=data.get("enemies",{}).get(str(int(member.id)),{})
    if int(enemy.get("template_id",-1))!=species or int(enemy.get("pet_flag",0))!=1 or int(enemy.get("level_max",999))>25:continue
    var rect:Array=area.rect
    var point:Array=[(int(rect[0])+int(rect[2]))/2,(int(rect[1])+int(rect[3]))/2]
    var target:Dictionary=helper.destination(backend,{"id":"","map_id":int(area.map_id),"cell":point,"area_rect":rect},"near")
    if target.is_empty():continue
    var actual:Dictionary=backend.encounter_catalog.area_at(int(area.map_id),Vector2i(int(target.cell[0]),int(target.cell[1])))
    if int(actual.get("id",-1))!=int(area.id):continue
    return {"id":"katan:pet:%d"%species,"npc_id":"","map_id":int(area.map_id),"cell":target.cell,"current":false,"done":false,"actionable":false,"source":{"type":"encounter","area_id":int(area.id),"area_rect":rect.duplicate(),"area_source_line":int(area.get("source_line",0)),"enemy_id":int(enemy.id),"species":species,"level_min":int(enemy.level_min),"level_max":int(enemy.level_max),"original_end_event":0}}
 return {}
static func steps(helper,backend,profile:Dictionary,quest:Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",35)
 var started:=Rules.flag(profile,"now",35)
 var proof:bool=2607 in profile.original_items
 helper.add_step(backend,profile,quest,"katan:request",entry(backend,3),not started and not ended,started or ended,"向沙漠卡坦接取四鲨鱼委托")
 for species in [223,224,221,222]:
  var pair_done:bool=ended or (proof and species in [223,224])
  var eligible:=Rules.pet_index(profile,"PET=25-%d*1"%species)
  var current:bool=started and not ended and (species in [221,222] if proof else species in [223,224])
  var step:=capture(helper,backend,species)
  if step.is_empty():step={"id":"katan:pet:%d"%species,"npc_id":"","source":{"type":"pet_requirement"}}
  var held:Array=[]
  for pet in profile.pets:
   if str(pet.get("species",""))=="original_%d"%species:held.append("%s Lv.%d%s"%[str(pet.pet_id),int(pet.level),"（事件宠，不可交）" if Rules.Session.original_pet_event(pet)!=0 else ""])
  step.current=current and eligible<0;step.done=pair_done or eligible>=0
  step.actionable=step.current and step.has("map_id")
  step.label="捕获普通%s并培养至恰好25级（超过25级不收）；%s"%[NAMES[species],"尚未携带" if held.is_empty() else "、".join(held)]
  quest.steps.append(step)
 helper.add_step(backend,profile,quest,"katan:first",entry(backend,2),started and not proof and not ended,proof or ended,"同时交25级加格与邦恩吉，领取原编号2607证明")
 helper.add_step(backend,profile,quest,"katan:second",entry(backend,0),started and proof and not ended,ended,"携证明同时交25级克邦凯斯与加克拉，领取1级修宝")
 quest.completion_detail="必须随身携带四种普通宠物，等级恰好25；每次交两只不同UID，先加格/邦恩吉，再克邦凯斯/加克拉。卡坦按原区域随机合法格出生；原版全服共享，本项目按角色服务器内存分别出生，重启重新抽取。原脚本证明编号2607在本地itemset名为火难的戒指，请保留并放在背包。完成后END35，后续四火鸡换金飞龙尚未开放；助手瞬移为项目便利，自动执行尚未开放。"
