extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Rules=preload("res://server/original_quests.gd")
const Guide=preload("res://server/golden_bui_helper.gd")
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
	var b=Backend.new();b.set_process(false)
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
		check(not b.handle({"type":"quest_visit","npc_id":"quiz/equiz_02@810:28:16"}).ok,"Raw reward NPC cannot bypass stage restrictions")
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
		var lower:=Guide.stage_key(b)
		b.handle({"type":"report_position","map_id":int(band.base),"cell":[29,21]})
		check(Guide.stage_key(b)==lower,"Same source component movement keeps helper cache key stable")
		var coupon:=step(b,"coupon:")
		check(visit(b,coupon).ok and b.automation.position_cell.y==21,"Coupon visit stays on current original entry side")
		b.handle({"type":"report_position","map_id":int(band.base)+1,"cell":[32,26],"map_changed":true})
		check(not visit(b,coupon).ok,"Old step_id after map change cannot return or cross floors")
		b.free()
	var all_floors=fresh(70)
	Session.OriginalEquipment.add(all_floors.session._profile,2752)
	for base in [800,820,840]:
		for floor_index in range(10):
			all_floors.automation.position_changed(base+floor_index,Vector2i(14 if floor_index%2==0 else 32,26),true)
			var current:=step(all_floors,"challenge:")
			check(visit(all_floors,current).ok and all_floors.automation.position_map==base+floor_index and all_floors.automation.position_cell.y==21,"All30 navigation targets stay on original challenge side")
			all_floors.automation.position_changed(base+floor_index,Vector2i(int(current.cell[0]),15))
			check(step(all_floors,"stairs:").current and not visit(all_floors,current).ok,"All30 passed-side stages reject entry-side navigation replay")
	all_floors.free()
	var b=fresh(30)
	b.automation.position_changed(800,Vector2i(29,21),true)
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
	b.automation.position_changed(802,Vector2i(29,21),true)
	check(step(b,"challenge:").current and str(quest(b).completion_detail).contains("没有猜拳的参加券"),"Original no-ticket janken remains actionable and explained")
	b.automation.position_changed(810,Vector2i(29,20),true)
	var claim:=step(b,"claim:")
	check(visit(b,claim).ok,"Reached original reward room allows source coupon issuer")
	r=choose(b,b.handle({"type":"quest_talk","npc_id":claim.npc_id}),"yes")
	if r.has("dialogue"):r=choose(b,r,"ok")
	check(r.ok and Rules.flag(b.session.snapshot(),"now",44),"Original claim sets NOW44")
	var exchange:=step(b,"exchange:")
	check(visit(b,exchange).ok,"Held original2753 and NOW44 derive source exchange")
	r=choose(b,b.handle({"type":"quest_talk","npc_id":exchange.npc_id}),"yes")
	check(choose(b,r,"ok").ok and quest(b).status=="已完成","Original pet exchange updates helper END44")
	check(not choose(b,r,"ok").ok and b.session.snapshot().pets.size()==1,"Old exchange token cannot duplicate golden Bui")
	check(not visit(b,exchange).ok and not visit(b,claim).ok,"Completed helper rejects stale reward navigation")
	b.free()
	var moving=fresh(30)
	moving.automation.position_changed(800,Vector2i(18,13),true)
	var emitted:Array=[]
	moving.event.connect(func(message):emitted.append(message))
	moving.handle({"type":"report_position","map_id":801,"cell":[32,26],"map_changed":true})
	check(emitted.any(func(message):return str(message.get("type",""))=="profile" and message.get("derived",{}).get("quest_helper",{}).get("quests",[]).any(func(q):return int(q.event)==44 and q.steps.any(func(s):return str(s.id)=="golden44:coupon:801"))),"Natural map report publishes changed helper stage to already connected devices")
	emitted.clear()
	moving.handle({"type":"report_position","map_id":801,"cell":[32,25]})
	check(not emitted.any(func(message):return str(message.get("type",""))=="profile"),"Same-region movement does not publish full helper/profile again")
	moving.free()
	print("GOLDEN BUI HELPER: %d failures"%failures)
	quit(1 if failures else 0)
