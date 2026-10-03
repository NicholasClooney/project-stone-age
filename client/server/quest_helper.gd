extends RefCounted
## Canonical server projection; every NPC action keeps its original source.
const LegacyCave=preload("res://server/legacy_cave_helper.gd")
const Rules = preload("res://server/original_quests.gd")
const WorldCatalog = preload("res://scripts/world_catalog.gd")
const MapFile = preload("res://scripts/map_file.gd")
const GoldenBui = preload("res://server/golden_bui_helper.gd")
const Dream = preload("res://server/dream_cave_helper.gd")
const Dragon = preload("res://server/dragon_cave_helper.gd")
const Marju = preload("res://server/marju_helper.gd")
var transmigration = preload("res://server/transmigration_foundation.gd").new()
var places = WorldCatalog.new()
var maps := {}
var cached_key := ""
var cached_snapshot := {}

func navigation_key(backend) -> Array:
 var key:Array=GoldenBui.stage_key(backend) if 44 in backend.quest_catalog.enabled_events else []
 if 37 in backend.quest_catalog.enabled_events or 38 in backend.quest_catalog.enabled_events:
  var marju_stage:Array=Marju.stage_key(backend)
  if not marju_stage.is_empty():key=key+[marju_stage]
 if 9 in backend.quest_catalog.enabled_events:key.append_array(preload("res://server/munde_cave_helper.gd").stage_key(self,backend))
 if 17 in backend.quest_catalog.enabled_events:
  var dragon_stage:Array=Dragon.stage_key(backend)
  if not dragon_stage.is_empty():key=key+[dragon_stage]
 if 20 in backend.quest_catalog.enabled_events:key.append_array(preload("res://server/jan_cave_helper.gd").stage_key(self,backend))
 if [32,33,34].any(func(event):return event in backend.quest_catalog.enabled_events):
  var dream_stage:Array=Dream.stage_key(backend)
  if not dream_stage.is_empty():key=key+[dream_stage]
 if 13 in backend.quest_catalog.enabled_events:key.append_array(preload("res://server/saton_cave_helper.gd").stage_key(self,backend))
 if 28 in backend.quest_catalog.enabled_events or 31 in backend.quest_catalog.enabled_events:key.append_array(preload("res://server/brothers_arrival_helper.gd").stage_key(backend))
 if [29,30,54].any(func(event):return event in backend.quest_catalog.enabled_events):key.append_array(preload("res://server/golden_arrival_helper.gd").stage_key(backend))
 key.append_array(transmigration.stage_key(self,backend))
 return key

