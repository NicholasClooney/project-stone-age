extends RefCounted
## Server-owned source receipts. Never accept these dictionaries from a command.
const Policy=preload("res://server/quest_wild_drop_policy.gd")
const DENIED="项目补充：本次野战缺少有效的原路线到达记录，任务专用物品未发放；普通战果照常结算。"

static func freeze(backend, source:Dictionary={}) -> void:
	var pending:Dictionary=backend.session._pending
	if pending.is_empty() or pending.has("quest_guard"):return
	if source.is_empty():
		if not bool(pending.get("source_encounter",false)):return
		var borrowed:Dictionary=pending.get("training_borrow",{})
		source={"map":int(borrowed.get("map_id",backend.automation.position_map)),"area":int(pending.get("area_id",-1)),"group":int(pending.get("group_id",-1)),"borrowed":not borrowed.is_empty(),"cell":borrowed.get("cell",[backend.automation.position_cell.x,backend.automation.position_cell.y]).duplicate()}
	var protected:Dictionary={}
	var error:=""
	for i in range(pending.get("enemies",[]).size()):
		var enemy:Dictionary=pending.enemies[i]
		var enemy_id:=int(enemy.get("source_enemy_id",-1))
		var rows:Dictionary={}
		var source_slots:Dictionary={}
		for drop in backend.encounter_catalog.data.get("enemies",{}).get(str(enemy_id),{}).get("drops",[]):
			source_slots[int(drop.slot)]=drop
			var rule:Dictionary=Policy.match_rule(int(source.map),int(source.area),int(source.group),enemy_id,int(drop.item_id),int(drop.slot))
			if not rule.is_empty():rows[int(drop.slot)]=rule
		if rows.is_empty():continue
		var generated:Array=enemy.get("generated_drops",[])
		var slots:Array=enemy.get("generated_drop_slots",[])
		if generated.size()!=slots.size():
			error="任务掉落来源槽位缺失，未提交战果。";continue
		var seen_slots:Dictionary={}
		for j in range(generated.size()):
			if not backend.session._integer(slots[j],0,9) or not source_slots.has(int(slots[j])) or seen_slots.has(int(slots[j])):
				error="任务掉落来源槽位无效，未提交战果。";continue
			seen_slots[int(slots[j])]=true
			var original:Dictionary=source_slots[int(slots[j])]
			if int(original.item_id)!=int(generated[j]) or int(original.probability)<=0:
				error="任务掉落来源槽位不符，未提交战果。";continue
			if rows.has(int(slots[j])):protected["%d:%d"%[i,j]]=rows[int(slots[j])].duplicate(true)
	# Keep source even without a winning special drop: party members need the
	# original leader's encounter tuple, never their trailing queue position.
	pending.wild_drop_source=source.duplicate(true)
	if protected.is_empty() and error.is_empty():return
	pending.wild_drop_receipt={"source":source.duplicate(true),"rules":protected,"context":backend.quest_arrival.wild_context(backend),"error":error}

## Call only after validating the COMPLETE original claim list. The caller
## retains that original list in pending/party_settlement for every save retry.
static func filter_claims(backend, receipt:Dictionary, claims:Array) -> Dictionary:
	var allowed:Array=[]
	var denied:=false
	for claim in claims:
		var rule:Dictionary=receipt.get("rules",{}).get("%d:%d"%[int(claim.enemy),int(claim.item)],{})
		var context:Dictionary=receipt.get("context",{})
		# Borrowed training troops do not move anyone. A same-scope visit to a
		# different source map is not proof of arrival at the borrowed enemy.
		var at_source:bool=int(context.get("map_id",-1))==int(receipt.get("source",{}).get("map",-2))
		if bool(receipt.get("source",{}).get("borrowed",false)) and context.get("cell",[])!=receipt.source.get("cell",[]):at_source=false
		if not rule.is_empty() and (not at_source or not backend.quest_arrival.check_wild(backend,context,str(rule.scope)).is_empty()):
			denied=true
		else:allowed.append(claim.duplicate(true))
	return {"claims":allowed,"denied":DENIED if denied else ""}
