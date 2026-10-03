extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Quests=preload("res://server/original_quests.gd")
const Hub=preload("res://server/profile_hub.gd")
const HAHN="jaruga/event/20501ev1"
const WATER="jaruga/event/20501ev2"
const BARL="jaruga/event/20501ev3"
const GOSSIP="jaruga/event/20501ev4"
const MERCHANT="jaruga/event/20501ev5"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func fresh():
	var b=Backend.new()
	b.quest_catalog.enabled_events=[2,18,19]
	b.session._profile.inventory.potion=0
	b.session._profile.player.level=15
	return b
func near(b,id: String) -> void:
	var n: Dictionary=b.original_quests.npc_by_id(id)
	if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
	if int(n.map_id) in range(20501,20509):
		check(preload("res://tests/support/legacy_cave_route.gd").approach(b,n).ok,"actual original wood cave route")
	else:check(b.handle({"type":"quest_visit","npc_id":id,"mode":"near"}).ok,"public wood village visit")
func talk(b,id: String) -> Dictionary:
	near(b,id)
	return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,reply: Dictionary,choice: String) -> Dictionary:
	return b.handle({"type":"quest_choose","token":reply.get("dialogue",{}).get("token",""),"choice":choice})
func accept(b,id: String) -> Dictionary:
	return choose(b,choose(b,talk(b,id),"yes"),"ok")
func request(b,id: String) -> Dictionary:
	return choose(b,talk(b,id),"yes")
func run() -> void:
	catalog_checks()
	chain()
	payouts()
	atomic_rejections()
	flag_order()
	lan()
	print("ORIGINAL WOOD QUEST: %d failures" % failures)
	quit(1 if failures else 0)
func catalog_checks() -> void:
	var b=fresh()
	check(b.quest_catalog.active_npcs().size()==9,"fixture enables seven quest NPCs plus two independent beauticians")
	check(b.original_quests.npc_by_id(HAHN).branches.size()==8,"unreviewed key branches disabled")
	b.quest_catalog.enabled_events=[18]
	check(b.quest_catalog.active_npcs().size()==7,"event18 activates wood chain while independent services stay available")
	b.quest_catalog.enabled_events=[2]
	check(b.quest_catalog.active_npcs().size()==4 and b.original_quests.npc_by_id(WATER).is_empty(),"shell-only fixture excludes wood")
	b.free()
func chain() -> void:
	var b=fresh()
	b.session._profile.player.level=14
	var low:=talk(b,BARL)
	check(low.ok and b.original_quests.pending.phase=="end" and b.session.snapshot().original_items.is_empty(),"LV>14 rejects level14")
	b.session._profile.player.level=15
	var before: Dictionary=b.session.snapshot()
	check(choose(b,talk(b,BARL),"no").ok and b.session.snapshot()==before,"REQUEST no unchanged")
	check(request(b,BARL).ok and b.session.snapshot().original_items==[2466] and Quests.flag(b.session.snapshot(),"now",18),"Barl original request gives commission NOW18")
	b.session._profile.original_items.erase(2466)
	var message:=talk(b,BARL)
	check(message.ok and b.session.snapshot().original_items==[2466] and message.dialogue.text.contains("委托书"),"MESSAGE replaces commission immediately")
	check(request(b,HAHN).ok and b.session.snapshot().original_items==[2466,2463] and Quests.flag(b.session.snapshot(),"now",19),"Hahn request gives empty jar NOW19")
	b.session._profile.original_items.erase(2463)
	check(talk(b,HAHN).ok and b.session.snapshot().original_items==[2466,2463],"Hahn MESSAGE replaces lost empty jar immediately")
	var opened:=talk(b,WATER)
	before=b.session.snapshot()
	check(choose(b,opened,"no").ok and b.session.snapshot()==before,"water ACCEPT no preserves")
	var thanks:=choose(b,talk(b,WATER),"yes")
	check(thanks.ok and b.session.snapshot()==before and thanks.dialogue.text.contains("请等一下"),"ACCEPT yes displays original ThanksMsg before exchange")
	check(choose(b,thanks,"ok").ok and b.session.snapshot().original_items==[2466,2464],"water ACK swaps empty jar for full jar")
	check(talk(b,WATER).dialogue.text.contains("洒出来"),"full jar MESSAGE uses original first branch")
	check(accept(b,HAHN).ok and b.session.snapshot().original_items==[2465] and Quests.flag(b.session.snapshot(),"ended",19) and not Quests.flag(b.session.snapshot(),"now",19),"Hahn consumes jars and commission, gives axe END19")
	check(accept(b,BARL).ok and b.session.snapshot().original_items==[2467,2484] and Quests.flag(b.session.snapshot(),"ended",18) and not Quests.flag(b.session.snapshot(),"now",18),"Barl consumes axe, gives recommendation and broken axe END18")
	check(request(b,MERCHANT).ok and b.session.snapshot().original_items==[2484,2478],"merchant REQUEST consumes recommendation and gives license")
	check(request(b,HAHN).ok and b.session.snapshot().original_items==[2478,2485],"broken axe repair consumes one and gives remodeled axe")
	check(accept(b,MERCHANT).ok and b.session.snapshot().original_items==[2485],"zero wood settlement consumes license")
	before=b.session.snapshot()
	check(choose(b,talk(b,GOSSIP),"no").ok and b.session.snapshot()==before,"CLEAN18 no keeps ended flag")
	check(request(b,GOSSIP).ok and not Quests.flag(b.session.snapshot(),"ended",18),"gossip CLEAN18 clears completion")
	check(request(b,HAHN).ok and not Quests.flag(b.session.snapshot(),"ended",19),"Hahn CLEAN19 allows repeated request")
	check(request(b,BARL).ok and request(b,HAHN).ok and accept(b,WATER).ok and accept(b,HAHN).ok and accept(b,BARL).ok,"original repeat loop completes a second axe delivery")
	var path="user://original-wood-roundtrip.json"
	var loaded=Session.new()
	check(b.session.save_game(path) and loaded.load_game(path) and loaded.snapshot()==b.session.snapshot(),"real GameSession reload preserves wood flags and rewards")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
	b.free()