func snapshot(backend) -> Dictionary:
 # Read only the trusted server profile. Ordinary battle/hunt publications do
 # not need to copy a potentially large pet warehouse or rebuild task recipes.
 var profile: Dictionary = backend.session._profile
 var catalog = backend.quest_catalog
 var key := JSON.stringify([catalog.get_instance_id(),catalog.enabled_events,profile.original_events,profile.original_items,profile.get("original_equipment",{}),profile.original_savepoint_bits,profile.player.level,profile.player.gold,profile.pets.map(func(pet):return [pet.get("pet_id",""),pet.get("species",""),pet.get("level",0),Rules.Session.original_pet_event(pet)]),Rules.Session.bag_slots(profile)])
 key+=JSON.stringify(navigation_key(backend))
 key+=":"+str(backend.original_quests.npc_state.version)
 if key == cached_key:return cached_snapshot.duplicate(true)
 var quests: Array = []
 for job in catalog.jobs:
  var event := int(job.event)
  var enabled: bool = event in catalog.enabled_events
  var ended := Rules.flag(profile,"ended",event)
  var quest := {"id":int(job.id),"event":event,"title":str(job.title),"status":"已完成" if ended else ("进行中" if Rules.flag(profile,"now",event) else "未开始"),"repeatable":false,"can_restart":false,"blocked_reason":"" if enabled else "尚未开放","steps":[]}
  if enabled:
   if event in transmigration.EVENTS:transmigration.steps(self,backend,profile,quest)
   elif event==1:herb_steps(backend,profile,quest)
   elif event==4:adult_steps(backend,profile,quest)
   elif event==2:shell_steps(backend,profile,quest)
   elif event in [15,16]:doctor_steps(backend,profile,quest)
   elif event==18:wood_steps(backend,profile,quest)
   elif event in [6,7,8]:preload("res://server/goya_deliveries_helper.gd").steps(self,backend,profile,quest)
   elif event in [3,5]:preload("res://server/yam_axe_helper.gd").steps(self,backend,profile,quest)
   elif event in [20,21,22]:preload("res://server/jan_cave_helper.gd").steps(self,backend,profile,quest)
   elif event==13:preload("res://server/saton_cave_helper.gd").steps(self,backend,profile,quest)
   elif event==9:preload("res://server/munde_cave_helper.gd").steps(self,backend,profile,quest)
   elif event in [32,33,34]:Dream.steps(self,backend,profile,quest)
   elif event==17:Dragon.steps(self,backend,profile,quest)
   elif event==27:preload("res://server/miner_contest_helper.gd").steps(self,backend,profile,quest)
   elif event==44:GoldenBui.steps(self,backend,profile,quest)
   elif event==35:preload("res://server/katan_helper.gd").steps(self,backend,profile,quest)
   elif event in [37,38]:Marju.steps(self,backend,profile,quest)
   elif event==45:preload("res://server/four_jewels_helper.gd").steps(self,backend,profile,quest)
   elif event in [28,29,30,31,54]:preload("res://server/brothers_helper.gd").steps(self,backend,profile,quest)
   restart_steps(backend,profile,quest)
   preload("res://server/quest_helper_status.gd").apply(profile,quest)
   if ended and quest.repeatable and not quest.can_restart and str(quest.blocked_reason).is_empty():quest.blocked_reason="可重做；当前尚未满足原任务清理条件"
  for step in quest.steps:
   step.quest_id=int(job.id)
   var rewards:Array=[]
   var notices:Array[String]=[]
   var actions:Dictionary=step.get("source",{}).get("actions",{})
   for action in ["GetItem","GetRandItem"]:
    var slots:Array=Rules.item_list(str(actions.get(action,"")))
    var unique_items:Dictionary={}
    var inactive_kinds:Dictionary={}
    for item_id in slots:
     unique_items[item_id]=true
     var item:Dictionary=catalog.items.get(str(item_id),{})
     var effects:Array=preload("res://scripts/original_item_effects.gd").resolve(item)
     if effects.is_empty():continue
     # Preserve every original slot's full effects, including repeated ids.
     rewards.append({"item_id":item_id,"name":str(item.get("name","")),"effects":effects})
     if action=="GetRandItem":
      for effect in effects:
       if not bool(effect.get("active",false)):inactive_kinds[str(effect.get("type","unknown"))]=true
     else:
      var labels:Array[String]=preload("res://scripts/original_item_effects.gd").lines(item)
      if not labels.is_empty():notices.append(str(item.get("name",""))+"："+"；".join(labels))
    if action=="GetRandItem" and not slots.is_empty():
     var names:Dictionary={"magic":"魔法","resistance":"抗性","use":"物品使用","attack_count":"连续攻击次数","attack_pattern":"特殊攻击方式","stat":"普通属性"}
     var categories:Array=inactive_kinds.keys();categories.sort()
     var labels:Array[String]=[]
     for kind in categories:labels.append(str(names.get(kind,kind)))
     var summary:String="原奖池%d槽、%d种物品；重复槽保持原权重，不按物品种类均分概率。"%[slots.size(),unique_items.size()]
     summary+="未实现效果类别："+"、".join(labels)+"。" if not labels.is_empty() else "无未实现效果标记。"
     notices.append(summary+"完整效果见物品说明。")
   if not rewards.is_empty():step.reward_effects=rewards
   if not notices.is_empty():
    step.effects_notice="\n".join(notices)
    step.label+="\n"+str(step.effects_notice)

  quests.append(quest)
 cached_key = key
 cached_snapshot = {"quests":quests}
 return cached_snapshot.duplicate(true)

func candidates(backend,event:int,key:String,item:int) -> Array:
 var result: Array=[]
 for npc in backend.quest_catalog.active_npcs():
  for index in range(npc.branches.size()):
   var branch: Dictionary=npc.branches[index]
   if not branch.get("events",[]).any(func(value):return int(value)==event):continue
   if item not in Rules.item_list(str(branch.actions.get(key,""))):continue
   result.append({"npc":npc,"branch":branch,"index":index})
 return result

func pick(backend,profile:Dictionary,options:Array) -> Dictionary:
 for entry in options:
  if backend.original_quests.branch_for(entry.npc,profile,str(entry.branch.get("spoken_keyword","")))==entry.branch:return entry
 return options[0] if not options.is_empty() else {}

