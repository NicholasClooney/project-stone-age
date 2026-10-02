extends RefCounted
## Source-script interpreter. Pending dialogues are server-owned and single use.
const Session = preload("res://server/game_session.gd")
const Progression = preload("res://server/progression.gd")
const Charm = preload("res://server/original_charm.gd")
const Brothers = preload("res://server/brothers_quests.gd")
const Loyalty = preload("res://server/loyalty.gd")
var catalog
var services = preload("res://server/original_quest_services.gd").new()
var npc_state = preload("res://server/quest_npc_state.gd").new()
var pending := {}
var serial := 0
# gmsv/include/version.h:241 enables _FIX_MAX_GOLD; char/char_base.c:
# CHAR_getMaxHaveGold = 1,000,000 + transmigration * 1,800,000.
# This game has no transmigration feature, so original NPC exchanges use its
# untransmigrated limit, independent of the prototype combat currency limit.
const ORIGINAL_MAX_GOLD := 1000000

static func flag(profile: Dictionary, kind: String, event: int) -> bool:
	return event>=0 and event<192 and (int(profile.original_events[kind][event >> 5]) & (1 << (event%32)))!=0

static func set_flag(profile: Dictionary, kind: String, event: int, on: bool) -> void:
	if event<0 or event>=192:return
	var word := int(profile.original_events[kind][event >> 5])
	profile.original_events[kind][event >> 5] = (word | (1 << (event%32))) if on else (word & ~(1 << (event%32)))

static func matches(profile: Dictionary, condition: String) -> bool:
	for alternative in condition.split(","):
		var accepted := true
		var pet_predicates: Array[String] = []
		for predicate in alternative.split("&"):
			if predicate.begins_with("PET"):
				pet_predicates.append(predicate)
				continue
			var regex := RegEx.new()
			regex.compile("^(NOWEV|ENDEV|ITEM|SP|LV)(!=|=|>)([0-9]+)(?:\\*([0-9]+))?$")
			var found := regex.search(predicate.strip_edges())
			if found==null:accepted=false;break
			var kind := found.get_string(1)
			var op := found.get_string(2)
			var number := int(found.get_string(3))
			var result := false
			match kind:
				"NOWEV","ENDEV":result=flag(profile,"now" if kind=="NOWEV" else "ended",number)
				"ITEM":
					# C NPC_EventBigSmallCheck handles != before the * quantity
					# branch: ITEM!=id*n still means no such item in the bag.
					var quantified := op=="=" and not found.get_string(4).is_empty()
					result=item_count(profile,number,quantified)>=(maxi(1,int(found.get_string(4))) if quantified else 1)
				"SP":result=number<4 and (int(profile.original_savepoint_bits)&(1<<number))!=0
				"LV":result=int(profile.player.level)>number if op==">" else int(profile.player.level)==number
			if op=="!=":result=not result
			if op==">" and kind!="LV":result=false
			if not result:accepted=false;break
		if accepted and (pet_predicates.is_empty() or not pet_indices(profile,",".join(pet_predicates)).is_empty()):return true
	return false

## Unquantified ITEM checks use the bag (C NPC_EventItemCheck:1051).
## ITEM=id*n uses all carried slots, including worn ones (EventReduce:3689).
static func item_count(profile: Dictionary, item: int, include_equipped := false) -> int:
	var count: int=profile.original_items.count(item)
	if include_equipped:return count
	for instance in profile.get("original_instances",[]):
		if int(instance.item_id)==item and Session.OriginalEquipment.worn(profile,int(instance.uid)):count-=1
	return maxi(0,count)

static func worn_item_hint(profile: Dictionary, condition: String) -> String:
	# Explain only a predicate that actually fails because its last copy is worn.
	var regex := RegEx.new()
	regex.compile("(?:^|[&,])ITEM=([0-9]+)(?=$|[&,])")
	for found in regex.search_all(condition):
		var item := int(found.get_string(1))
		if item_count(profile,item)==0 and item_count(profile,item,true)>0:
			return "原任务只检查背包中的道具；请先卸下需要交付的装备。"
	return ""

