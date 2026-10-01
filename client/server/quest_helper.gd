extends RefCounted
## Canonical server projection; every NPC action keeps its original source.
const Rules = preload("res://server/original_quests.gd")
const WorldCatalog = preload("res://scripts/world_catalog.gd")
const MapFile = preload("res://scripts/map_file.gd")
var places = WorldCatalog.new()
var maps := {}
var cached_key := ""
var cached_snapshot := {}

func snapshot(backend) -> Dictionary:
 # Read only the trusted server profile. Ordinary battle/hunt publications do
 # not need to copy a potentially large pet warehouse or rebuild task recipes.
 var profile: Dictionary = backend.session._profile
 var catalog = backend.quest_catalog
 var key := JSON.stringify([catalog.get_instance_id(),catalog.enabled_events,profile.original_events,profile.original_items,profile.original_savepoint_bits,profile.player.level])
 if key == cached_key:return cached_snapshot.duplicate(true)
 var quests: Array = []
 for job in catalog.jobs:
  var event := int(job.event)
  var enabled: bool = event in catalog.enabled_events
  var ended := Rules.flag(profile,"ended",event)
  var quest := {"id":int(job.id),"event":event,"title":str(job.title),"status":"已完成" if ended else ("进行中" if Rules.flag(profile,"now",event) else "未开始"),"repeatable":false,"can_restart":false,"blocked_reason":"" if enabled else "尚未开放","steps":[]}
  if enabled:
   if event==2:shell_steps(backend,profile,quest)
   elif event==18:wood_steps(backend,profile,quest)
   restart_steps(backend,profile,quest)
   if ended and quest.repeatable and not quest.can_restart and str(quest.blocked_reason).is_empty():quest.blocked_reason="可重做；当前尚未满足原任务清理条件"
  for step in quest.steps:step.quest_id=int(job.id)
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
  if backend.original_quests.branch_for(entry.npc,profile)==entry.branch:return entry
 return options[0] if not options.is_empty() else {}

func add_step(backend,profile:Dictionary,quest:Dictionary,id:String,entry:Dictionary,current:bool,done:bool,label:String="") -> void:
 if entry.is_empty():return
 var npc:Dictionary=entry.npc
 var branch:Dictionary=entry.branch
 if places.info(int(npc.map_id)).is_empty() or not FileAccess.file_exists(places.file(int(npc.map_id))):return
 var selected:Dictionary=backend.original_quests.branch_for(npc,profile)
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

func wood_steps(backend,profile:Dictionary,quest:Dictionary) -> void:
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
 if not entry.is_empty() and backend.original_quests.branch_for(entry.npc,profile)==entry.branch:caption=label_for(backend.quest_catalog,entry.npc,entry.branch)
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
  for choice in area.groups:
   var group:Dictionary=data.get("groups",{}).get(str(int(choice.id)),{})
   if int(group.get("requires_item",-1))==2478 and group.get("enemies",[]).any(func(entry):return int(entry.id)==563):eligible=true
  if not eligible:return {}
  var rect:Array=area.rect
  var point:=Vector2i((int(rect[0])+int(rect[2]))/2,(int(rect[1])+int(rect[3]))/2)
  var target:Dictionary=destination(backend,{"id":"","map_id":int(area.map_id),"cell":[point.x,point.y],"area_rect":rect},"near")
  if target.is_empty():continue
  return {"id":"wood:harvest","npc_id":"","map_id":int(area.map_id),"cell":target.cell,"current":false,"done":false,"actionable":false,"source":{"type":"encounter","area_id":int(area.id),"area_rect":rect.duplicate(),"area_source_line":int(area.get("source_line",0)),"enemy_id":563,"drops":enemy.drops.duplicate(true)}}
 return {}

func resolve_step(backend,quest_id:int,step_id:String) -> Dictionary:
 for quest in snapshot(backend).quests:
  if int(quest.id)!=quest_id:continue
  for step in quest.steps:
   if str(step.id)==step_id:return step
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

func destination(backend, npc: Dictionary, mode: String) -> Dictionary:
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
 for entry in backend.quest_catalog.active_npcs():
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
 for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
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