func add_step(backend,profile:Dictionary,quest:Dictionary,id:String,entry:Dictionary,current:bool,done:bool,label:String="") -> void:
 if entry.is_empty():return
 var npc:Dictionary=entry.npc
 var branch:Dictionary=entry.branch
 if places.info(int(npc.map_id)).is_empty() or not FileAccess.file_exists(places.file(int(npc.map_id))):return
 var selected:Dictionary=backend.original_quests.branch_for(npc,profile,str(branch.get("spoken_keyword","")))
 var source:Dictionary=branch
 var blocked := ""
 var cancellation:bool=str(branch.type)=="REQUEST" and Rules.flag(profile,"now",int(branch.event))
 var actionable:bool=current and selected==branch and not cancellation
 # A refusal that precedes the wanted trade is retained once at that stage.
 if current and selected!=branch:
  actionable=false
  if not selected.is_empty():
   source=selected
   blocked=str(selected.texts.get("NomalWindowMsg","当前原分支无法推进此步骤"))
  else:blocked="尚未满足原任务条件"
  var worn_hint := Rules.worn_item_hint(profile,str(branch.condition))
  if not worn_hint.is_empty():blocked=worn_hint
 if current and actionable and branch.actions.has("GetRandItem"):
  # Use the authority's actual UID deletion semantics on a private candidate.
  # Worn items do not occupy bag slots; deleting one cannot free a bag slot.
  var capacity:Dictionary=profile.duplicate(true)
  Rules.remove_items(capacity,str(branch.actions.get("DelItem","")),str(branch.get("item_deletion_scope",""))=="bag")
  var rewards:int=Rules.item_list(str(branch.actions.get("GetItem",""))).size()+1
  if Rules.Session.bag_slots(capacity)+rewards>15:
   actionable=false;blocked="道具栏已满；交换后需要足够空格领取随机谢礼"
 if current and actionable and branch.actions.has("GetPet") and profile.pets.size()-Rules.pet_indices(profile,str(branch.actions.get("DelPet",""))).size()+1>Rules.Session.PET_CAPACITY:
  actionable=false;blocked="宠物栏已满"
 if current and actionable and branch.actions.has("DelStone"):
  var fee := Rules.stone_cost(profile,str(branch.actions.DelStone))
  if fee<0:actionable=false;blocked="尚未支持的原费用"
  elif int(profile.player.gold)<fee:actionable=false;blocked="石币不足"
 if current and cancellation:blocked="已领取；请继续下一步骤"
 var caption:String=label if not label.is_empty() else label_for(backend.quest_catalog,npc,branch)
 if not blocked.is_empty():caption+="（"+blocked+"）"
 caption+=" · %s (%d,%d)" % [places.map_name(int(npc.map_id)),int(npc.cell[0]),int(npc.cell[1])]
 quest.steps.append({"id":id,"label":caption,"npc_id":str(npc.id),"map_id":int(npc.map_id),"cell":npc.cell.duplicate(),"current":current,"done":done,"actionable":actionable,"source":{"npc_id":str(npc.id),"branch":npc.branches.find(source),"type":str(source.type),"condition":str(source.condition),"actions":source.actions.duplicate(true),"branch_data":source.duplicate(true)}})
 if current and not blocked.is_empty():quest.blocked_reason=blocked

func shell_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
 var requests:Array=[]
 for npc in backend.quest_catalog.active_npcs():
  for index in range(npc.branches.size()):
   var branch:Dictionary=npc.branches[index]
   if int(branch.event)==2 and str(branch.type)=="REQUEST" and Rules.matches(profile,str(branch.condition)):
    requests.append({"npc":npc,"branch":branch,"index":index})
 if requests.is_empty():quest.blocked_reason="出生地标记未满足原任务条件";return
 var request:Dictionary=requests[0]
 # Multiple SP bits: a currently effective ACCEPT remains the authority.
 for candidate in requests:
  var held:Array=Rules.item_list(str(candidate.branch.actions.get("GetItem","")))
  if not held.is_empty() and held[0] in profile.original_items:request=candidate;break
 var item:int=Rules.item_list(str(request.branch.actions.GetItem))[0]
 var exchange:Dictionary=pick(backend,profile,candidates(backend,2,"DelItem",item))
 var ended:=Rules.flag(profile,"ended",2)
 var started:bool=Rules.flag(profile,"now",2) or item in profile.original_items
 add_step(backend,profile,quest,"shell:request",request,not started and not ended,started or ended)
 add_step(backend,profile,quest,"shell:exchange",exchange,started and not ended,ended)

func herb_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
 quest.completion_detail="洞内医生须从哈罗山原入口沿五层原路抵达；助手只送公开入口或合法近处原地，不能跳过洞内路线。回村交付保留原持药条件。"
 var ended:=Rules.flag(profile,"ended",1)
 var started:=Rules.flag(profile,"now",1)
 var held:bool=2401 in profile.original_items
 var request:Dictionary={}
 for npc in backend.quest_catalog.active_npcs():
  for branch in npc.branches:
   if int(branch.event)==1 and str(branch.type)=="REQUEST":request={"npc":npc,"branch":branch}
 add_step(backend,profile,quest,"herb:request",request,not started and not ended,started or ended,"向村庄小姑娘领取药草委托")
 add_step(backend,profile,quest,"herb:medicine",pick(backend,profile,candidates(backend,1,"GetItem",2401)),started and not held and not ended,held or ended,"向哈罗山医生领取哈罗的香草")
 add_step(backend,profile,quest,"herb:return",pick(backend,profile,candidates(backend,1,"DelItem",2401)),started and held and not ended,ended,"回村交付香草，领取老爷爷的护身符")