static func pet_index(profile: Dictionary, predicate: String) -> int:
	var indices := pet_indices(profile,predicate)
	return -1 if indices.is_empty() else int(indices[0])

## Resolve all source predicates against distinct carried UIDs. Return no partial
## result if any pet is absent; source counts other than *1 remain unsupported.
static func pet_indices(profile: Dictionary, raw: String) -> Array:
	if raw.is_empty():return []
	var predicates := []
	var regex := RegEx.new()
	regex.compile("^PET([>=])([0-9]+)-([0-9]+)(?:\\*1)?$")
	for entry in raw.split(","):
		var found := regex.search(entry)
		if found==null:return []
		predicates.append({"op":found.get_string(1),"level":int(found.get_string(2)),"species":"original_%d"%int(found.get_string(3))})
	if predicates.size()>profile.pets.size():return []
	return _select_pets(profile,predicates,0,[])

static func _select_pets(profile: Dictionary, predicates: Array, offset: int, used: Array) -> Array:
	if offset==predicates.size():return used
	var predicate: Dictionary=predicates[offset]
	for index in range(profile.pets.size()):
		if index in used:continue
		var pet: Dictionary=profile.pets[index]
		if str(pet.get("species",""))!=predicate.species or Session.original_pet_event(pet)!=0:continue
		if not (int(pet.level)>int(predicate.level) if predicate.op==">" else int(pet.level)==int(predicate.level)):continue
		var selected := used.duplicate()
		selected.append(index)
		var resolved := _select_pets(profile,predicates,offset+1,selected)
		if not resolved.is_empty():return resolved
	return []

static func pet_ids(profile: Dictionary, raw: String) -> Array:
	return pet_indices(profile,raw).map(func(index):return str(profile.pets[index].pet_id))

func refresh_npc_state() -> bool:
	var changed:bool=npc_state.expire()
	catalog.npc_overrides=npc_state.snapshot()
	return changed

func npc_by_id(id: String) -> Dictionary:
	refresh_npc_state()
	for npc in catalog.active_npcs():
		if str(npc.id)==id:return npc
	return {}

func branch_for(npc: Dictionary, profile: Dictionary) -> Dictionary:
	for branch in npc.get("branches",[]):
		if int(branch.event)>=0 and flag(profile,"ended",int(branch.event)):continue
		if matches(profile,str(branch.condition)):return branch
	return {}

func allowed(backend, npc: Dictionary) -> bool:
	var current := npc_by_id(str(npc.id))
	if current.is_empty() or current.map_id!=npc.map_id or current.cell!=npc.cell:return false
	if backend.quest_auto.running and not backend.quest_auto.internal:return false
	if backend.battle_open or not backend.session._pending.is_empty() or backend.automation.running or backend.automation.hunt_running or backend.automation.flow_active():return false
	var cell: Array = npc.cell
	return backend.automation.position_map==int(npc.map_id) and maxi(absi(backend.automation.position_cell.x-int(cell[0])),absi(backend.automation.position_cell.y-int(cell[1])))<=2

func window(npc: Dictionary, branch: Dictionary, phase: String, text: String, confirm: bool) -> Dictionary:
	if int(branch.get("guard",{}).get("dieact",1))==0 or branch.get("actions",{}).has("NpcWarp"):
		text+="\n【项目规则】原版为全服共享，本项目按角色各自计算；服务器重启复位。"
	serial+=1
	var token := "%d-%d" % [Time.get_ticks_usec(),serial]
	pending={"token":token,"npc":npc,"branch":branch,"phase":phase}
	return {"ok":true,"dialogue":{"token":token,"npc_id":npc.id,"name":npc.name,"text":text,"choices":[{"id":"yes","text":"是"},{"id":"no","text":"否"}] if confirm else [{"id":"ok","text":"确定"}]}}

