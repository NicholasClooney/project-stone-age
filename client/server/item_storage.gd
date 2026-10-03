extends RefCounted
## Original npc_poolitemshop.c:706 and char_base.c:1426. Direct free access is
## a project convenience. This module never allocates or combines original UIDs.
const Equipment=preload("res://server/original_equipment.gd")
const Spirits=preload("res://server/spirits.gd")
const MAX_CAPACITY:=3000 # Project override; original hook remains disabled.
const STACK_LIMIT:=64
static var _catalog: Dictionary={}
const LEGACY_IDS:={"potion":1500,"club":100,"mirror_charm":1460,"haru_armor":1011,"freya_robe":1112,"teo_robe":1113,"koyala_charm":1450}
const FIELDS:=["item_storage","legacy_item_storage","item_storage_revision"]

static func migrate(profile: Dictionary) -> void:
	if not profile.has("item_storage"):
		profile.item_storage=[]
		profile.legacy_item_storage={}
		profile.item_storage_revision=0

static func original_capacity(profile: Dictionary) -> int:
	return mini(10+4*mini(5,int(profile.get("player",{}).get("transmigration",0))),30)

static func capacity(_profile: Dictionary) -> int:
	return MAX_CAPACITY

static func catalog() -> Dictionary:
	if _catalog.is_empty():_catalog=preload("res://scripts/quest_catalog.gd").new().items
	return _catalog

static func stackable(entry: Dictionary, data: Dictionary) -> bool:
	# Current instances contain exactly UID/template/durability. Any future
	# binding, rolled modifier or unique state makes the instance independent.
	var raw: Array=data.get("raw_columns",[])
	return entry.size()==3 and int(entry.get("durability",-1))==0 and raw.size()>81 and int(raw[19]) in [16,20] and reason(data).is_empty()

static func groups(profile: Dictionary) -> Array:
	var result: Array=[]
	var open: Dictionary={}
	var specs: Dictionary=catalog()
	for entry in profile.get("item_storage",[]):
		var id:=int(entry.item_id)
		if stackable(entry,specs.get(str(id),{})):
			if not open.has(id) or result[int(open[id])].size()==STACK_LIMIT:
				open[id]=result.size();result.append([])
			result[int(open[id])].append(entry)
		else:result.append([entry])
	return result

static func used(profile: Dictionary) -> int:
	var total:=groups(profile).size()
	for key in profile.get("legacy_item_storage",{}):
		var count:=int(profile.legacy_item_storage[key])
		total+=int(ceil(float(count)/STACK_LIMIT)) if key=="potion" else count
	return total

static func reason(data: Dictionary) -> String:
	var columns: Array=data.get("raw_columns",[])
	if columns.size()<=81:return "原物品仓库标记尚未核实。"
	if str(columns[78])=="1":return "原版规则：登出消失物品不能寄存。"
	if str(columns[79])=="1":return "原版规则：丢弃消失物品不能寄存。"
	if str(columns[81])!="1":return "原版规则：不可宠邮物品不能寄存。"
	return ""

static func legacy_worn(profile: Dictionary, key: String) -> bool:
	return (key=="club" and bool(profile.get("equipped",false))) or (key=="mirror_charm" and bool(profile.get("equipped_mirror",false))) or key in profile.get("equipment",{}).values()

static func valid(profile: Dictionary) -> bool:
	var present:=0
	for key in FIELDS:present+=int(profile.has(key))
	if present==0:return true
	if present!=3 or int(profile.get("version",0))<6:return false
	if not profile.item_storage is Array or not profile.legacy_item_storage is Dictionary or not Equipment.integer(profile.item_storage_revision,0,2147483646):return false
	if profile.item_storage.size()>MAX_CAPACITY*STACK_LIMIT or not Equipment.valid(profile):return false
	for key in profile.legacy_item_storage:
		if not key in LEGACY_IDS or not Equipment.integer(profile.legacy_item_storage[key],1,MAX_CAPACITY*STACK_LIMIT):return false
	var seen: Dictionary={}
	for entry in profile.original_instances:seen[int(entry.uid)]=true
	for entry in profile.item_storage:
		if not entry is Dictionary or entry.size()!=3:return false
		if not Equipment.integer(entry.get("uid"),1,int(profile.next_original_uid)-1) or seen.has(int(entry.uid)):return false
		if not Equipment.integer(entry.get("item_id"),1,2147483647):return false
		var spec: Dictionary=Equipment.ITEMS.get(int(entry.item_id),{})
		if not Equipment.integer(entry.get("durability"),0,int(spec.get("durability",0))):return false
		if int(spec.get("durability",0))>0 and int(entry.durability)==0:return false
		if not reason(catalog().get(str(int(entry.item_id)),{})).is_empty():return false
		seen[int(entry.uid)]=true
	return used(profile)<=capacity(profile)