func doctor_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
 var event:=int(quest.event)
 var prefix:="doctor%d:"%event
 var ended:=Rules.flag(profile,"ended",event)
 var started:=Rules.flag(profile,"now",event)
 var species:=74 if event==15 else 191
 var level:=15 if event==15 else 30
 var name:="鲁尼帖斯" if event==15 else "贝鲁卡"
 var predicate:="PET>%d-%d"%[level-1,species]
 var eligible:=Rules.pet_index(profile,predicate)
 var request:Dictionary={}
 var exchange:Dictionary={}
 var assistant:Dictionary={}
 for npc in backend.quest_catalog.active_npcs():
  for branch in npc.branches:
   if int(branch.event)==event and str(branch.type)=="REQUEST":request={"npc":npc,"branch":branch}
   if int(branch.event)==event and str(branch.type)=="ACCEPT":exchange={"npc":npc,"branch":branch}
   if event==15 and str(npc.id)=="sainasu/event/event15_2":assistant={"npc":npc,"branch":branch}
 add_step(backend,profile,quest,prefix+"request",request,not started and not ended,started or ended,"向恐龙博士哈鲁领取委托（角色%d级%s）"%[10 if event==15 else 16,"" if event==15 else "，先完成鲁尼帖斯委托"])
 if not assistant.is_empty():
  add_step(backend,profile,quest,prefix+"assistant",assistant,started and not ended,false,"向助手吉鲁了解原版捕获与培养说明")
  if not quest.steps.is_empty() and quest.steps[-1].id==prefix+"assistant":quest.steps[-1].optional=true
 var target:=capture_step(backend,species)
 var held:Array=[]
 for pet in profile.pets:
  if str(pet.get("species",""))=="original_%d"%species:held.append("%s Lv.%d%s"%[str(pet.get("pet_id","")),int(pet.level),"（事件或来源不明，不可交付）" if Rules.Session.original_pet_event(pet)!=0 else ""])
 var detail:="捕获普通%s并培养至%d级；只交随身栏首个符合宠物%s"%[name,level,"；当前："+"、".join(held) if not held.is_empty() else "；尚未持有"]
 if target.is_empty():
  quest.steps.append({"id":prefix+"capture","npc_id":"","current":started and eligible<0 and not ended,"done":eligible>=0 or ended,"actionable":false,"label":detail+"（尚无已导入捕获地点）","source":{"type":"pet_requirement","species":species,"level":level,"original_end_event":0}})
 else:
  target.id=prefix+"capture";target.current=started and eligible<0 and not ended;target.done=eligible>=0 or ended;target.actionable=target.current
  target.label=detail+" · %s (%d,%d)"%[places.map_name(int(target.map_id)),int(target.cell[0]),int(target.cell[1])]
  quest.steps.append(target)
 add_step(backend,profile,quest,prefix+"return",exchange,started and eligible>=0 and not ended,ended,"交付%s%s，领取%s"%[name,"（"+str(profile.pets[eligible].pet_id)+"）" if eligible>=0 else "", "八种原物品之一" if event==15 else "1级布克布克"])
 if started and eligible<0 and not ended:quest.blocked_reason="需要普通%s至少%d级；事件宠和来源不明宠不能交付"%[name,level]
 quest.completion_detail="博士须从深红洞窟公开入口沿六层原路抵达；不增成人礼条件。助手只送公开入口或合法近处原地。原任务无重做入口；博士自动任务尚未开放"

func capture_step(backend,species:int) -> Dictionary:
 var data:Dictionary=backend.encounter_catalog.data
 for area in data.get("areas",[]):
  if int(area.map_id)!=(100 if species==74 else 200) or places.info(int(area.map_id)).is_empty():continue
  if area.get("invalid_weights",false) or int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:continue
  for choice in area.groups:
   var group:Dictionary=data.get("groups",{}).get(str(int(choice.id)),{})
   if group.get("invalid_weights",false) or int(group.get("requires_item",-1))>=0 or int(group.get("excludes_item",-1))>=0:continue
   for member in group.get("enemies",[]):
    var enemy:Dictionary=data.get("enemies",{}).get(str(int(member.id)),{})
    if int(enemy.get("template_id",-1))!=species or int(enemy.get("pet_flag",0))!=1:continue
    var rect:Array=area.rect
    var point:=[(int(rect[0])+int(rect[2]))/2,(int(rect[1])+int(rect[3]))/2]
    var target:=destination(backend,{"id":"","map_id":int(area.map_id),"cell":point,"area_rect":rect},"near")
    if target.is_empty():continue
    var actual:Dictionary=backend.encounter_catalog.area_at(int(area.map_id),Vector2i(int(target.cell[0]),int(target.cell[1])))
    if int(actual.get("id",-1))!=int(area.id):continue
    return {"id":"","npc_id":"","map_id":int(area.map_id),"cell":target.cell,"current":false,"done":false,"actionable":false,"source":{"type":"encounter","area_id":int(area.id),"area_rect":rect.duplicate(),"area_source_line":int(area.get("source_line",0)),"enemy_id":int(enemy.id),"species":species,"level_min":int(enemy.level_min),"level_max":int(enemy.level_max),"original_end_event":0}}
 return {}