## NPC_EventGetCost (npc_exchangeman.c:3960-3974), reviewed cost subset.
## Return -1 on unknown syntax or C signed-int overflow, before any mutation.
static func stone_cost(profile: Dictionary, expression: String) -> int:
	if expression in ["LV*20","LV*40"]:
		var factor := 20 if expression=="LV*20" else 40
		var level := int(profile.player.level)
		if level<0 or level>2147483647/factor:return -1
		return level*factor
	if expression.is_empty() or expression.length()>10:return -1
	for character in expression:
		if character<"0" or character>"9":return -1
	var fee := int(expression)
	return fee if fee<=2147483647 else -1


static func message(texts: Dictionary, key: String) -> String:
	# Original scripts use both unnumbered and ordered numbered message fields.
	var parts: Array[String] = []
	if texts.has(key):parts.append(str(texts[key]))
	for index in range(1,10):
		if texts.has(key+str(index)):parts.append(str(texts[key+str(index)]))
	return "\n".join(parts)

func talk(backend, id: String) -> Dictionary:
	pending={}
	var npc := npc_by_id(id)
	if npc.is_empty() or not allowed(backend,npc):return {"ok":false,"reason":"任务人物不在附近，或当前正忙。"}
	if str(npc.get("handler",""))=="Charm":return Charm.talk(self,backend,npc)
	if npc.has("kind"):
		if str(npc.kind) not in services.KINDS:return {"ok":false,"reason":"尚未开放的原服务类型。"}
		return services.open(self,backend,npc)
	for gate in npc.get("branches",[]):
		if str(gate.get("type",""))=="FREEWARP" and backend.quest_visit_guard.is_valid() and not str(backend.quest_visit_guard.call()).is_empty():
			return window(npc,{},"end",str(gate.source_fields.get("PartyMsg","无法加入团队。请解散团队。")).replace("\\n","\n"),false)
	var profile: Dictionary=backend.session.snapshot()
	var branch := branch_for(npc,profile)
	if branch.is_empty():return window(npc,branch,"end",str(npc.get("text","")),false)
	for action in branch.actions:
		if action not in ["GetItem","DelItem","GetStone","DelStone","EndSetFlg","CleanFlg","DelPet","GetPet","GetRandItem","Charm","Warp","Battle","NpcWarp"]:return {"ok":false,"reason":"尚未支持的任务动作。"}
	var phase: String=str(branch.type)
	if phase=="MESSAGE":
		var result := transact(backend,profile,branch,"MESSAGE","",str(npc.id))
		if not result.ok:return result
		return window(npc,branch,"end",message(branch.texts,"NomalWindowMsg") if branch.texts.has("NomalWindowMsg") else message(branch.texts,"NomalMsg"),false)
	if phase=="REQUEST" and flag(profile,"now",int(branch.event)):phase="cancel"
	var keys := {"FREEWARP":"AcceptMsg","KEYWORD":"AcceptMsg","BATTLE":"AcceptMsg","REQUEST":"RequestMsg","ACCEPT":"AcceptMsg","CLEAN":"CleanMainMsg","cancel":"StopMsg"}
	if not keys.has(phase):return {"ok":false,"reason":"尚未支持的任务分支。"}
	var prompt := str(branch.get("confirmation_text",message(branch.texts,keys[phase])))
	if branch.actions.has("DelStone"):
		var fee := stone_cost(profile,str(branch.actions.DelStone))
		if fee<0:return {"ok":false,"reason":"尚未支持的原费用。"}
		prompt=prompt.replace("%8d","%8d" % fee)
	var reply := window(npc,branch,phase,prompt,true)
	if phase=="KEYWORD":
		reply.dialogue.merge({"kind":"original_keyword","input":"text","choices":[{"id":"submit","text":"说出口令"},{"id":"no","text":"取消"}]},true)
	if phase=="ACCEPT" and branch.actions.has("DelPet"):
		var selected := pet_ids(profile,str(branch.actions.DelPet))
		if selected.is_empty():
			pending={}
			return {"ok":false,"reason":"交付宠物已经改变。"}
		pending.pet_ids=selected
	return reply

