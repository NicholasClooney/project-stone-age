extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Rules=preload("res://server/original_quests.gd")
const Guide=preload("res://server/golden_bui_helper.gd")
const Travel=preload("res://tests/support/golden_bui_route.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(value:bool,label:String) -> bool:
	if not value:failures+=1;push_error(label)
	return value
func quest(b) -> Dictionary:
	for q in b.quest_helper.snapshot(b).quests:
		if int(q.event)==44:return q
	check(false,"Original job44 exists");return {}
func step(b,prefix:String) -> Dictionary:
	for s in quest(b).steps:
		if str(s.id).begins_with("golden44:"+prefix):return s
	return {}
func visit(b,s:Dictionary) -> Dictionary:
	return b.handle({"type":"quest_visit","quest_id":2,"step_id":s.get("id",""),"mode":"near"})
func choose(b,r:Dictionary,c:String,t:="") -> Dictionary:
	return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":c,"text":t})
func fresh(level:int):
	var b=Backend.new();b.set_process(false);b.quest_catalog.enabled_events=[44]
	b.session.gm_raise_level(-1,level);b.session._profile.player.gold=100000
	return b
func source_answer(b,r:Dictionary) -> Dictionary:
	var data:Dictionary=b.original_quests.services.context(b).catalog
	for q in data.services["genout/quz_800_29_19"].questions:
		if not str(r.dialogue.text).ends_with(str(q.text)):continue
		if int(q.answer_type)==4:return {"choice":"submit","text":str(q.options[0])}
		for c in r.dialogue.choices:
			if c.text==q.options[int(q.answer)]:return {"choice":str(c.id),"text":""}
	return {}
func run() -> void:
	for level in [29,30,49,50,69,70]:
		var b=fresh(level)
		var q:=quest(b)
		check(int(q.id)==2 and str(q.title)=="猜谜3兄弟" and not q.steps.is_empty(),"Original job2/event44 has substantive helper steps")
		check(not b.handle({"type":"quest_auto_start","quest_id":2}).ok,"Quest44 does not acquire unauthorized automatic play")
		var purchase:=step(b,"buy:")
		var exchange:=step(b,"exchange:")
		check(not visit(b,exchange).ok,"Future reward step denied on server, not merely hidden by UI")
		var outside:Dictionary=b.handle({"type":"quest_visit","npc_id":"quiz/equiz_02@810:28:16"})
		check((not outside.ok) if level<30 else (outside.ok and int(outside.target.map_id) in [2020,4020] and str(outside.target.npc_id)==""),"Raw reward request only permits the public ticket entrance")
		if level<30:
			check(not visit(b,purchase).ok and str(q.blocked_reason).contains("30"),"Level29 cannot navigate a stale purchase stage")
			b.free();continue
		var band:=Guide.band(level)
		check(visit(b,purchase).ok and b.automation.position_map==int(band.counter) and b.automation.position_cell==Vector2i(16,13),"Three-band purchase goes to original reachable counter side")
		var initial:Dictionary=b.handle({"type":"quest_talk","npc_id":purchase.npc_id})
		var paid:=choose(b,initial,"yes");paid=choose(b,paid,"ok")
		check(paid.ok and b.session.snapshot().player.gold==100000-int(band.fee),"Helper navigation still requires actual source fee")
		check(not visit(b,purchase).ok,"Old purchase step invalidated by held original ticket")
		var entrance:=step(b,"enter:")
		check(visit(b,entrance).ok and b.automation.position_cell.y==22,"Entrance navigates below original receptionist, never into challenge floor")
		initial=b.handle({"type":"quest_talk","npc_id":entrance.npc_id})
		check(choose(b,initial,"yes").ok and b.automation.position_map==int(band.base),"Original gate consumes original band ticket")
		check(not visit(b,entrance).ok and not int(band.ticket) in b.session.snapshot().original_items,"Old gate navigation rejected after original entry")
		check(step(b,"coupon:").current and not step(b,"challenge:").current,"Quiz first directs actual random coupon acquisition")
		check(not b.handle({"type":"quest_visit","npc_id":"genout/quz_801_18_19@801:18:19"}).ok,"Raw future-floor challenge target rejected")
		var stale_coupon:=step(b,"coupon:")
		for mode in ["near","arrival"]:
			var before:Vector2i=b.automation.position_cell
			check(not b.handle({"type":"quest_visit","quest_id":2,"step_id":stale_coupon.id,"mode":mode,"map_id":810,"cell":[29,16],"area_rect":[0,0,99,99],"npc_id":"quiz/equiz_01@810:29:16"}).ok and b.automation.position_cell==before,"Both modes ignore forged coupon fields and cannot skip original entry path")
			check(not b.handle({"type":"quest_visit","mode":mode,"npc_id":"","map_id":int(band.base),"cell":[29,21],"area_rect":[29,21,29,21]}).ok,"Raw empty-ID coupon spoof is not a server-resolved step")
		check(not Guide.owns({"id":"","map_id":int(band.base),"cell":[29,21],"area_rect":[0,0,99,99]}),"Unreviewed encounter rectangle is not owned by dojo helper")
		check(Route.walk(b,int(band.base),Vector2i(29,21),[int(band.base)]).ok,"Actual original path reaches first coupon point")
		check(b.quest_arrival.has_arrival(b,int(band.base),b.automation.position_cell),"Near-stage cache follows actual original walk")
		var coupon:=step(b,"coupon:")
		for mode in ["near","arrival"]:
			var legal:Dictionary=b.handle({"type":"quest_visit","quest_id":2,"step_id":coupon.id,"mode":mode})
			check(legal.ok and legal.target.cell==[29,21] and str(legal.target.npc_id)=="" and b.quest_arrival.has_arrival(b,int(band.base),b.automation.position_cell),"Both coupon modes preserve legal original point and route without moving")
		b.handle({"type":"report_position","map_id":int(band.base)+1,"cell":[32,26],"map_changed":true})
		check(not visit(b,coupon).ok,"Old step_id after map change cannot return or cross floors")
		b.free()
	var all_floors=fresh(70)
	Session.OriginalEquipment.add(all_floors.session._profile,2752)
	for base in [800,820,840]:
		for floor_index in range(10):
			all_floors.automation.position_changed(base+floor_index,Vector2i(14 if floor_index%2==0 else 32,26),true)
			var current:=step(all_floors,"challenge:")
			var rejected:Dictionary=visit(all_floors,current)
			check(rejected.ok and int(rejected.target.map_id)==4020 and str(rejected.target.npc_id)=="","All30 project placements only navigate back to public ticket entrance")
			all_floors.automation.position_changed(base+floor_index,Vector2i(int(current.cell[0]),15))
			check(step(all_floors,"stairs:").current and not visit(all_floors,current).ok,"All30 forged passed-side stages cannot reuse an old challenge step")
	for room in [810,850]:
		all_floors.automation.position_changed(room,Vector2i(29,17),true)
		var unchanged:Dictionary=all_floors.session.snapshot()
		var refused:Dictionary=all_floors.handle({"type":"quest_talk","npc_id":"quiz/equiz_01@%d:29:16"%room})
		check(not refused.ok and all_floors.session.snapshot()==unchanged,"Project placement in final room cannot issue2753 or NOW44")
		for mode in ["near","arrival"]:
			all_floors.automation.position_changed(room,Vector2i(29,17),true)
			var redirected:Dictionary=all_floors.handle({"type":"quest_visit","npc_id":"quiz/equiz_01@%d:29:16"%room,"mode":mode})
			check(redirected.ok and int(redirected.target.map_id)==4020 and str(redirected.target.npc_id)=="","Both raw final-room helper modes only return to public entrance")
	all_floors.free()
	var b=fresh(30)
	check(Travel.enter(b,800) and Route.walk(b,800,Vector2i(29,21),[800]).ok,"Original ticket and walk establish helper challenge fixture")
	Session.OriginalEquipment.add(b.session._profile,2752)
	var challenge:=step(b,"challenge:")
	check(visit(b,challenge).ok and b.automation.position_cell.y>=19,"Challenge navigation stays below original separating wall")
	var before_key:String=b.quest_helper.cached_key
	var r:=choose(b,b.handle({"type":"quest_talk","npc_id":challenge.npc_id}),"yes")
	var answer:=source_answer(b,r)
	check(not answer.is_empty() and choose(b,r,str(answer.get("choice","")),str(answer.get("text",""))).ok,"Actual source question succeeds")
	check(b.automation.position_cell.y<18 and step(b,"stairs:").current and b.quest_helper.cached_key!=before_key,"Actual quiz Warp invalidates helper region cache and reveals original stairs")
	check(not visit(b,challenge).ok,"Pre-answer navigation replay cannot cross back through wall")
	check(not b.handle({"type":"quest_visit","npc_id":challenge.npc_id}).ok,"Raw challenge NPC cannot ignore won-side navigation restriction")
	check(Travel.reach_floor(b,802),"Actual second quiz and portal reach original no-ticket janken")
	check(step(b,"challenge:").current and str(quest(b).completion_detail).contains("没有猜拳的参加券"),"Original no-ticket janken remains actionable and explained")
	check(Travel.near(b,b.original_quests.npc_by_id("quiz/equiz_01@810:29:16")),"All original services and portals precede final reward fixture")
	var claim:=step(b,"claim:")
	check(visit(b,claim).ok,"Reached original reward room allows source coupon issuer")
	r=choose(b,b.handle({"type":"quest_talk","npc_id":claim.npc_id}),"yes")
	if r.has("dialogue"):r=choose(b,r,"ok")
	check(r.ok and Rules.flag(b.session.snapshot(),"now",44),"Original claim sets NOW44")
	var exchange:=step(b,"exchange:")
	check(Travel.near(b,b.original_quests.npc_by_id(str(exchange.npc_id))) and visit(b,exchange).ok,"Held original2753 and NOW44 derive source nearby exchange")
	r=choose(b,b.handle({"type":"quest_talk","npc_id":exchange.npc_id}),"yes")
	check(choose(b,r,"ok").ok and quest(b).status=="已完成","Original pet exchange updates helper END44")
	check(not choose(b,r,"ok").ok and b.session.snapshot().pets.size()==1,"Old exchange token cannot duplicate golden Bui")
	check(not visit(b,exchange).ok and not visit(b,claim).ok,"Completed helper rejects stale reward navigation")
	b.free()
	var moving=fresh(30)
	check(Travel.enter(moving,800) and Travel.challenge(moving),"Actual first quiz establishes post-win helper fixture")
	var emitted:Array=[]
	moving.event.connect(func(message):emitted.append(message))
	check(Travel.reach_floor(moving,801),"Original stairs publish next helper stage")
	check(emitted.any(func(message):return str(message.get("type",""))=="profile" and message.get("derived",{}).get("quest_helper",{}).get("quests",[]).any(func(q):return int(q.event)==44 and q.steps.any(func(s):return str(s.id)=="golden44:coupon:801"))),"Natural map report publishes changed helper stage to already connected devices")
	emitted.clear()
	moving.handle({"type":"report_position","map_id":801,"cell":[32,25]})
	check(not emitted.any(func(message):return str(message.get("type",""))=="profile"),"Same-region movement does not publish full helper/profile again")
	moving.free()
	print("GOLDEN BUI HELPER: %d failures"%failures)
	quit(1 if failures else 0)