func adult_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
 var ended:=Rules.flag(profile,"ended",4)
 var started:=Rules.flag(profile,"now",4)
 var held:int=profile.original_items.count(2417)
 var request:Dictionary={}
 for npc in backend.quest_catalog.active_npcs():
  for branch in npc.branches:
   if int(branch.event)==4 and str(branch.type)=="REQUEST":request={"npc":npc,"branch":branch}
 add_step(backend,profile,quest,"adult:request",request,not started and not ended,started or ended,"向审判领取成人仪式")
 add_step(backend,profile,quest,"adult:jade",pick(backend,profile,candidates(backend,4,"GetItem",2417)),started and held==0 and not ended,held>=15 or ended,"向通道尽头差使领取十五个仪玉（需十五空格）")
 add_step(backend,profile,quest,"adult:return",pick(backend,profile,candidates(backend,4,"DelItem",2417)),started and held>0 and not ended,ended,"返回审判交付十五个仪玉，领取仪之兜")
 quest.completion_detail="原入口要求等级30，助手只送入口外；洞内远处须沿原通道步行，已合法抵达且在可谈距离时助手保持原地。自动任务从原等级门进入并往返步行；接任务仍按原LV>0。仪玉由差使发放，非战斗掉落。"

func wood_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
 quest.completion_detail="木洞内须从公开原入口沿原路步行；助手只送入口或合法近处原地。村内原持物交付不增洞内条件。"
 var items:Array=profile.original_items
 var ended:=Rules.flag(profile,"ended",18)
 var stage:=0
 if 2466 in items:stage=1
 if 2463 in items:stage=2
 if 2464 in items:stage=3
 if 2465 in items:stage=4
 if ended:stage=8
 if 2467 in items:stage=5
 if 2478 in items:stage=6 if items.count(2468)==0 else 7
 elif 2468 in items:stage=5 # original no-permit refusal before recommendation
 var ids:Array=["commission","pot","fill","axe","recommendation","permit"]
 var outputs:Array=[2466,2463,2464,2465,2467,2478]
 for index in range(ids.size()):
  var entry:Dictionary=pick(backend,profile,candidates(backend,18,"GetItem",int(outputs[index])))
  add_step(backend,profile,quest,"wood:"+str(ids[index]),entry,stage==index,(stage>index and stage<8) or (ended and index<5))
 var harvest:Dictionary=harvest_step(backend)
 if not harvest.is_empty():
  harvest.current=stage==6
  harvest.done=stage==7
  harvest.actionable=stage==6
  harvest.label="持%s采集%s（当前%d件） · %s (%d,%d)" % [item_names(backend.quest_catalog,"2478"),item_names(backend.quest_catalog,"2468"),items.count(2468),places.map_name(int(harvest.map_id)),int(harvest.cell[0]),int(harvest.cell[1])]
  quest.steps.append(harvest)
 var exchanges:Array=candidates(backend,18,"DelItem",2478)
 var entry:Dictionary=pick(backend,profile,exchanges)
 var caption:="向赛尚兑换木材（按原数量结算）"
 if not entry.is_empty() and backend.original_quests.branch_for(entry.npc,profile,str(entry.branch.get("spoken_keyword","")))==entry.branch:caption=label_for(backend.quest_catalog,entry.npc,entry.branch)
 add_step(backend,profile,quest,"wood:exchange",entry,stage==7,false,caption)
 if ended:quest.completion_detail="交斧已完成；当前许可证、推荐书与木材继续按原分支处理"

func restart_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
 for npc in backend.quest_catalog.active_npcs():
  var selected:Dictionary=backend.original_quests.branch_for(npc,profile)
  if int(quest.event)==18 and not selected.is_empty() and 2485 in Rules.item_list(str(selected.actions.get("GetItem",""))):
   add_step(backend,profile,quest,"wood:optional_axe",{"npc":npc,"branch":selected},false,false,"可选："+label_for(backend.quest_catalog,npc,selected))
   if not quest.steps.is_empty() and str(quest.steps[-1].id)=="wood:optional_axe":
    quest.steps[-1].optional=true
    quest.steps[-1].actionable=true
  for index in range(npc.branches.size()):
   var branch:Dictionary=npc.branches[index]
   if not branch.get("events",[]).any(func(value):return int(value)==int(quest.event)):continue
   if str(branch.type)!="CLEAN":continue
   if str(quest.event) in str(branch.actions.get("CleanFlg","")).split(","):quest.repeatable=true
   if selected!=branch:continue
   if str(quest.event) in str(branch.actions.get("CleanFlg","")).split(","):quest.can_restart=true
   add_step(backend,profile,quest,"restart:"+str(npc.id),{"npc":npc,"branch":branch,"index":index},false,false)