func choose(backend, token: String, choice: String, text: String = "") -> Dictionary:
	if pending.is_empty() or token!=str(pending.token):return {"ok":false,"reason":"对话已过期。"}
	var current: Dictionary=pending.duplicate(true)
	pending={}
	var npc: Dictionary=current.npc
	if not allowed(backend,npc):return {"ok":false,"reason":"位置或活动状态已经改变。"}
	if current.has("service_state"):return services.reply(self,backend,current,choice,text)
	var branch: Dictionary=current.branch
	var phase: String=current.phase
	if phase=="end":return {"ok":choice=="ok","closed":true}
	if str(npc.get("handler",""))=="Charm":return Charm.choose(self,backend,current,choice)
	var profile: Dictionary=backend.session.snapshot()
	if (phase=="REQUEST" and flag(profile,"now",int(branch.event))) or (phase=="cancel" and not flag(profile,"now",int(branch.event))):return {"ok":false,"reason":"任务状态已经改变。"}
	if branch_for(npc,profile)!=branch:return {"ok":false,"reason":"任务状态已经改变。"}
	if choice=="no":
		if phase=="cancel":return window(npc,branch,"end",str(branch.texts.get("NoStopMsg","")),false)
		return {"ok":true,"closed":true}
	if phase=="FREEWARP":
		if choice!="yes":return {"ok":false,"reason":"无效选择。"}
		var committed := transact(backend,profile,branch,"FREEWARP")
		return {"ok":true,"closed":true} if committed.ok else committed
	if phase=="KEYWORD":
		if choice!="submit" or text.length()>120:return {"ok":false,"reason":"无效口令输入。"}
		if text!=str(branch.get("keyword","")):return {"ok":false,"reason":message(branch.texts,"AcceptMsg")}
		var committed := transact(backend,profile,branch,"KEYWORD")
		return {"ok":true,"closed":true} if committed.ok else committed
	if current.has("pet_ids"):
		if pet_ids(profile,str(branch.actions.DelPet))!=current.pet_ids:return {"ok":false,"reason":"交付宠物已经改变，请重新确认。"}
	if phase=="BATTLE" and choice=="yes":return Brothers.begin(self,backend,npc,branch)
	if phase=="ACCEPT" and choice=="yes":
		var reply := window(npc,branch,"reward",message(branch.texts,"ThanksMsg"),false)
		if current.has("pet_ids"):pending.pet_ids=current.pet_ids
		return reply
	if choice!=("ok" if phase=="reward" else "yes"):return {"ok":false,"reason":"无效选择。"}
	var result := transact(backend,profile,branch,phase,"",str(npc.id))
	if not result.ok:return result
	var key := "EndStopMsg" if phase=="cancel" else ("CleanFlgMsg" if phase=="CLEAN" else "ThanksMsg")
	return {"ok":true,"closed":true} if phase=="reward" else window(npc,branch,"end",message(branch.texts,key),false)

