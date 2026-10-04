extends RefCounted
## Read-only quest44 projection. No answers, grants, automatic play or new flags.
const Rules=preload("res://server/original_quests.gd")
const MapFile=preload("res://scripts/map_file.gd")
const BASES=[800,820,840]
static var service_sources:Dictionary={}
static func floor_base(map_id:int) -> int:
	for base in BASES:
		if map_id>=base and map_id<base+10:return base
	return -1

static func stage_key(backend) -> Array:
	var map_id:int=backend.automation.position_map
	if not protected_map(map_id):return [map_id]
	# All thirty pinned maps separate entry/challenge (y>=19) from the won
	# stair component (y<=17) with the source y18 wall. Walking within either
	# component does not invalidate every quest's cached projection.
	var cell:Vector2i=backend.automation.position_cell
	var nearby:Array=[]
	for actor in backend.quest_catalog.active_npcs():
		if int(actor.map_id)!=map_id or not owns(actor) or str(actor.get("kind",""))=="golden_bui_gate":continue
		var delta:=cell-Vector2i(int(actor.cell[0]),int(actor.cell[1]))
		if maxi(absi(delta.x),absi(delta.y))<=2:nearby.append(str(actor.id))
	return [map_id,cell.y<18,backend.quest_arrival.has_arrival(backend,map_id,cell),nearby] if protected_map(map_id) else [map_id]

static func band(level:int) -> Dictionary:
	if level>=70:return {"base":840,"ticket":2757,"counter":4020,"lobby":851,"fee":level*40,"name":"高级","range":"70级以上"}
	if level>=50:return {"base":820,"ticket":2756,"counter":2020,"lobby":811,"fee":level*40,"name":"中级","range":"50–69级"}
	return {"base":800,"ticket":2755,"counter":2020,"lobby":811,"fee":level*20,"name":"初级","range":"30–49级"}

static func row(quest:Dictionary,id:String,label:String,current:bool,done:bool,npc:Dictionary={},point:Array=[]) -> Dictionary:
	var value:Dictionary={"id":"golden44:"+id,"label":label,"npc_id":"","current":current,"done":done,"actionable":false,"source":{"type":"golden_bui_stage"}}
	if current and not npc.is_empty() and not point.is_empty():
		value.npc_id=str(npc.id);value.map_id=int(npc.map_id);value.cell=npc.cell.duplicate()
		value.navigation_cell=point.duplicate();value.actionable=true
		value.source={"type":"golden_bui_stage","npc_id":str(npc.id),"source_script":str(npc.get("source_script",""))}
	quest.steps.append(value)
	return value

static func npc(backend,id:String) -> Dictionary:
	return backend.original_quests.npc_by_id(id)