func payouts() -> void:
	var rewards=[0,400,1600,2400,3200,4000,4800,5600,6400,7200,8000,10000,12000,16000,20000]
	for count in range(15):
		var b=fresh()
		b.session._profile.original_items=[2478]
		# 14 wood + license occupy the complete 15-slot original bag.
		if count<14:b.session._profile.original_items.append(2467)
		for i in range(count):b.session._profile.original_items.append(2468)
		var before: Dictionary=b.session.snapshot()
		var opened:=talk(b,MERCHANT)
		check(choose(b,opened,"no").ok and b.session.snapshot()==before,"wood %d ACCEPT no atomic" % count)
		var thanks:=choose(b,talk(b,MERCHANT),"yes")
		check(thanks.ok and b.session.snapshot()==before,"wood %d waits second ACK" % count)
		var token: String=thanks.dialogue.token
		var done:=choose(b,thanks,"ok")
		var p: Dictionary=b.session.snapshot()
		check(done.ok and p.player.gold==before.player.gold+rewards[count] and not 2468 in p.original_items and not 2478 in p.original_items,"wood %d exact original cash and consumption" % count)
		check((2467 in p.original_items)==(count in [0,12]) and (2481 in p.original_items)==(count==14),"wood %d recommendation exception and bracelet" % count)
		check(not b.handle({"type":"quest_choose","token":token,"choice":"ok"}).ok,"wood %d cannot replay reward" % count)
		b.free()
	var b=fresh()
	b.session._profile.original_items=[2468,2467]
	var before: Dictionary=b.session.snapshot()
	check(talk(b,MERCHANT).dialogue.text.contains("许可证") and b.session.snapshot()==before,"wood without license hits refusal before recommendation REQUEST")
	b.free()
func atomic_rejections() -> void:
	var b=fresh()
	Quests.set_flag(b.session._profile,"now",18,true)
	b.save_path="user://missing-wood-directory/save.json"
	var before: Dictionary=b.session.snapshot()
	check(not talk(b,BARL).ok and b.session.snapshot()==before and b.original_quests.pending.is_empty(),"MESSAGE disk failure rolls back reward and NOW atomically")
	b.save_path="user://original-wood-message.json"
	check(talk(b,BARL).ok,"MESSAGE succeeds with real persistent backend")
	var loaded=Session.new()
	check(loaded.load_game(b.save_path) and loaded.snapshot().original_items==[2466] and Quests.flag(loaded.snapshot(),"now",18),"MESSAGE saved before display")
	for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(b.save_path+suffix)
	b.save_path=""
	b.session._profile.original_items=[]
	for i in range(15):b.session._profile.original_items.append(2485)
	before=b.session.snapshot()
	check(not talk(b,BARL).ok and b.session.snapshot()==before,"full bag MESSAGE rolls back")
	b.session._profile.original_items[0]=2467
	before=b.session.snapshot()
	check(not request(b,MERCHANT).ok and b.session.snapshot()==before,"license REQUEST needs actual free slot despite net zero")
	b.session._profile.original_items=[2465]
	for i in range(14):b.session._profile.original_items.append(2485)
	before=b.session.snapshot()
	check(not accept(b,BARL).ok and b.session.snapshot()==before,"axe-for-two reward rejects full bag")
	b.session._profile.original_items=[2478,2468]
	b.session._profile.player.gold=Quests.ORIGINAL_MAX_GOLD-400
	before=b.session.snapshot()
	check(not accept(b,MERCHANT).ok and b.session.snapshot()==before,"exact maxGold rejects entire exchange including input deletion")
	b.session._profile.player.gold-=1
	check(accept(b,MERCHANT).ok and b.session.snapshot().player.gold==Quests.ORIGINAL_MAX_GOLD-1,"one below maxGold succeeds")
	b.session._profile.original_items=[2478,2468]
	b.session._profile.player.gold=20
	b.save_path="user://missing-wood-directory/save.json"
	before=b.session.snapshot()
	check(not accept(b,MERCHANT).ok and b.session.snapshot()==before,"cash exchange disk failure restores money and all items")
	b.save_path=""
	var thanks:=choose(b,talk(b,MERCHANT),"yes")
	b.session._profile.original_items.erase(2478)
	before=b.session.snapshot()
	check(not choose(b,thanks,"ok").ok and b.session.snapshot()==before,"lost license revalidation rejects reward")
	b.session._profile.original_items=[2466,2463,2463]
	Quests.set_flag(b.session._profile,"now",19,true)
	var charm: int=b.session.snapshot().player.charm
	check(request(b,HAHN).ok and b.session.snapshot().original_items==[2466] and b.session.snapshot().player.charm==charm-1,"cancel removes all quantified REQUEST copies and charm")
	# Fail closed even for a MESSAGE that otherwise has a valid reward.
	var npc: Dictionary=b.quest_catalog.npcs[4]
	var original: Dictionary=npc.branches[0].duplicate(true)
	npc.branches[0].condition="LV>0";npc.branches[0].actions={"Teleport":"3300"}
	before=b.session.snapshot()
	check(not talk(b,BARL).ok and b.session.snapshot()==before,"unknown MESSAGE action fails closed")
	npc.branches[0]=original
	b.free()