func harvest_step(backend) -> Dictionary:
 var data:Dictionary=backend.encounter_catalog.data
 var enemy:Dictionary=data.get("enemies",{}).get("563",{})
 if enemy.is_empty() or not enemy.get("drops",[]).any(func(drop):return int(drop.item_id)==2468):return {}
 for area in data.get("areas",[]):
  if int(area.id) not in [88,267] or places.info(int(area.map_id)).is_empty():continue
  var eligible:=false
  if area.get("invalid_weights",false) or int(area.get("event_now",-1))>0 or int(area.get("event_end",-1))>0:continue
  for choice in area.groups:
   var group:Dictionary=data.get("groups",{}).get(str(int(choice.id)),{})
   if int(group.get("requires_item",-1))==2478 and group.get("enemies",[]).any(func(entry):return int(entry.id)==563):eligible=true
  if not eligible:return {}
  var rect:Array=area.rect
  var point:=Vector2i((int(rect[0])+int(rect[2]))/2,(int(rect[1])+int(rect[3]))/2)
  var target:Dictionary=destination(backend,{"id":"","map_id":int(area.map_id),"cell":[point.x,point.y],"area_rect":rect},"near")
  if target.is_empty():continue
  # Overlapping source rectangles are not interchangeable: equal-priority
  # areas retain the first source row, exactly as ENCOUNT_getEncountAreaArray.
  # Search the traversable component of the old landing, not a rectangle-only
  # midpoint that can be shadowed by an earlier area without the wood group.
  var map_id:=int(area.map_id)
  var geometry_key:=[backend.encounter_catalog.get_instance_id(),backend.quest_catalog.get_instance_id(),backend.quest_catalog.enabled_events,backend.original_quests.npc_state.version,int(area.id)]
  var cached:Dictionary=get_meta("wood_harvest_geometry",{})
  if cached.get("key",[])==geometry_key:
   target=cached.target.duplicate(true)
  else:
   var map_data:Dictionary=maps[map_id]
   var occupied:Dictionary={}
   for resident in places.residents:
    if int(resident.map_id)==map_id:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
   for resident in backend.quest_catalog.active_npcs():
    if int(resident.map_id)==map_id:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
   var links:Dictionary=places.links(map_id)
   var origin:=Vector2i(int(target.cell[0]),int(target.cell[1]))
   var queue:Array[Vector2i]=[origin]
   var seen:Dictionary={origin:true}
   var cursor:=0
   target={}
   while cursor<queue.size():
    var candidate:Vector2i=queue[cursor]
    cursor+=1
    if int(backend.encounter_catalog.area_at(map_id,candidate).get("id",-1))==int(area.id):
     target={"map_id":map_id,"cell":[candidate.x,candidate.y],"npc_id":""}
     break
    for offset in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.DOWN,Vector2i.UP]:
     var next:Vector2i=candidate+offset
     if seen.has(next) or next.x<int(rect[0]) or next.y<int(rect[1]) or next.x>int(rect[2]) or next.y>int(rect[3]):continue
     seen[next]=true
     if safe(map_data,next,occupied,links):queue.append(next)
   set_meta("wood_harvest_geometry",{"key":geometry_key.duplicate(true),"target":target.duplicate(true)})
  if target.is_empty():continue
  return {"id":"wood:harvest","npc_id":"","map_id":int(area.map_id),"cell":target.cell,"current":false,"done":false,"actionable":false,"source":{"type":"encounter","area_id":int(area.id),"area_rect":rect.duplicate(),"area_source_line":int(area.get("source_line",0)),"enemy_id":563,"drops":enemy.drops.duplicate(true)}}
 return {}

func resolve_step(backend,quest_id:int,step_id:String) -> Dictionary:
 for quest in snapshot(backend).quests:
  if int(quest.id)!=quest_id:continue
  for step in quest.steps:
   if str(step.id)==step_id:
    if int(quest.event) in transmigration.EVENTS and not transmigration.can_visit(self,backend,int(quest.event),step):return {}
    if int(quest.event) in [28,31] and not preload("res://server/brothers_arrival_helper.gd").can_visit(self,backend,step):return {}
    if int(quest.event) in [29,30,54] and not preload("res://server/golden_arrival_helper.gd").can_visit(self,backend,step):return {}
    if int(quest.event)==44 and not GoldenBui.can_visit(step):return {}
    if int(quest.event) in [20,21,22] and not preload("res://server/jan_cave_helper.gd").can_visit(step):return {}
    if int(quest.event)==13 and not preload("res://server/saton_cave_helper.gd").can_visit(self,backend,step):return {}
    if int(quest.event)==9 and not preload("res://server/munde_cave_helper.gd").can_visit(step):return {}
    return step
 return {}

