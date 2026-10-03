extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const Wait=preload("res://tests/support/wait.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Route=preload("res://tests/support/original_route_driver.gd")
const MARJU="extra/event/marju@1300:70:51"
const KAITE="extra/event/marju01@119:97:88"
const GATE="genout/wpm_120_19_15@120:19:15"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func row(b,event:int) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==event:return q
 return {}
func talk(b,id:String) -> Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 if id==KAITE:check(Travel.walk_near(b,b.original_quests.npc_by_id(KAITE),[122,118,119]),"actual maze and paired portals reach recipient")
 var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":id,"mode":"near"})
 check(visit.ok,"real safe visit "+id)
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,c:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":c})
func trade(b,id:String) -> Dictionary:
 var r:=choose(b,talk(b,id),"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func clean_bag(b) -> void:
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
func enter(b) -> void:
 check(trade(b,GATE).ok and b.automation.position_map==122,"source gate really admits to122")
func leave(b)->void:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(Route.walk(b,119,Vector2i(103,93),[119]).get("ok",false),"walk original one-way exit")
 check(b.handle({"type":"report_position","map_id":121,"cell":[17,15]}).ok,"actual one-way exit leaves maze route")
 check(not b.quest_arrival.has_arrival(b,119,Vector2i(97,89)),"leaving clears maze arrival")
func run() -> void:
 var b=Backend.new()
 var reward_step:Dictionary=b.quest_helper.resolve_step(b,9,"marju:return")
 check(reward_step.get("reward_effects",[]).size()==3 and str(reward_step.get("effects_notice","")).contains("未实现效果类别：魔法"),"actual helper advertises all three source magic limitations")
 for reward in reward_step.get("reward_effects",[]):
  check(reward.effects.filter(func(e):return e.type=="stat").all(func(e):return bool(e.active)),"helper ordinary reward stats stay active")
 check(37 in b.quest_catalog.enabled_events and 38 in b.quest_catalog.enabled_events,"real mail chain registered")
 if b.original_quests.npc_by_id(MARJU).is_empty():check(false,"imported real NPC required");b.free();quit(1);return
 clean_bag(b)
 b.session.gm_raise_level(-1,49)
 var before:Dictionary=b.session.snapshot()
 trade(b,MARJU)
 check(b.session.snapshot().original_items==before.original_items and not Rules.flag(b.session.snapshot(),"now",37),"level49 cannot accept mail")
 for mode in ["near","arrival"]:
  var target:Dictionary=b.quest_helper.destination(b,b.original_quests.npc_by_id(KAITE),mode)
  check(int(target.get("map_id",-1))==120 and str(target.get("npc_id","bad")).is_empty(),"outside raw recipient redirects only to public entrance with no dialogue identity")
  check(b.handle({"type":"quest_visit","npc_id":KAITE,"mode":mode}).ok and b.automation.position_map==120,"raw helper cannot skip original maze entry")
 b.automation.position_changed(119,Vector2i(97,89))
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":KAITE,"mode":mode}).ok,"project maze position cannot authorize raw recipient")
  check(not b.handle({"type":"quest_visit","quest_id":5,"step_id":"marju:deliver","mode":mode}).ok,"stale step cannot bless project arrival")
 check(not b.handle({"type":"quest_talk","npc_id":KAITE}).ok,"project position cannot use independent cutting-stone branch")
 b.session.gm_raise_level(-1,50)
 var r:=talk(b,MARJU)
 before=b.session.snapshot();b.save_path="user://missing-marju-dir/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"failed request save grants neither mail nor NOW37")
 b.save_path=""
 check(trade(b,MARJU).ok and 2687 in b.session.snapshot().original_items and Rules.flag(b.session.snapshot(),"now",37),"Lv50 original mail accepted")
 check(not Rules.flag(b.session.snapshot(),"ended",37) and not Rules.flag(b.session.snapshot(),"ended",38),"acceptance grants no completion")
 enter(b)
 # Bag capacity is checked before deletion for the original REQUEST38.
 var mail_state:Dictionary=b.session.snapshot()
 while Session.bag_slots(b.session._profile)<15:Session.OriginalEquipment.add(b.session._profile,2687)
 before=b.session.snapshot()
 check(not trade(b,KAITE).ok and b.session.snapshot().original_items==before.original_items,"full bag cannot exchange letter even at net zero")
 b.session._profile=mail_state
 r=talk(b,KAITE)
 before=b.session.snapshot();b.save_path="user://missing-marju-dir/save.json"
 check(not choose(b,r,"yes").ok and b.session.snapshot()==before,"failed delivery save preserves mail and both flags")
 b.save_path=""
 check(trade(b,KAITE).ok,"actual delivery succeeds")
 check(Rules.flag(b.session.snapshot(),"ended",37) and not Rules.flag(b.session.snapshot(),"ended",38) and not 2687 in b.session.snapshot().original_items and 2697 in b.session.snapshot().original_items,"delivery completes37 only and exchanges letter for cutting stone")
 check(row(b,38).status=="进行中" and row(b,38).steps[0].current,"helper requires return for38")
 leave(b)
 r=choose(b,talk(b,MARJU),"yes")
 before=b.session.snapshot();b.save_path="user://missing-marju-dir/save.json"
 check(not choose(b,r,"ok").ok and b.session.snapshot()==before,"failed final save grants no random weapon/END38")
 b.save_path="user://marju-chain.json"
 r=choose(b,talk(b,MARJU),"yes")
 check(choose(b,r,"ok").ok and Rules.flag(b.session.snapshot(),"ended",38),"return commits actual END38")
 var items:Array=b.session.snapshot().original_items
 check(items.size()==2 and items[0]==2697 and int(items[1]) in [2688,2689,2690],"one of exactly three source weapons awarded")
 check(not choose(b,r,"ok").ok,"reward token replay rejected")
 before=b.session.snapshot();trade(b,MARJU)
 check(b.session.snapshot().original_items==before.original_items,"finished dialogue cannot reward twice")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path) and loaded.snapshot().original_events==before.original_events and loaded.snapshot().original_items==before.original_items,"both completion bits and reward reload")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(b.save_path+suffix))
 b.save_path=""
 # The original replacement is MESSAGE+GetItem, with the same atomic save.
 enter(b)
 check(b.handle({"type":"quest_discard","item_id":2697}).ok,"real discard removes cutting stone")
 place_for_message(b)
 before=b.session.snapshot();b.save_path="user://missing-marju-dir/save.json"
 check(not b.handle({"type":"quest_talk","npc_id":KAITE}).ok and b.session.snapshot()==before,"replacement MESSAGE save failure keeps stone absent")
 b.save_path=""
 check(b.handle({"type":"quest_talk","npc_id":KAITE}).ok and b.session.snapshot().original_items.count(2697)==1,"source replacement gives one stone")
 var completed:Dictionary=b.session.snapshot()
 # Branch-selection fixture only; retain the actually walked route.
 Rules.set_flag(b.session._profile,"now",37,false)
 Rules.set_flag(b.session._profile,"ended",37,false)
 Rules.set_flag(b.session._profile,"ended",38,false)
 check(b.handle({"type":"quest_discard","item_id":2697}).ok,"discard before independent source branch")
 check(Travel.commit(b,b.original_quests.npc_by_id(KAITE)) and 2697 in b.session.snapshot().original_items and not Rules.flag(b.session.snapshot(),"ended",37) and not Rules.flag(b.session.snapshot(),"ended",38),"legitimate independent cutting stone preserves original flags")
 b.session._profile=completed
 b.original_quests.pending={}
 b.automation.position_changed(119,Vector2i(98,89))
 for mode in ["near","arrival"]:
  check(not b.handle({"type":"quest_visit","npc_id":KAITE,"mode":mode}).ok,"same-room project move clears recipient navigation authority")
 check(b.handle({"type":"quest_discard","item_id":2697}).ok,"discard after invalidating route")
 before=b.session.snapshot()
 check(not b.handle({"type":"quest_talk","npc_id":KAITE}).ok and b.session.snapshot()==before,"project replacement cannot write a cutting stone")
 b.free()
 await lan()
 print("MARJU QUEST: %d failures"%failures)
 quit(1 if failures else 0)