func transact(backend, profile: Dictionary, branch: Dictionary, phase: String, notice: String = "", npc_id: String = "") -> Dictionary:
	if branch.actions.has("Warp") and backend.quest_visit_guard.is_valid():
		var reason: String=str(backend.quest_visit_guard.call())
		if not reason.is_empty():return {"ok":false,"reason":str(branch.source_fields.get("PartyMsg","无法加入团队。请解散团队。")).replace("\\n","\n") if phase=="FREEWARP" else reason}
	if phase=="FREEWARP":
		var parts:=str(branch.actions.Warp).split(",")
		var info:Dictionary=backend.session.world_catalog.info(int(parts[0]))
		if info.is_empty() or int(parts[1])<0 or int(parts[2])<0 or int(parts[1])>=int(info.width) or int(parts[2])>=int(info.height):return {"ok":false,"reason":"原门目的地图尚未导入。"}
	var npc_destinations:Array=[]
	if branch.actions.has("NpcWarp") and phase not in ["cancel","CLEAN"]:
		if npc_id.is_empty() or npc_by_id(npc_id).is_empty():return {"ok":false,"reason":"人物状态已经改变。"}
		for raw in str(branch.actions.NpcWarp).split(","):
			var parts:=raw.split(".")
			if parts.size()!=3:return {"ok":false,"reason":"原人物位置资料不完整。"}
			var point: Array=[int(parts[0]),int(parts[1]),int(parts[2])]
			var info:Dictionary=backend.session.world_catalog.info(point[0])
			if info.is_empty() or point[1]<0 or point[2]<0 or point[1]>=int(info.width) or point[2]>=int(info.height):return {"ok":false,"reason":"原人物目的地图尚未导入。"}
			npc_destinations.append(point)
	var candidate := profile.duplicate(true)
	var event := int(branch.event)
	if phase=="cancel":
		# Cancellation removes all copies, including quantified GetItem entries.
		for id in item_list(str(branch.actions.get("GetItem",""))):
			while id in candidate.original_items:Session.OriginalEquipment.remove(candidate,id)
		set_flag(candidate,"now",event,false)
		candidate.player.charm=maxi(0,int(candidate.player.get("charm",0))-1)
	elif phase=="CLEAN":
		clear_flags(candidate,str(branch.actions.get("CleanFlg","")))
	else:
		var received := item_list(str(branch.actions.get("GetItem","")))
		var random_items := item_list(str(branch.actions.get("GetRandItem","")))
		var reward_count := received.size()+(1 if not random_items.is_empty() else 0)
		var consumed := []
		if branch.actions.has("DelPet"):
			consumed=pet_indices(candidate,str(branch.actions.DelPet))
			if consumed.is_empty():return {"ok":false,"reason":"交付宠物不符合原条件。"}
		if branch.actions.has("DelStone"):
			var fee := stone_cost(profile,str(branch.actions.DelStone))
			if fee<0:return {"ok":false,"reason":"尚未支持的原费用。"}
			if int(profile.player.gold)<fee:return {"ok":false,"reason":message(branch.texts,"StoneLessMsg") if branch.texts.has("StoneLessMsg") else "石币不足。"}
			candidate.player.gold-=fee
		var reward_pet: Dictionary={}
		if branch.actions.has("GetPet"):
			if candidate.pets.size()-consumed.size()+1>Session.PET_CAPACITY:return {"ok":false,"reason":str(branch.texts.get("PetFullMsg","宠物栏已满。"))}
			var definition: Dictionary=catalog.reward_pets.get(str(branch.actions.GetPet),{})
			if definition.is_empty() or not Session.TroopArt.can_render([{"sprite":int(definition.get("sprite",0))}]):return {"ok":false,"reason":"原奖励宠物来源或图像尚未导入。"}
			reward_pet=Progression.species_actor(str(definition.species),int(definition.level),randi(),[],definition)
			reward_pet.merge({"species":definition.species,"template_id":definition.template_id,"name":definition.name,"sprite":definition.sprite,"level":definition.level,"xp":0,"skill_unlocked":false,"elements":definition.elements.duplicate(),"size":definition.size,"modai":definition.modai,"variable_ai":0,"original_end_event":0,"source_enemy_id":definition.enemy_id,"quest_reward_event":event,"skill_slots":definition.skill_slots})
			Loyalty.refresh(reward_pet,candidate.player)
		# REQUEST has an additional pre-deletion capacity check in the original
		# NPC callback. Keep the established event2 net-capacity compatibility.
		if phase=="REQUEST" and event!=2 and Session.bag_slots(profile)+received.size()>15:
			return {"ok":false,"reason":str(branch.texts.get("ItemFullMsg","道具栏已满。"))}
		if branch.actions.has("GetStone"):
			var stone := int(branch.actions.GetStone)
			if int(profile.player.gold)+stone>=ORIGINAL_MAX_GOLD:
				return {"ok":false,"reason":str(branch.texts.get("StoneFullMsg","石币已满。"))}
			candidate.player.gold+=stone
		# AcceptDel checks net capacity, credits stone, deletes source items,
		# gives items, then applies flags. Quantified deletions
		# consume the script's count (fixing the reference C's empty *n branch).
		var capacity := candidate.duplicate(true)
		remove_items(capacity,str(branch.actions.get("DelItem","")),str(branch.get("item_deletion_scope",""))=="bag")
		if Session.bag_slots(capacity)+reward_count>15:
			return {"ok":false,"reason":str(branch.texts.get("ItemFullMsg","道具栏已满。"))}
		# Delete from the end so every slot index still identifies its bound UID.
		consumed.sort()
		consumed.reverse()
		for removed in consumed:
			var old_id := str(candidate.pets[removed].pet_id)
			candidate.pets.remove_at(removed)
			for field in ["active_pet","ride_pet"]:
				var index := int(candidate.get(field,-1))
				candidate[field]=-1 if index==removed else (index-1 if index>removed else index)
			var capture: Dictionary=candidate.get("automation_settings",{}).get("capture",{})
			if str(capture.get("pet_id",""))==old_id or int(capture.get("pet",-2))==removed:
				capture.pet_id="";capture.pet=-2
			elif int(capture.get("pet",-2))>removed:capture.pet=int(capture.pet)-1
		if not reward_pet.is_empty():
			reward_pet.pet_id="pet-%d"%int(candidate.next_pet_id)
			candidate.next_pet_id+=1
			candidate.pets.append(reward_pet)
		if not random_items.is_empty():received.append(random_items[randi_range(0,random_items.size()-1)])
		remove_items(candidate,str(branch.actions.get("DelItem","")),str(branch.get("item_deletion_scope",""))=="bag")
		for item in received:Session.OriginalEquipment.add(candidate,item)
		set_flag(candidate,"now",event,true)
		var ended: String=str(branch.actions.get("EndSetFlg",""))
		if not ended.is_empty():
			set_flag(candidate,"now",event,false)
			for value in ended.split(","):set_flag(candidate,"ended",int(value),true)
		clear_flags(candidate,str(branch.actions.get("CleanFlg","")))
	if phase not in ["cancel","CLEAN"]:
		if branch.actions.has("Charm"):candidate.player.charm=clampi(int(candidate.player.get("charm",0))+int(branch.actions.Charm),0,100)
		if branch.actions.has("Warp"):Brothers.warp_profile(candidate,str(branch.actions.Warp))
	backend.session._profile=candidate
	if not backend.save():
		backend.session._profile=profile
		return {"ok":false,"reason":"save_failed"}
	if not npc_destinations.is_empty():
		npc_state.moved(npc_id,npc_destinations)
		refresh_npc_state()
	if not notice.is_empty():backend._emit({"type":"quest_result","text":notice})
	if branch.actions.has("DelPet") and phase not in ["cancel","CLEAN"]:
		var fresh: Dictionary=backend.automation.profile_settings()
		for key in ["capture_pet","capture_pet_id"]:backend.automation.settings[key]=fresh[key]
		if not candidate.pets.any(func(pet):return str(pet.pet_id)==backend.automation.training_pet_id):backend.automation.training_pet_id=""
	if branch.actions.has("Warp") and phase not in ["cancel","CLEAN"]:Brothers.publish_warp(backend,str(branch.actions.Warp))
	backend.publish()
	return {"ok":true}

static func item_list(raw: String) -> Array:
	var result := []
	if raw.is_empty():return result
	for entry in raw.split(","):
		var parts := entry.split("*")
		for i in range(int(parts[1]) if parts.size()>1 else 1):result.append(int(parts[0]))
	return result

static func remove_items(profile: Dictionary, raw: String, bag_only := false) -> void:
	if raw.is_empty():return
	if bag_only:
		for item_id in item_list(raw):
			for index in range(profile.original_instances.size()):
				var entry:Dictionary=profile.original_instances[index]
				if int(entry.item_id)==item_id and not Session.OriginalEquipment.worn(profile,int(entry.uid)):
					Session.OriginalEquipment.remove_at(profile,index)
					break
		return
	for entry in raw.split(","):
		var parts := entry.split("*")
		var id := int(parts[0])
		if parts.size()>1:
			for i in range(int(parts[1])):Session.OriginalEquipment.remove(profile,id)
		else:
			while id in profile.original_items:Session.OriginalEquipment.remove(profile,id)

static func clear_flags(profile: Dictionary, raw: String) -> void:
	if raw.is_empty():return
	for value in raw.split(","):
		set_flag(profile,"now",int(value),false)
		set_flag(profile,"ended",int(value),false)