func item_names(catalog, raw: String) -> String:
 var names: Array = []
 for entry in raw.split(",",false):
  var parts := entry.split("*")
  var item:Dictionary=catalog.items.get(parts[0],{})
  var name := str(item.get("name",parts[0]))
  var description:=str(item.get("description",""))
  if description.contains("现在是空的"):name+="（空）"
  elif description.contains("水满了"):name+="（满）"
  names.append(name+(" ×"+parts[1] if parts.size()>1 else ""))
 return "、".join(names)

func label_for(catalog, npc: Dictionary, branch: Dictionary) -> String:
 var actions: Dictionary = branch.actions
 if str(branch.type)=="CLEAN":return "与%s交谈，重置任务" % npc.name
 if actions.is_empty():return str(branch.texts.get("NomalWindowMsg",branch.texts.get("MessageMsg","与%s交谈，查看原任务提示" % npc.name)))
 var parts: Array = []
 if actions.has("DelItem"):parts.append("交付"+item_names(catalog,str(actions.DelItem)))
 if actions.has("GetItem"):parts.append("领取"+item_names(catalog,str(actions.GetItem)))
 if actions.has("GetStone"):parts.append("兑换%s石币" % actions.GetStone)
 return "%s：%s" % [npc.name,"，".join(parts)]

func adult_walk_destination(backend,npc:Dictionary)->Dictionary:
 # Geometry only, used by the server's real step runner, never by a
 # client travel receipt. Clearing events only avoids this local dispatch.
 if int(npc.get("map_id",-1))!=10204:return {}
 var plain:=npc.duplicate(true);plain.events=[]
 return destination(backend,plain,"near")

func adult_destination(backend,npc:Dictionary)->Dictionary:
 if int(npc.get("map_id",-1))!=10204:return {}
 var current:Vector2i=backend.automation.position_cell
 if backend.automation.position_map!=10204 or not backend.quest_arrival.has_arrival(backend,10204,current):
  var outside:Dictionary=destination(backend,{"id":"","map_id":10202,"cell":[30,13],"events":[]},"near")
  if outside.is_empty():return {}
  outside.npc_id=str(npc.id)
  return outside
 var branch:Dictionary=backend.original_quests.branch_for(npc,backend.session.snapshot())
 if not backend.quest_arrival.check_action(backend,npc,branch,str(branch.get("type",""))).is_empty():return {}
 var target:=Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 if maxi(absi(current.x-target.x),absi(current.y-target.y))>2:return {}
 var near:=adult_walk_destination(backend,npc)
 if near.is_empty() or not backend.quest_arrival.has_arrival(backend,10204,Vector2i(int(near.cell[0]),int(near.cell[1]))):return {}
 return {"map_id":10204,"cell":[current.x,current.y],"npc_id":str(npc.id)}

func destination(backend, npc: Dictionary, mode: String) -> Dictionary:
 if preload("res://server/transmigration_final_helper.gd").owns(npc):return preload("res://server/transmigration_final_helper.gd").destination(self,backend,npc,mode)
 if LegacyCave.owns(npc) and int(npc.map_id) not in range(10701,10706):return LegacyCave.destination(self,backend,npc,mode)
 if preload("res://server/golden_arrival_helper.gd").owns(npc):return preload("res://server/golden_arrival_helper.gd").destination(self,backend,npc,mode)
 if preload("res://server/brothers_arrival_helper.gd").owns(npc):return preload("res://server/brothers_arrival_helper.gd").destination(self,backend,npc,mode)
 if npc.get("events",[]).any(func(event):return int(event)==4):return adult_destination(backend,npc)
 if npc.get("events",[]).any(func(event):return int(event) in [32,33,34]):return Dream.destination(self,backend,npc,mode)
 if preload("res://server/saton_cave_helper.gd").owns(npc) and int(npc.map_id) in range(10701,10706):return preload("res://server/saton_cave_helper.gd").destination(self,backend,npc,mode)
 if npc.get("events",[]).any(func(event):return int(event)==17):return Dragon.destination(self,backend,npc,mode)
 if npc.get("events",[]).any(func(event):return int(event) in [37,38]):return Marju.destination(self,backend,npc,mode)
 if preload("res://server/jan_cave_helper.gd").owns(npc) and int(npc.map_id) in range(20601,20609):return preload("res://server/jan_cave_helper.gd").destination(self,backend,npc,mode)
 if GoldenBui.owns(npc):return GoldenBui.destination(self,backend,npc,mode)
 if preload("res://server/munde_cave_helper.gd").owns(npc) and int(npc.map_id)==11107:
  var munde=preload("res://server/munde_cave_helper.gd")
  var boundary:Dictionary=munde.destination(self,backend,npc,mode)
  if boundary.is_empty():return {}
  # event12 is one shared physical NPC. The already enabled Munde route
  # remains a valid owner; inactive/locked wind must not revoke it. Both
  # owners are always bounded by the original Munde guard component.
  if 9 in backend.quest_catalog.enabled_events or not transmigration.owns(npc):return boundary
  var target:Dictionary=transmigration.destination(self,backend,npc,mode)
  if target.is_empty() or int(target.get("map_id",-1))!=11107:return {}
  var cell:Array=target.get("cell",[])
  if cell.size()!=2 or munde.region_at(self,backend,Vector2i(int(cell[0]),int(cell[1])))!=munde.region_at(self,backend,backend.automation.position_cell):return {}
  return target
 if transmigration.owns(npc):return transmigration.destination(self,backend,npc,mode)
 return geometric_destination(backend,npc,mode)