static func steps(helper,backend,profile:Dictionary,quest:Dictionary) -> void:
	var level:=int(profile.player.level)
	var route:=band(level)
	var map_id:int=backend.automation.position_map
	var base:=floor_base(map_id)
	var on_floor:=base>=0
	var won:bool=on_floor and backend.automation.position_cell.y<18
	var ended:=Rules.flag(profile,"ended",44)
	var started:=Rules.flag(profile,"now",44)
	var reward_room:=map_id in [810,850]
	var reward_ready:=reward_room or started
	var coupon:bool=2753 in profile.original_items
	var ticket:bool=int(route.ticket) in profile.original_items
	if not ended and (on_floor or reward_ready or ticket):quest.status="进行中"
	quest.completion_detail="原任务“猜谜3兄弟”。30–49／50–69／70级以上分别购买初／中／高级门票，收费等级×20／40／40。每条十层有七组问答（1、2、3、5、5、7、10题）和三次猜拳；题库Level不是角色等级。首层答对另得道具交换卷；通关后先领取猜谜专家的会员证，再兑换1级金布伊。原版行为：没有猜拳的参加券也能玩，有券扣一张，平局不再扣。助手只送公开售票入口或票门；洞内须经过真实票门和原路，合法近谈时仅保持原地。手动玩法保持原规则；自动推进仅本任务，自动查原公开题目答案是项目便利，猜拳沿用原随机结果并合法重试。缺猜谜票时停下交由玩家处理，不自动买票或刷券；全程原路，普通战自动攻击并快速结算，通关自动领取会员证并兑换一次金布伊。不开放47、77级后续。"
	if ended:
		row(quest,"complete","已领取金布伊，任务已完成；不会重复发宠物。",false,true)
		return
	if level<30:
		quest.blocked_reason="原道场至少需要角色30级。"
		row(quest,"level","先达到角色30级，再到玛丽娜丝道场柜台购票。",true,false)
	var outside:=not on_floor and not reward_ready
	var buy:bool=outside and not ticket and level>=30
	var vendor:=npc(backend,"quiz/uketuke%s@%d:18:13"%["2" if int(route.counter)==4020 else "",int(route.counter)])
	var purchase:=row(quest,"buy:%d"%int(route.ticket),"购买%s门票（%s，%d石币） · %s道场柜台(18,13)"%[route.name,route.range,int(route.fee),"卡鲁它那" if int(route.counter)==4020 else "玛丽娜丝"],buy,ticket or on_floor or reward_ready,vendor,[16,13])
	if on_floor or reward_ready:purchase.label="已到达挑战区域；原门票与等级在受理入场时核验。"
	if buy and int(profile.player.gold)<int(route.fee):
		purchase.actionable=false;quest.blocked_reason="石币不足：原费用为%d石币。"%int(route.fee)
	var lobby:int=831 if map_id==831 and int(route.lobby)==811 else int(route.lobby)
	var gate_x:=29 if lobby==851 else (30 if int(route.base)==800 else 28)
	var gate:=npc(backend,"genout/wpm_%d_%d_20@%d:%d:20"%[lobby,gate_x,lobby,gate_x])
	row(quest,"enter:%d:%d"%[lobby,int(route.ticket)],"向%s受理员出示并消耗门票，进入第一层；等级与门票由原对话重查。"%route.name,outside and ticket and level>=30,on_floor or reward_ready,gate,[gate_x,22])
	if on_floor:
		var floor_number:=map_id-base+1
		if won:
			var next_map:= (850 if base==840 else 810) if floor_number==10 else map_id+1
			var stairs:=[]
			for portal in helper.places.links(map_id).values():
				if int(portal.to_map)==next_map:stairs=portal.cell;break
			row(quest,"stairs:%d"%map_id,"第%d层已过关：沿当前区域走到原楼梯%s，前往%s；助手不跳过楼梯。"%[floor_number,str(stairs),"领奖房" if floor_number==10 else "第%d层"%(floor_number+1)],true,false)
		else:
			var challenge:Dictionary={}
			for candidate in backend.quest_catalog.active_npcs():
				if int(candidate.map_id)==map_id and str(candidate.get("kind","")) in ["golden_bui_quiz","golden_bui_janken"]:challenge=candidate;break
			var fist:=str(challenge.get("kind",""))=="golden_bui_janken"
			var item:=2751 if fist else 2752
			var count:int=profile.original_items.count(item)
			var collect:=row(quest,"coupon:%d"%map_id,"第%d层：在当前入口侧走动遇敌，击败原道场弟子取得%s（当前%d张；随机掉落，不保证每战获得）%s。"%[floor_number,"猜拳的参加券" if fist else "猜谜的参加票",count,"；无猜拳券也可按原版直接挑战" if fist else ""],count==0, count>0)
			# The current floor's entry-side cell is an actual encounter area.
			# Restrict destination() neighbours to this side of the source wall.
			if count==0:
				var point:=[int(challenge.get("cell",[29,19])[0]),21]
				var area:Dictionary=backend.encounter_catalog.area_at(map_id,Vector2i(point[0],point[1]))
				if not area.is_empty():
					collect.map_id=map_id;collect.cell=point;collect.actionable=true
					collect.source={"type":"encounter","area_id":int(area.id),"area_rect":[point[0],21,point[0],21],"item_id":item,"source":"gmsv/data/encount.txt","area_source_line":int(area.get("source_line",0))}
			var active:=fist or count>0
			row(quest,"challenge:%d"%map_id,"第%d层：%s；确认开局后按原规则扣参加券，退出不退券。"%[floor_number,"与原NPC猜拳，胜利前进、失败退层" if fist else "向原NPC答完整组问题，按原正确数判定过关或退层"],active,false,challenge,[int(challenge.get("cell",[29,19])[0]),21])
	else:
		row(quest,"challenges","进入后完成十层：问答需要猜谜的参加票，猜拳的参加券按原版可有可无；在原道场随机战取得参加券。",false,reward_ready)
	var room:int=map_id if reward_room else (850 if int(route.base)==840 else 810)
	var claim:=npc(backend,"quiz/equiz_01@%d:29:16"%room)
	var claim_label:="通关后向魁司领取猜谜专家的会员证，用于兑换金布伊。"
	if started:claim_label="已领取猜谜专家的会员证，带给伊那多兑换金布伊。" if coupon else "会员证已领取但未持有：向魁司核对原取消／重领对话。"
	row(quest,"claim:%d"%room,claim_label,reward_ready and (not started or not coupon),started and coupon,claim,[29,17])
	var exchange:=npc(backend,"quiz/equiz_02@%d:28:16"%room)
	row(quest,"exchange:%d"%room,"向伊那多交猜谜专家的会员证，领取1级金布伊；需随身宠物空位，不开放77级后续。",reward_ready and started and coupon,false,exchange,[28,17])
	if reward_ready and started and coupon and profile.pets.size()>=Rules.Session.PET_CAPACITY:quest.blocked_reason="随身宠物栏已满；先空出一个位置，原兑换券保留。"

static func can_visit(step:Dictionary) -> bool:
	return bool(step.get("current",false)) and step.has("map_id") and step.get("cell",[]).size()==2

static func protected_map(map_id:int)->bool:
	return floor_base(map_id)>=0 or map_id in [810,850]

