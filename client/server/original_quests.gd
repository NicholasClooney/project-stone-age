extends RefCounted
## Source-script interpreter. Pending dialogues are server-owned and single use.
const Session = preload("res://server/game_session.gd")
const Progression = preload("res://server/progression.gd")
const Charm = preload("res://server/original_charm.gd")
const Loyalty = preload("res://server/loyalty.gd")
var catalog
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
		for predicate in alternative.split("&"):
			if predicate.begins_with("PET"):
				if pet_index(profile,predicate)<0:accepted=false;break
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
				"ITEM":result=profile.original_items.count(number)>=maxi(1,int(found.get_string(4)))
				"SP":result=number<4 and (int(profile.original_savepoint_bits)&(1<<number))!=0
				"LV":result=int(profile.player.level)>number if op==">" else int(profile.player.level)==number
			if op=="!=":result=not result
			if op==">" and kind!="LV":result=false
			if not result:accepted=false;break
		if accepted:return true
	return false

static func pet_index(profile: Dictionary, predicate: String) -> int:
	var regex := RegEx.new()
	regex.compile("^PET>([0-9]+)-([0-9]+)(?:\\*1)?$")
	var found := regex.search(predicate)
	if found==null:return -1
	for index in range(profile.pets.size()):
		var pet: Dictionary=profile.pets[index]
		if str(pet.get("species",""))=="original_%d"%int(found.get_string(2)) and int(pet.level)>int(found.get_string(1)) and Session.original_pet_event(pet)==0:return index
	return -1

func npc_by_id(id: String) -> Dictionary:
	for npc in catalog.active_npcs():
		if str(npc.id)==id:return npc
	return {}

func branch_for(npc: Dictionary, profile: Dictionary) -> Dictionary:
	for branch in npc.get("branches",[]):
		if int(branch.event)>=0 and flag(profile,"ended",int(branch.event)):continue
		if matches(profile,str(branch.condition)):return branch
	return {}

func allowed(backend, npc: Dictionary) -> bool:
	if backend.quest_auto.running and not backend.quest_auto.internal:return false
	if backend.battle_open or not backend.session._pending.is_empty() or backend.automation.running or backend.automation.hunt_running or backend.automation.flow_active():return false
	var cell: Array = npc.cell
	return backend.automation.position_map==int(npc.map_id) and maxi(absi(backend.automation.position_cell.x-int(cell[0])),absi(backend.automation.position_cell.y-int(cell[1])))<=2

func window(npc: Dictionary, branch: Dictionary, phase: String, text: String, confirm: bool) -> Dictionary:
	serial+=1
	var token := "%d-%d" % [Time.get_ticks_usec(),serial]
	pending={"token":token,"npc":npc,"branch":branch,"phase":phase}
	return {"ok":true,"dialogue":{"token":token,"npc_id":npc.id,"name":npc.name,"text":text,"choices":[{"id":"yes","text":"是"},{"id":"no","text":"否"}] if confirm else [{"id":"ok","text":"确定"}]}}

static func message(texts: Dictionary, key: String) -> String:
	# Original scripts use both unnumbered and ordered numbered message fields.
	var parts: Array[String] = []
	if texts.has(key):parts.append(str(texts[key]))
	for index in range(1,5):
		if texts.has(key+str(index)):parts.append(str(texts[key+str(index)]))
	return "\n".join(parts)

func talk(backend, id: String) -> Dictionary:
	pending={}
	var npc := npc_by_id(id)
	if npc.is_empty() or not allowed(backend,npc):return {"ok":false,"reason":"任务人物不在附近，或当前正忙。"}
	if str(npc.get("handler",""))=="Charm":return Charm.talk(self,backend,npc)
	var profile: Dictionary=backend.session.snapshot()
	var branch := branch_for(npc,profile)
	if branch.is_empty():return window(npc,branch,"end",str(npc.get("text","")),false)
	for action in branch.actions:
		if action not in ["GetItem","DelItem","GetStone","EndSetFlg","CleanFlg","DelPet","GetPet","GetRandItem"]:return {"ok":false,"reason":"尚未支持的任务动作。"}
	var phase: String=str(branch.type)
	if phase=="MESSAGE":
		var result := transact(backend,profile,branch,"MESSAGE")
		if not result.ok:return result
		return window(npc,branch,"end",message(branch.texts,"NomalWindowMsg") if branch.texts.has("NomalWindowMsg") else message(branch.texts,"NomalMsg"),false)
	if phase=="REQUEST" and flag(profile,"now",int(branch.event)):phase="cancel"
	var keys := {"REQUEST":"RequestMsg","ACCEPT":"AcceptMsg","CLEAN":"CleanMainMsg","cancel":"StopMsg"}
	if not keys.has(phase):return {"ok":false,"reason":"尚未支持的任务分支。"}
	var reply := window(npc,branch,phase,message(branch.texts,keys[phase]),true)
	if phase=="ACCEPT" and branch.actions.has("DelPet"):
		var index := pet_index(profile,str(branch.actions.DelPet))
		if index<0:return {"ok":false,"reason":"交付宠物已经改变。"}
		pending.pet_id=str(profile.pets[index].pet_id)
	return reply

