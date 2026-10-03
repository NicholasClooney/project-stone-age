extends SceneTree
## Real Backend + two WebSocket devices. Item inputs plus actual original gate, services and portal fixtures.
const Backend = preload("res://server/backend.gd")
const Session = preload("res://server/game_session.gd")
const Server = preload("res://server/ws_server.gd")
const Link = preload("res://network/ws_link.gd")
const Wait = preload("res://tests/support/wait.gd")
const QUIZ := "genout/quz_800_29_19@800:29:19"
const FIST := "genout/jan_802_29_19@802:29:19"
var links: Array = []
var failures := 0
var private_catalog: Dictionary
func _initialize() -> void:call_deferred("run")
func check(value: bool, label: String) -> bool:
	if not value:
		failures+=1
		push_error(label)
	return value
func setup():
	var b=Backend.new()
	b.set_process(false)
	b.quest_catalog.enabled_events=[44]
	for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
	b.session.gm_raise_level(-1,30)
	return b
func place(b,id: String) -> void:
	var npc: Dictionary=b.original_quests.npc_by_id(id)
	if not check(not npc.is_empty(),"Source instance activated "+id):return
	check(preload("res://tests/support/golden_bui_route.gd").near(b,npc),"Actual original ticket gate and services reach fixture NPC")
func choice(b,reply: Dictionary,id: String,text := "") -> Dictionary:
	return b.handle({"type":"quest_choose","token":reply.get("dialogue",{}).get("token",""),"choice":id,"text":text})
func answer(reply: Dictionary) -> Dictionary:
	for question in private_catalog.services["genout/quz_800_29_19"].questions:
		if not str(reply.get("dialogue",{}).get("text","")).ends_with(str(question.text)):continue
		if int(question.answer_type)==4:return {"choice":"submit","text":str(question.options[0])}
		for entry in reply.dialogue.choices:
			if entry.text==question.options[int(question.answer)]:return {"choice":entry.id,"text":""}
	return {}