static func coupon_target(target:Dictionary)->bool:
	var map_id:int=int(target.get("map_id",-1))
	var base:=floor_base(map_id)
	if base<0 or str(target.get("id",""))!="":return false
	# Exact reviewed source challenge-column encounter point, never arbitrary
	# empty IDs or client-supplied rectangles. Backend derives this from a step.
	var x:=29 if (map_id-base)%2==0 else 18
	return target.get("cell",[])==[x,21] and target.get("area_rect",[])==[x,21,x,21]

static func owns(target:Dictionary)->bool:
	if coupon_target(target):return true
	if str(target.get("id","" )).is_empty() or not target.get("events",[]).any(func(event):return int(event)==44):return false
	var script:=str(target.get("source_script",str(target.id).split("@")[0]))
	var map_id:int=int(target.get("map_id",-1))
	var cell:Array=target.get("cell",[])
	if cell.size()!=2 or str(target.id)!="%s@%d:%d:%d"%[script,map_id,int(cell[0]),int(cell[1])]:return false
	if script in ["quiz/uketuke","quiz/uketuke2"]:
		return map_id==(2020 if script=="quiz/uketuke" else 4020) and int(cell[0])==18 and int(cell[1])==13
	if script in ["quiz/equiz_01","quiz/equiz_02"]:
		return map_id in [810,850] and int(cell[0])==(29 if script=="quiz/equiz_01" else 28) and int(cell[1])==16
	if str(target.get("kind","")) not in ["golden_bui_quiz","golden_bui_janken","golden_bui_gate"]:return false
	if service_sources.is_empty():
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/server/golden-bui.json"))
		if parsed is Dictionary:service_sources=parsed.get("services",{})
	if not service_sources.has(script):return false
	var parts:=script.split("_")
	return parts.size()==4 and int(parts[1])==map_id and int(parts[2])==int(cell[0]) and int(parts[3])==int(cell[1])

static func walk_destination(helper,backend,target:Dictionary)->Dictionary:
	# Pure collision geometry for real walking/tests, never a travel receipt.
	if not owns(target):return {}
	return helper.geometric_destination(backend,target,"near")

static func public_entrance(helper,backend)->Dictionary:
	var profile:Dictionary=backend.session._profile
	var route:=band(int(profile.player.level))
	if int(profile.player.level)<30:return {}
	var map_id:int=int(route.counter)
	var cell:Array=[16,13]
	if int(route.ticket) in profile.original_items:
		map_id=831 if backend.automation.position_map==831 and int(route.lobby)==811 else int(route.lobby)
		cell=[29 if map_id==851 else (30 if int(route.base)==800 else 28),22]
	if not helper.maps.has(map_id):helper.maps[map_id]=MapFile.load_map(helper.places.file(map_id))
	if not helper.safe(helper.maps[map_id],Vector2i(int(cell[0]),int(cell[1])),{},helper.places.links(map_id)):return {}
	return {"map_id":map_id,"cell":cell,"npc_id":""}

static func destination(helper,backend,target:Dictionary,mode:String)->Dictionary:
	if mode not in ["near","arrival"] or not owns(target):return {}
	var map_id:int=int(target.map_id)
	var current_map:int=backend.automation.position_map
	var current:Vector2i=backend.automation.position_cell
	var has_route:bool=protected_map(current_map) and backend.quest_arrival.has_arrival(backend,current_map,current)
	if protected_map(map_id) and not has_route:return public_entrance(helper,backend)
	# Rebuild only from the canonical published stage. Raw NPC and stale step
	# requests use the same stage and final route check; no client fields count.
	var selected:Dictionary={}
	for quest in helper.snapshot(backend).quests:
		if int(quest.event)!=44:continue
		for candidate in quest.steps:
			if not can_visit(candidate) or int(candidate.map_id)!=map_id:continue
			if coupon_target(target):
				if str(candidate.get("npc_id",""))=="" and str(candidate.source.get("type",""))=="encounter" and candidate.cell==target.cell:selected=candidate;break
			elif str(candidate.get("npc_id",""))==str(target.id):selected=candidate;break
	if selected.is_empty():return {}
	if not protected_map(map_id):return public_entrance(helper,backend)
	if current_map!=map_id:return {}
	var delta:=current-Vector2i(int(target.cell[0]),int(target.cell[1]))
	if maxi(absi(delta.x),absi(delta.y))>2:return {}
	var geometry:Dictionary=walk_destination(helper,backend,target)
	if geometry.is_empty() or not backend.quest_arrival.has_arrival(backend,map_id,Vector2i(int(geometry.cell[0]),int(geometry.cell[1]))):return {}
	if not coupon_target(target):
		var branch:Dictionary=backend.original_quests.branch_for(target,backend.session._profile)
		if not backend.quest_arrival.check_action(backend,target,branch,"SERVICE" if str(target.get("kind","" )).begins_with("golden_bui_") else str(branch.get("type",""))).is_empty():return {}
	return {"map_id":current_map,"cell":[current.x,current.y],"npc_id":"" if coupon_target(target) else str(target.id)}