func choose(backend, token: String, choice: String) -> Dictionary:
	if pending.is_empty() or token!=str(pending.token):return {"ok":false,"reason":"对话已过期。"}
	var current: Dictionary=pending.duplicate(true)
	pending={}
	var npc: Dictionary=current.npc
	var branch: Dictionary=current.branch
	var phase: String=current.phase
	if not allowed(backend,npc):return {"ok":false,"reason":"位置或活动状态已经改变。"}
	if phase=="end":return {"ok":choice=="ok","closed":true}
	if str(npc.get("handler",""))=="Charm":return Charm.choose(self,backend,current,choice)
	var profile: Dictionary=backend.session.snapshot()
	if (phase=="REQUEST" and flag(profile,"now",int(branch.event))) or (phase=="cancel" and not flag(profile,"now",int(branch.event))):return {"ok":false,"reason":"任务状态已经改变。"}
	if branch_for(npc,profile)!=branch:return {"ok":false,"reason":"任务状态已经改变。"}
	if choice=="no":
		if phase=="cancel":return window(npc,branch,"end",str(branch.texts.get("NoStopMsg","")),false)
		return {"ok":true,"closed":true}
	if current.has("pet_id"):
		var index := pet_index(profile,str(branch.actions.DelPet))
		if index<0 or str(profile.pets[index].pet_id)!=str(current.pet_id):return {"ok":false,"reason":"交付宠物已经改变，请重新确认。"}
	if phase=="ACCEPT" and choice=="yes":
		var reply := window(npc,branch,"reward",message(branch.texts,"ThanksMsg"),false)
		if current.has("pet_id"):pending.pet_id=current.pet_id
		return reply
	if choice!=("ok" if phase=="reward" else "yes"):return {"ok":false,"reason":"无效选择。"}
	var result := transact(backend,profile,branch,phase)
	if not result.ok:return result
	var key := "EndStopMsg" if phase=="cancel" else ("CleanFlgMsg" if phase=="CLEAN" else "ThanksMsg")
	return {"ok":true,"closed":true} if phase=="reward" else window(npc,branch,"end",message(branch.texts,key),false)

func transact(backend, profile: Dictionary, branch: Dictionary, phase: String) -> Dictionary:
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
		var consumed := -1
		if branch.actions.has("DelPet"):
			consumed=pet_index(candidate,str(branch.actions.DelPet))
			if consumed<0:return {"ok":false,"reason":"交付宠物不符合原条件。"}
		var reward_pet: Dictionary={}
		if branch.actions.has("GetPet"):
			if candidate.pets.size()-(1 if consumed>=0 else 0)+1>Session.PET_CAPACITY:return {"ok":false,"reason":str(branch.texts.get("PetFullMsg","宠物栏已满。"))}
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
		remove_items(capacity,str(branch.actions.get("DelItem","")))
		if Session.bag_slots(capacity)+reward_count>15:
			return {"ok":false,"reason":str(branch.texts.get("ItemFullMsg","道具栏已满。"))}
		if consumed>=0:
			candidate.pets.remove_at(consumed)
			for field in ["active_pet","ride_pet"]:
				var index := int(candidate.get(field,-1))
				candidate[field]=-1 if index==consumed else (index-1 if index>consumed else index)
			# Selected capture helpers use UID plus a slot; reset the removed UID
			# and rebase surviving slots together in the persisted settings.
			var capture: Dictionary=candidate.get("automation_settings",{}).get("capture",{})
			var old_id := str(profile.pets[consumed].pet_id)
			if str(capture.get("pet_id",""))==old_id or int(capture.get("pet",-2))==consumed:
				capture.pet_id="";capture.pet=-2
			elif int(capture.get("pet",-2))>consumed:capture.pet=int(capture.pet)-1
		if not reward_pet.is_empty():
			reward_pet.pet_id="pet-%d"%int(candidate.next_pet_id)
			candidate.next_pet_id+=1
			candidate.pets.append(reward_pet)
		if not random_items.is_empty():received.append(random_items[randi_range(0,random_items.size()-1)])
		remove_items(candidate,str(branch.actions.get("DelItem","")))
		for item in received:Session.OriginalEquipment.add(candidate,item)
		set_flag(candidate,"now",event,true)
		var ended: String=str(branch.actions.get("EndSetFlg",""))
		if not ended.is_empty():
			set_flag(candidate,"now",event,false)
			for value in ended.split(","):set_flag(candidate,"ended",int(value),true)
		clear_flags(candidate,str(branch.actions.get("CleanFlg","")))
	backend.session._profile=candidate
	if not backend.save():
		backend.session._profile=profile
		return {"ok":false,"reason":"save_failed"}
	if branch.actions.has("DelPet") and phase not in ["cancel","CLEAN"]:
		var fresh: Dictionary=backend.automation.profile_settings()
		for key in ["capture_pet","capture_pet_id"]:backend.automation.settings[key]=fresh[key]
		if not candidate.pets.any(func(pet):return str(pet.pet_id)==backend.automation.training_pet_id):backend.automation.training_pet_id=""
	backend.publish()
	return {"ok":true}

static func item_list(raw: String) -> Array:
	var result := []
	if raw.is_empty():return result
	for entry in raw.split(","):
		var parts := entry.split("*")
		for i in range(int(parts[1]) if parts.size()>1 else 1):result.append(int(parts[0]))
	return result

static func remove_items(profile: Dictionary, raw: String) -> void:
	if raw.is_empty():return
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