func flag_order() -> void:
	var b=fresh()
	near(b,BARL) # Synthetic action-order unit case still supplies the real public NPC context.
	var branch={"event":18,"actions":{"GetItem":"2467","EndSetFlg":"18,19","CleanFlg":"19"},"texts":{}}
	check(b.original_quests.transact(b,b.session.snapshot(),branch,"MESSAGE","",BARL).ok and Quests.flag(b.session.snapshot(),"ended",18) and not Quests.flag(b.session.snapshot(),"now",18) and not Quests.flag(b.session.snapshot(),"ended",19),"EndSetFlg then CleanFlg retains original ordered semantics")
	Quests.set_flag(b.session._profile,"now",18,true)
	b.session._profile.original_items=[2465]
	# The EventNo=-1 direct axe branch sets END18 without clearing NOW18.
	Quests.set_flag(b.session._profile,"ended",18,false)
	var direct: Dictionary=b.original_quests.npc_by_id(BARL).branches[3]
	check(b.original_quests.transact(b,b.session.snapshot(),direct,"reward","",BARL).ok and Quests.flag(b.session.snapshot(),"now",18) and Quests.flag(b.session.snapshot(),"ended",18),"EventNo=-1 does not clear another event NOW")
	check(b.quest_catalog.journal(b.session.snapshot()).size()==1 and b.quest_catalog.journal(b.session.snapshot())[0].state=="已完成","journal END precedes NOW and adds no event19 title")
	b.free()
func lan() -> void:
	var dir="user://original-wood-hub-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var hub=Hub.new(dir.path_join("accounts.json"))
	hub.tick=false;hub.backups=false;hub.share_dir=""
	check(hub.start(),"real wood ProfileHub starts")
	check(hub.handle(1,{"type":"create_profile","name":"WoodAlice","pin":"1111"}).ok and hub.handle(2,{"type":"create_profile","name":"WoodBob","pin":"2222"}).ok and hub.handle(3,{"type":"login","name":"WoodAlice","pin":"1111"}).ok,"real auth two wood profiles and second device")
	var a=hub.backend_of(1);var b=hub.backend_of(2)
	for backend in [a,b]:
		backend.quest_catalog.enabled_events=[2,18,19]
		backend.session._profile.original_items=[2478,2468]
		near(backend,MERCHANT)
	var first: Dictionary=hub.handle(1,{"type":"quest_talk","npc_id":MERCHANT})
	var other: Dictionary=hub.handle(2,{"type":"quest_talk","npc_id":MERCHANT})
	var second: Dictionary=hub.handle(3,{"type":"quest_talk","npc_id":MERCHANT})
	check(not hub.handle(1,{"type":"quest_choose","token":first.dialogue.token,"choice":"yes"}).ok,"second wood device supersedes old token")
	var thanks: Dictionary=hub.handle(3,{"type":"quest_choose","token":second.dialogue.token,"choice":"yes"})
	check(hub.handle(3,{"type":"quest_choose","token":thanks.dialogue.token,"choice":"ok"}).ok and a.session.snapshot().player.gold==420 and b.session.snapshot().original_items==[2478,2468],"wood cash transaction isolated between real profiles")
	check(not hub.handle(2,{"type":"quest_choose","token":thanks.dialogue.token,"choice":"ok"}).ok and hub.handle(2,{"type":"quest_choose","token":other.dialogue.token,"choice":"no"}).ok,"foreign wood token preserves own pending")
	var loaded=Session.new()
	check(loaded.load_game(a.save_path) and loaded.snapshot().player.gold==420 and loaded.snapshot().original_items.is_empty(),"LAN wood payout persisted to profile save")
	hub.shut_down();hub.free()
	for file in DirAccess.get_files_at(dir):DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