func public_only(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			if str(key) in ["answer_choice","answer_text","answer_type","level_mask","questions","service_state","services"]:return false
			if not public_only(value[key]):return false
	elif value is Array:
		for item in value:
			if not public_only(item):return false
	return true
func local_transactions() -> void:
	var b=setup()
	place(b,QUIZ)
	var initial: Dictionary=b.handle({"type":"quest_talk","npc_id":QUIZ})
	var before: Dictionary=b.session.snapshot()
	check(not choice(b,initial,"yes").ok and b.session.snapshot()==before,"Quiz without2752 does not start, reward or move")
	Session.OriginalEquipment.add(b.session._profile,2752)
	initial=b.handle({"type":"quest_talk","npc_id":QUIZ})
	before=b.session.snapshot()
	b.save_path="user://golden-bui-blocked/child.json"
	check(not choice(b,initial,"yes").ok and b.session.snapshot()==before,"Entry debit save failure rolls back exact profile")
	b.save_path=""
	initial=b.handle({"type":"quest_talk","npc_id":QUIZ})
	check(choice(b,initial,"no").ok and b.session.snapshot()==before,"Cancel before entry preserves coupon")
	initial=b.handle({"type":"quest_talk","npc_id":QUIZ})
	var question:=choice(b,initial,"yes")
	check(question.ok and not 2752 in b.session.snapshot().original_items,"Quiz ticket consumed once at real start")
	check(not choice(b,initial,"yes").ok,"Duplicate confirmation cannot start another quiz")
	var correct:=answer(question)
	before=b.session.snapshot()
	var position: Vector2i=b.automation.position_cell
	b.save_path="user://golden-bui-blocked/child.json"
	check(not choice(b,question,str(correct.get("choice","")),str(correct.get("text",""))).ok and b.session.snapshot()==before and b.automation.position_cell==position,"Reward and warp save failure grant neither")
	b.save_path=""
	Session.OriginalEquipment.add(b.session._profile,2752)
	initial=b.handle({"type":"quest_talk","npc_id":QUIZ});question=choice(b,initial,"yes")
	before=b.session.snapshot()
	check(choice(b,question,"cancel").ok and b.session.snapshot()==before and not 2752 in before.original_items,"Cancel after entry never refunds original consumed coupon")
	place(b,FIST)
	initial=b.handle({"type":"quest_talk","npc_id":FIST});question=choice(b,initial,"yes")
	check(question.ok and not 2751 in b.session.snapshot().original_items,"Approved original no-ticket janken reaches real server hand phase")
	before=b.session.snapshot()
	var result:=choice(b,question,"not-a-hand")
	check(not result.ok and b.session.snapshot()==before,"Malformed hand cannot warp")
	initial=b.handle({"type":"quest_talk","npc_id":FIST});question=choice(b,initial,"yes")
	var rng:=RandomNumberGenerator.new()
	for candidate in range(100):
		rng.seed=candidate
		if rng.randi_range(0,2)==1:
			b.original_quests.services.rng.seed=candidate
			break
	before=b.session.snapshot();position=b.automation.position_cell
	b.save_path="user://golden-bui-blocked/child.json"
	check(not choice(b,question,"rock").ok and b.session.snapshot()==before and b.automation.position_cell==position,"No-ticket win still requires persisted warp; failure cannot advance")
	b.save_path=""
	b.free()
func poll() -> void:
	for link in links:link.poll(0.01)
func request(link,command: Dictionary) -> Dictionary:
	var received: Array=[]
	link.request(command,func(reply):received.append(reply))
	check(await Wait.until(self,func():poll();return not received.is_empty()),"Real socket round trip")
	return received[0] if not received.is_empty() else {}
func lan() -> void:
	var b=setup();root.add_child(b)
	Session.OriginalEquipment.add(b.session._profile,2752)
	place(b,QUIZ)
	var server=Server.new(b,0,"127.0.0.1");root.add_child(server)
	if not check(server.start()==OK,"Ephemeral two-device server"):return
	var observed: Array=[]
	for i in range(2):
		var link=Link.new("ws://127.0.0.1:%d"%server.port)
		link.message.connect(func(event):observed.append(event.duplicate(true)))
		links.append(link);link.connect_now()
	if not check(await Wait.until(self,func():poll();return links.all(func(l):return l.online)),"Two independent sockets connected"):return
	await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
	var old: Dictionary=await request(links[0],{"type":"quest_talk","npc_id":QUIZ})
	var fresh: Dictionary=await request(links[1],{"type":"quest_talk","npc_id":QUIZ})
	var stale: Dictionary=await request(links[0],{"type":"quest_choose","token":old.dialogue.token,"choice":"yes"})
	check(not stale.ok and 2752 in b.session.snapshot().original_items,"Other device supersedes first token without spending ticket")
	var question: Dictionary=await request(links[1],{"type":"quest_choose","token":fresh.dialogue.token,"choice":"yes"})
	check(question.ok and public_only(question),"Question reply contains only public text/options")
	var correct:=answer(question)
	var submitted: Dictionary=await request(links[0],{"type":"quest_choose","token":question.dialogue.token,"choice":correct.choice,"text":correct.text,"answer":true,"state":{"correct":99},"actions":{"GetItem":"2753"}})
	check(submitted.ok and 2754 in b.session.snapshot().original_items and not 2753 in b.session.snapshot().original_items,"Second socket answers shared token; forged client state/reward ignored")
	var after: Dictionary=b.session.snapshot()
	var replay: Dictionary=await request(links[1],{"type":"quest_choose","token":question.dialogue.token,"choice":correct.choice,"text":correct.text})
	check(not replay.ok and b.session.snapshot()==after,"Other device cannot replay committed correct answer")
	place(b,FIST)
	old=await request(links[0],{"type":"quest_talk","npc_id":FIST})
	links[0].close()
	fresh=await request(links[1],{"type":"quest_talk","npc_id":FIST})
	links[0]=Link.new("ws://127.0.0.1:%d"%server.port);links[0].connect_now()
	check(await Wait.until(self,func():poll();return links[0].online),"Disconnected device reconnects")
	await request(links[0],{"type":"ping"});await request(links[1],{"type":"ping"})
	stale=await request(links[0],{"type":"quest_choose","token":old.dialogue.token,"choice":"yes"})
	check(not stale.ok,"Disconnected device's old token cannot replace current hand")
	question=await request(links[1],{"type":"quest_choose","token":fresh.dialogue.token,"choice":"yes"})
	check(question.ok and not 2751 in b.session.snapshot().original_items,"No-ticket original branch works remotely")
	for attempt in range(40):
		var hand_token: String=question.dialogue.token
		question=await request(links[1],{"type":"quest_choose","token":hand_token,"choice":"rock"})
		var hand_replay: Dictionary=await request(links[0],{"type":"quest_choose","token":hand_token,"choice":"paper"})
		check(not hand_replay.ok,"No-ticket hand token is single use including draws")
		if question.get("closed",false):break
	check(question.ok and question.get("closed",false),"Remote janken resolves original win/lose warp")
	check(observed.all(func(event):return public_only(event)),"No remote broadcast/snapshot exposes private questions or answers")
	for link in links:link.close()
	links=[];server.stop();server.queue_free();b.queue_free()
func run() -> void:
	private_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/server/golden-bui.json"))
	var blocked:=FileAccess.open("user://golden-bui-blocked",FileAccess.WRITE);blocked.store_string("not a directory");blocked.close()
	local_transactions()
	await lan()
	DirAccess.remove_absolute("user://golden-bui-blocked")
	print("golden_bui_transactions_test: %d failures"%failures)
	quit(1 if failures else 0)