func geometric_destination(backend,npc:Dictionary,mode:String)->Dictionary:
 var world = places
 world.set_quest_catalog(backend.quest_catalog)
 var map_id := int(npc.map_id)
 if not world.maps.has(str(map_id)):return {}
 if not maps.has(map_id):maps[map_id]=MapFile.load_map(world.file(map_id))
 var data:Dictionary=maps[map_id]
 if data.is_empty():return {}
 var occupied := {}
 for resident in world.residents:
  if int(resident.map_id)==map_id:occupied[Vector2i(int(resident.cell[0]),int(resident.cell[1]))]=true
 for entry in backend.quest_catalog.active_npcs_on_map(map_id):
  if int(entry.map_id)==map_id:occupied[Vector2i(int(entry.cell[0]),int(entry.cell[1]))]=true
 if map_id==1000 and FileAccess.file_exists("res://assets/legacy/samgir-npc.json"):
  var special = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir-npc.json"))
  if special is Dictionary:occupied[Vector2i(int(special.cell[0]),int(special.cell[1]))]=true
 if map_id==1002 and FileAccess.file_exists("res://assets/legacy/mvp/manifest.json"):
  var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/mvp/manifest.json"))
  if manifest is Dictionary and manifest.get("merchant",{}).has("cell"):
   var merchant: Array = manifest.merchant.cell
   occupied[Vector2i(int(merchant[0]),int(merchant[1]))]=true
 var links: Dictionary = world.links(map_id)
 var target := Vector2i(int(npc.cell[0]),int(npc.cell[1]))
 var neighbours: Array[Vector2i] = []
 var region:Array=npc.get("area_rect",[])
 if str(npc.id).is_empty() and safe(data,target,occupied,links):neighbours.append(target)
 for offset in preload("res://scripts/npc_interaction.gd").offsets():
  var cell: Vector2i = target+offset
  if safe(data,cell,occupied,links) and (region.is_empty() or cell.x>=int(region[0]) and cell.y>=int(region[1]) and cell.x<=int(region[2]) and cell.y<=int(region[3])):neighbours.append(cell)
 if neighbours.is_empty():return {}
 if mode=="near":return {"map_id":map_id,"cell":[neighbours[0].x,neighbours[0].y],"npc_id":str(npc.id)}
 # Flood the actual traversable component from NPC-adjacent cells. Arrival
 # must share it; geometrically free cells behind walls are rejected.
 var reachable := {}
 var queue: Array[Vector2i] = neighbours.duplicate()
 for cell in queue:reachable[cell]=true
 var spawn: Array = world.info(map_id).get("spawn",data.get("spawn",[]))
 if spawn.size()<2:return {}
 var origin := Vector2i(int(spawn[0]),int(spawn[1]))
 var cursor := 0
 while cursor<queue.size():
  var cell := queue[cursor]
  cursor+=1
  if maxi(absi(cell.x-origin.x),absi(cell.y-origin.y))<=32:return {"map_id":map_id,"cell":[cell.x,cell.y],"npc_id":str(npc.id)}
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next: Vector2i = cell+offset
   if not reachable.has(next) and safe(data,next,occupied,links):reachable[next]=true;queue.append(next)

 return {}

func safe(data: Dictionary, cell: Vector2i, occupied: Dictionary, links: Dictionary) -> bool:
 if not Rect2i(0,0,int(data.width),int(data.height)).has_point(cell):return false
 var index := cell.y*int(data.width)+cell.x
 return int(data.blocked[index])==0 and int(data.ground[index])!=0 and not occupied.has(cell) and not links.has(cell)