func place_for_message(b) -> void:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(Travel.walk_near(b,b.original_quests.npc_by_id(KAITE),[122,118,119]),"walk original maze for replacement")
 var point:Vector2i=b.automation.position_cell
 for mode in ["near","arrival"]:
  check(b.handle({"type":"quest_visit","npc_id":KAITE,"mode":mode}).ok and b.automation.position_cell==point,"both modes remain at legitimate near recipient")
func rpc(link,command:Dictionary) -> Dictionary:
 var replies:Array=[]
 link.request(command,func(r):replies.append(r))
 check(await Wait.until(self,func():return not replies.is_empty()),"LAN command roundtrip")
 return replies[0] if not replies.is_empty() else {}
func lan() -> void:
 var b=Backend.new();root.add_child(b)
 b.session.gm_raise_level(-1,50);clean_bag(b)
 check(trade(b,MARJU).ok,"LAN mail accepted through real source")
 # Connect both devices before real admission to validate helper updates.
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"LAN ephemeral server")
 var links:Array=[];var states:Array=[];var pollers:Array=[]
 for i in range(2):
  var link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
  var state=preload("res://network/client_state.gd").new()
  link.message.connect(state.apply)
  var poller:Callable=func():link.poll(0.016)
  process_frame.connect(poller);links.append(link);states.append(state);pollers.append(poller);link.connect_now()
  check(await Wait.until(self,func():return link.online and not state.profile.is_empty()),"remote profile connects")
  await rpc(link,{"type":"ping"})
 check(links.all(func(l):return l.backend==null),"two remote clients have no backend")
 var forged:Dictionary=await rpc(links[0],{"type":"quest_visit","quest_id":5,"step_id":"marju:deliver","npc_id":KAITE,"mode":"near","map_id":119})
 check(forged.ok and b.automation.position_map==120,"stale step and forged client map redirect only to public original entrance")
 await rpc(links[0],{"type":"quest_visit","npc_id":GATE,"mode":"near"})
 var offer:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":GATE})
 check((await rpc(links[0],{"type":"quest_choose","token":offer.dialogue.token,"choice":"yes"})).ok,"real socket enters through original50 gate")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(state):return state.derived.quest_helper.quests.any(func(q):return int(q.event)==37 and q.steps.any(func(step):return step.id=="marju:deliver" and not step.current))),"both devices require actual maze walk after entry")
 var publications:=[0,0]
 for i in range(2):
  var index:=i
  links[i].message.connect(func(event):
   if event.get("type","")=="profile":publications[index]+=1)
 var moved:Dictionary=await rpc(links[0],{"type":"report_position","map_id":122,"cell":[6,6]})
 for link in links:await rpc(link,{"type":"ping"})
 check(moved.ok and publications==[0,0],"same maze region movement emits no profile broadcast")
 check(Travel.walk_near(b,b.original_quests.npc_by_id(KAITE),[122,118,119]),"LAN authority walks actual maze")
 b.publish()
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(state):return state.derived.quest_helper.quests.any(func(q):return int(q.event)==37 and q.steps.any(func(step):return step.id=="marju:deliver" and step.current))),"near arrival refreshes both client actions")
 check(trade(b,KAITE).ok,"LAN earns37 through original recipient")
 leave(b)
 for link in links:await rpc(link,{"type":"ping"})

 await rpc(links[0],{"type":"quest_visit","npc_id":MARJU,"mode":"near"})
 var a:Dictionary=await rpc(links[0],{"type":"quest_talk","npc_id":MARJU})
 a=await rpc(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"yes"})
 await rpc(links[0],{"type":"ping"})
 var other:Dictionary=await rpc(links[1],{"type":"quest_talk","npc_id":MARJU})
 var stale:Dictionary=await rpc(links[0],{"type":"quest_choose","token":a.dialogue.token,"choice":"ok"})
 check(not stale.ok and not Rules.flag(b.session.snapshot(),"ended",38),"second socket invalidates first reward token")
 other=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"yes"})
 var done:Dictionary=await rpc(links[1],{"type":"quest_choose","token":other.dialogue.token,"choice":"ok"})
 check(done.ok,"second socket commits one source weapon")
 for link in links:await rpc(link,{"type":"ping"})
 check(states.all(func(s):return Rules.flag(s.profile,"ended",38) and s.profile.original_items.size()==2),"both devices see same completed chain and one reward")
 check(states[0].profile.original_items==states[1].profile.original_items,"both devices see identical random weapon")
 for i in range(2):links[i].close();process_frame.disconnect(pollers[i])
 server.stop();server.queue_free();b.queue_free();await process_frame