static func rows(profile: Dictionary, specs: Dictionary, deposit: bool) -> Array:
	var result: Array=[]
	var grouped: Array=[]
	if deposit:
		for entry in profile.get("original_instances",[]):grouped.append([entry])
	else:grouped=groups(profile)
	for group in grouped:
		var entry: Dictionary=group[0]
		var data: Dictionary=specs.get(str(int(entry.item_id)),{})
		var refusal: String=reason(data) if deposit else ""
		if deposit and Equipment.worn(profile,int(entry.uid)):refusal="请先卸下已穿戴的装备。"
		var selector: Dictionary={"uid":int(entry.uid)} if deposit else {"uids":group.map(func(member):return int(member.uid))}
		result.append({"selector":selector,"id":"uid_%d"%int(entry.uid),"name":str(data.get("name",str(entry.item_id))),"count":group.size(),"durability":int(entry.durability),"reason":refusal,"icon":str(data.get("icon_path",""))})
	var counts: Dictionary=profile.get("inventory" if deposit else "legacy_item_storage",{})
	for key in counts:
		if int(counts[key])<=0:continue
		var refusal:=""
		if not LEGACY_IDS.has(key):refusal="项目辅助物品暂不支持寄存。"
		if deposit and legacy_worn(profile,key):refusal="请先卸下已穿戴的装备。"
		var title: String=Spirits.ITEMS.get(key,{}).get("name",{"potion":"耐久力回复药","club":"小棍棒","healing_charm":"恢复宠物"}.get(key,key))
		var offset:=0
		while offset<int(counts[key]):
			var count: int=int(counts[key]) if deposit else mini(STACK_LIMIT if key=="potion" else 1,int(counts[key])-offset)
			result.append({"selector":{"key":key,"count":count,"offset":offset},"id":"legacy_%s_%d"%[key,offset],"name":title,"count":count,"reason":refusal,"durability":-1,"icon":""})
			offset+=count
	return result

static func take(row: Dictionary, count: int) -> Dictionary:
	var result: Dictionary=row.selector.duplicate(true)
	if result.has("uids"):result.uids=result.uids.slice(0,count)
	elif result.has("key"):result.count=count
	return result

static func transfer(backend, command: Dictionary) -> Dictionary:
	if backend.battle_open or not backend.session._pending.is_empty() or backend.party_battle() or backend.automation.running or backend.automation.hunt_running or backend.automation.flow_active() or backend.quest_auto.running or backend.stationary.running or not backend.original_quests.pending.is_empty():return backend._reject("当前正忙，请结束战斗、任务对话或自动活动后存取。")
	var before: Dictionary=backend.session.snapshot()
	var revision=command.get("revision")
	if not Equipment.integer(revision,0,2147483645) or int(revision)!=int(before.item_storage_revision):return backend._reject("仓库状态已更新，请重新选择物品。")
	var direction=command.get("direction")
	if direction not in ["deposit","withdraw"]:return backend._reject("无效存取方向。")
	var selection=command.get("items")
	if not selection is Array or selection.is_empty() or selection.size()>MAX_CAPACITY:return backend._reject("请选择要存取的物品。")
	var deposit: bool=direction=="deposit"
	var available: Array=rows(before,backend.quest_catalog.items,deposit)
	var by_id: Dictionary={}
	for row in available:by_id[row.id]=row
	var chosen: Array=[]
	var seen: Dictionary={}
	for selector in selection:
		if not selector is Dictionary:return backend._reject("无效物品。")
		var ident:=""
		var count:=1
		if selector.has("uid") and Equipment.integer(selector.uid,1,2147483647):ident="uid_%d"%int(selector.uid)
		elif selector.get("uids") is Array and not selector.uids.is_empty() and selector.uids.size()<=STACK_LIMIT:
			for uid in selector.uids:
				if not Equipment.integer(uid,1,2147483647):return backend._reject("无效物品。")
			ident="uid_%d"%int(selector.uids[0]);count=selector.uids.size()
		elif selector.get("key") is String and Equipment.integer(selector.get("offset"),0,MAX_CAPACITY*STACK_LIMIT) and Equipment.integer(selector.get("count"),1,99):
			ident="legacy_%s_%d"%[selector.key,int(selector.offset)];count=int(selector.count)
		var row: Dictionary=by_id.get(ident,{})
		if row.is_empty() or count>int(row.count) or take(row,count)!=selector:return backend._reject("物品已改变或不属于当前角色，请重新选择。")
		if seen.has(ident):return backend._reject("不能重复选择同一件物品。")
		if not row.reason.is_empty():return backend._reject(row.reason)
		seen[ident]=true;chosen.append({"selector":selector})
	var candidate: Dictionary=before.duplicate(true)
	var move_uids: Dictionary={}
	for row in chosen:
		var selector: Dictionary=row.selector
		if selector.has("uid"):move_uids[int(selector.uid)]=true
		elif selector.has("uids"):
			for uid in selector.uids:
				if move_uids.has(int(uid)):return backend._reject("不能重复选择同一件物品。")
				move_uids[int(uid)]=true
		else:
			var key: String=selector.key
			var source: Dictionary=candidate.inventory if deposit else candidate.legacy_item_storage
			var dest: Dictionary=candidate.legacy_item_storage if deposit else candidate.inventory
			var count:=int(selector.count)
			if int(source.get(key,0))<count:return backend._reject("物品数量已改变。")
			dest[key]=int(dest.get(key,0))+count
			if not deposit and int(dest[key])>99:return backend._reject("背包同类数量已满，整批未移动。")
			source[key]-=count
			if not deposit and int(source[key])==0:source.erase(key)
	var remaining: Array=[]
	var source: Array=candidate.original_instances if deposit else candidate.item_storage
	for entry in source:
		if move_uids.has(int(entry.uid)):
			if deposit:candidate.item_storage.append(entry)
			else:candidate.original_instances.append(entry)
		else:remaining.append(entry)
	if deposit:candidate.original_instances=remaining
	else:candidate.item_storage=remaining
	candidate.original_items=candidate.original_instances.map(func(entry):return int(entry.item_id))
	if deposit and used(candidate)>capacity(candidate):return backend._reject("物品仓库已满，整批未存入。")
	if backend.GameSession.bag_slots(candidate)>15:return backend._reject("背包已满，整批未取出。")
	candidate.item_storage_revision+=1
	if not backend.session._valid_profile(candidate):return backend._reject("存取校验失败，整批未移动。")
	backend.session._profile=candidate
	if not backend.save():
		backend.session._profile=before
		return backend._reject("保存失败，整批未移动。")
	backend._publish()
	return {"ok":true,"note":"已存入所选物品。" if deposit else "已取出所选物品。"}
