extends "res://server/original_quests.gd"
# Exact 21e15ea choose/transact bodies in candidate environment.
func choose(backend, token: String, choice: String, text: String = "", selected_ids: Variant = []) -> Dictionary:
	if pending.is_empty() or token!=str(pending.token):return {"ok":false,"reason":"对话已过期。"}
	if pending.get("phase","")=="permit_shop":return {"ok":false,"reason":"请使用原售证确认。"}
	var current: Dictionary=pending.duplicate(true)
	var source_call:Dictionary=backend.capture_quest_source_call(str(current.npc.id))
	pending={}
	var fee_frame:Dictionary=RequiredFee.capture(backend,"seimu",RequiredFee.GATE) if str(current.npc.id)==RequiredFee.GATE and str(current.phase)=="FREEWARP" else {}
	var npc: Dictionary=current.npc
	if not allowed(backend,npc):return {"ok":false,"reason":"位置或活动状态已经改变。"}
	if current.has("service_state"):return services.reply(self,backend,current,choice,text)
	var branch: Dictionary=current.branch
	var phase: String=current.phase
	if phase=="end":return {"ok":choice=="ok","closed":true}
	if str(npc.get("handler",""))=="Charm":return Charm.choose(self,backend,current,choice)
	var profile: Dictionary=backend.session.snapshot()
	if phase=="SCRIPT_KEYWORD":
		if choice=="no":return {"ok":true,"closed":true}
		if choice!="submit" or text.length()>120:return {"ok":false,"reason":"无效口令输入。"}
		var selected := branch_for(npc,profile,text)
		var reply := open_branch(backend,npc,profile,selected)
		if not pending.is_empty():pending.spoken=text
		return reply
	if (phase=="REQUEST" and flag(profile,"now",int(branch.event))) or (phase=="cancel" and not flag(profile,"now",int(branch.event))):return {"ok":false,"reason":"任务状态已经改变。"}
	if branch_for(npc,profile,str(current.get("spoken","")))!=branch:return {"ok":false,"reason":"任务状态已经改变。"}
	var arrival_reason:String=backend.quest_arrival.check_action(backend,npc,branch,phase)
	if not arrival_reason.is_empty():return {"ok":false,"reason":arrival_reason}
	if choice=="no":
		if phase=="cancel":return window(npc,branch,"end",str(branch.texts.get("NoStopMsg","")),false)
		return {"ok":true,"closed":true}
	if phase=="FREEWARP":
		if choice!="yes":return {"ok":false,"reason":"无效选择。"}
		var committed := transact(backend,profile,branch,"FREEWARP","",str(npc.id),[],fee_frame)
		return committed if not fee_frame.is_empty() else ({"ok":true,"closed":true} if committed.ok else committed)
	if phase=="KEYWORD":
		if choice!="submit" or text.length()>120:return {"ok":false,"reason":"无效口令输入。"}
		if text!=str(branch.get("keyword","")):return {"ok":false,"reason":message(branch.texts,"AcceptMsg")}
		var committed := transact(backend,profile,branch,"KEYWORD","",str(npc.id))
		return {"ok":true,"closed":true} if committed.ok else committed
	if bool(branch.get("project_pet_selection",false)):
		if not selected_ids is Array:return {"ok":false,"reason":"无效宠物选择。"}
		var selected:Array=current.get("selected_pet_ids",[])
		if phase=="ACCEPT":
			if not selected_ids.is_empty():selected=selected_ids.duplicate()
			if selected.size()!=1 or not selected[0] in current.get("pet_candidates",[]):return {"ok":false,"reason":"请选择要交付的宠物。"}
		elif not selected_ids.is_empty() and selected_ids!=selected:return {"ok":false,"reason":"确认后不可更换交付宠物。"}
		if selected_pet_indices(profile,str(branch.actions.DelPet),selected).is_empty():return {"ok":false,"reason":"所选宠物已经改变，请重新确认。"}
		current.selected_pet_ids=selected
	if current.has("pet_ids"):
		if pet_ids(profile,str(branch.actions.DelPet))!=current.pet_ids:return {"ok":false,"reason":"交付宠物已经改变，请重新确认。"}
	if phase=="BATTLE" and choice=="yes":return Brothers.begin(self,backend,npc,branch)
	if phase=="ACCEPT" and choice=="yes":
		var reply := window(npc,branch,"reward",message(branch.texts,"ThanksMsg"),false)
		if current.has("pet_ids"):pending.pet_ids=current.pet_ids
		if current.has("selected_pet_ids"):pending.selected_pet_ids=current.selected_pet_ids.duplicate()
		if current.has("spoken"):pending.spoken=current.spoken
		return reply
	if choice!=("ok" if phase=="reward" else "yes"):return {"ok":false,"reason":"无效选择。"}
	var result := transact(backend,profile,branch,phase,"",str(npc.id),current.get("selected_pet_ids",[]))
	if not result.ok:return result
	if not source_call.is_empty() and not backend.quest_source_call_live(source_call):return {"ok":true,"closed":true}
	var key := "EndStopMsg" if phase=="cancel" else ("CleanFlgMsg" if phase=="CLEAN" else "ThanksMsg")
	return {"ok":true,"closed":true} if phase=="reward" else window(npc,branch,"end",message(branch.texts,key),false)

func transact(backend, profile: Dictionary, branch: Dictionary, phase: String, notice: String = "", npc_id: String = "", selected_ids: Array = [], fee_frame:Dictionary = {}) -> Dictionary:
	if npc_id==RequiredFee.GATE and phase=="FREEWARP":
		if fee_frame.is_empty():return {"ok":false,"reason":"原收费确认已过期。"}
		return RequiredFee.seimu(backend,profile,branch,fee_frame)
	# Resolve from the explicit trusted context, never the already-cleared token.
	var source_npc:Dictionary=npc_by_id(npc_id)
	var arrival_reason:String=backend.quest_arrival.check_action(backend,source_npc,branch,phase)
	if not arrival_reason.is_empty():return {"ok":false,"reason":arrival_reason}
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
			consumed=selected_pet_indices(candidate,str(branch.actions.DelPet),selected_ids) if bool(branch.get("project_pet_selection",false)) else pet_indices(candidate,str(branch.actions.DelPet))
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
			Loyalty.refresh(reward_pet,candidate.player,int(candidate.player.get("transmigration",0)))
		# REQUEST has an additional pre-deletion capacity check in the original
		# NPC callback. Keep the established event2 net-capacity compatibility.
		if phase=="REQUEST" and event!=2 and Session.bag_slots(profile)+received.size()>15:
			return {"ok":false,"reason":str(branch.texts.get("ItemFullMsg","道具栏已满。"))}
		if branch.actions.has("GetStone"):
			var stone := int(branch.actions.GetStone)
			if int(profile.player.gold)+stone>Session.MAX_GOLD:
				return {"ok":false,"reason":str(branch.texts.get("StoneFullMsg","石币已满。"))+"\n【项目改动】石币上限为10亿，本次收入会超过上限；物品与石币均未变动。"}
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
	# Only this run's privately purchased 44 entry bypasses the old rollback.
	# The candidate above was built by the real DelItem/Warp path.
	if backend._fee_entry_handles(npc_id,branch,phase):
		return backend._transact_lobby_ticket_entry(profile,candidate,npc_id,branch,phase)
	backend.session._profile=candidate
	if not backend.save_quest_source_transaction(npc_id,branch,phase):
		backend.session._profile=profile
		return {"ok":false,"reason":"save_failed"}
	backend.quest_arrival.action_committed(backend,source_npc,branch,phase)
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
