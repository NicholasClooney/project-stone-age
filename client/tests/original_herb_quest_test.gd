extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const MapFile=preload("res://scripts/map_file.gd")
const GIRL="jaruga/event/event01_1"
const DOCTOR="jaruga/event/event01_2"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func row(b) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==1:return q
 return {}
func current(b,id:String) -> bool:
 return row(b).steps.any(func(s):return s.id==id and s.current and s.actionable)
func talk(b,id:String) -> Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":id,"mode":"near"})
 check(visit.ok,"real safe visit "+id)
 return b.handle({"type":"quest_talk","npc_id":id})
func choose(b,r:Dictionary,c:String) -> Dictionary:
 return b.handle({"type":"quest_choose","token":r.get("dialogue",{}).get("token",""),"choice":c})
func trade(b,id:String) -> Dictionary:
 var r:=choose(b,talk(b,id),"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func run() -> void:
 var b=Backend.new()
 check(b.quest_catalog.enabled_events==[1,2,4,15,16,18,19,28,29,30,31,54],"herb publicly enabled with existing quests")
 check(row(b).steps.size()==3 and current(b,"herb:request") and not row(b).repeatable,"three original stages, no invented CLEAN")
 for id in [GIRL,DOCTOR]:
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  check(FileAccess.file_exists("res://assets/legacy/"+str(npc.path)),"original 2.5 NPC art exists")
  var map:Dictionary=MapFile.load_map(b.quest_helper.places.file(int(npc.map_id)))
  var nav=preload("res://scripts/nav_grid.gd").new()
  nav.region=Rect2i(0,0,int(map.width),int(map.height));nav.update()
  for y in range(int(map.height)):
   for x in range(int(map.width)):
    var point:=Vector2i(x,y)
    nav.set_point_solid(point,not b.quest_helper.safe(map,point,{Vector2i(npc.cell[0],npc.cell[1]):true},b.quest_helper.places.links(int(npc.map_id))))
  var arrival:Dictionary=b.quest_helper.destination(b,npc,"arrival")
  var neighbour:Dictionary=b.quest_helper.destination(b,npc,"near")
  check(not nav.get_id_path(Vector2i(arrival.cell[0],arrival.cell[1]),Vector2i(neighbour.cell[0],neighbour.cell[1])).is_empty(),"actual arrival walking grid reaches NPC neighbour")
  for mode in ["near","arrival"]:
   var target:Dictionary=b.quest_helper.destination(b,npc,mode)
   check(not target.is_empty(),"NPC reachable landing "+mode)
   if target.is_empty():continue
   var cell:=Vector2i(target.cell[0],target.cell[1])
   check(b.quest_helper.safe(map,cell,{Vector2i(npc.cell[0],npc.cell[1]):true},b.quest_helper.places.links(int(npc.map_id))),"no portal, occupied or blocked landing")
 # Event87 alone and unreviewed grinding items cannot grant medicine.
 Rules.set_flag(b.session._profile,"now",87,true)
 check(not b.original_quests.branch_for(b.original_quests.npc_by_id(DOCTOR),b.session.snapshot()).has("actions"),"event87 disabled")
 Rules.set_flag(b.session._profile,"now",87,false)
 b.session._profile.original_items=[1982,1983]
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(DOCTOR),b.session.snapshot()).is_empty(),"grinding service disabled")
 b.session._profile.original_items=[]
 b.session._profile.original_savepoint_bits=0
 b.session._profile.player.level=0
 check(b.original_quests.branch_for(b.original_quests.npc_by_id(GIRL),b.session.snapshot()).is_empty(),"original LV>0 boundary")
 b.session._profile.player.level=1
 var unstarted:Dictionary=b.session.snapshot()
 b.save_path="user://missing-herb-directory/save.json"
 check(not trade(b,GIRL).ok and b.session.snapshot().original_events==unstarted.original_events,"failed REQUEST save does not set NOW")
 b.save_path=""
 check(choose(b,talk(b,GIRL),"no").ok and not Rules.flag(b.session.snapshot(),"now",1),"request refusal has no flag")
 check(trade(b,GIRL).ok and Rules.flag(b.session.snapshot(),"now",1) and current(b,"herb:medicine"),"LV>0 and no SP gate starts herb")
 var opened:=talk(b,DOCTOR)
 var texts:Dictionary=b.original_quests.branch_for(b.original_quests.npc_by_id(DOCTOR),b.session.snapshot()).texts
 check(opened.dialogue.text==Rules.message(texts,"AcceptMsg") and opened.dialogue.text.contains(str(texts.AcceptMsg2)),"both numbered AcceptMsg in source order")
 check(choose(b,opened,"no").ok and b.session.snapshot().original_items.is_empty(),"medicine refusal preserves bag")
 var thanks:=choose(b,talk(b,DOCTOR),"yes")
 check(thanks.dialogue.text==Rules.message(texts,"ThanksMsg") and thanks.dialogue.text.ends_with(str(texts.ThanksMsg4)) and b.session.snapshot().original_items.is_empty(),"all four thanks precede final receipt")
 check(b.handle({"type":"quest_close","token":thanks.dialogue.token}).ok and not choose(b,thanks,"ok").ok,"closing thanks invalidates token")
 b.session._profile.original_items.resize(14);b.session._profile.original_items.fill(2414)
 check(Session.bag_slots(b.session.snapshot())==15,"actual 15-slot full bag")
 var before:Dictionary=b.session.snapshot()
 check(not trade(b,DOCTOR).ok and b.session.snapshot()==before,"full medicine receipt rolls back all flags/items")
 b.session._profile.original_items=[]
 b.save_path="user://missing-herb-directory/save.json"
 before=b.session.snapshot()
 check(not trade(b,DOCTOR).ok and b.session.snapshot()==before,"disk failure rolls back medicine")
 b.save_path=""
 check(trade(b,DOCTOR).ok and b.session.snapshot().original_items==[2401] and current(b,"herb:return"),"receipt advances helper")
 check(talk(b,DOCTOR).dialogue.text.contains("草药已经确实交给你"),"held medicine prevents duplicate grant")
 check(b.handle({"type":"quest_discard","item_id":2401}).ok and current(b,"herb:medicine"),"lost herb returns to doctor stage")
 check(trade(b,DOCTOR).ok,"doctor replenishes during NOW1")
 var charm:int=b.session.snapshot().player.charm
 check(choose(b,talk(b,GIRL),"no").ok and Rules.flag(b.session.snapshot(),"now",1),"return refusal preserves active task")
 b.session._profile.original_items=[]
 check(trade(b,GIRL).ok and not Rules.flag(b.session.snapshot(),"now",1) and b.session.snapshot().player.charm==charm-1,"cancel absent herb clears NOW and deducts charm")
 check(trade(b,GIRL).ok and trade(b,DOCTOR).ok,"cancelled quest can be accepted again")
 for i in range(13):b.session._profile.original_items.append(2414)
 check(Session.bag_slots(b.session.snapshot())==15,"full return bag including herb")
 thanks=choose(b,talk(b,GIRL),"yes")
 b.save_path="user://missing-herb-directory/save.json"
 before=b.session.snapshot()
 check(not choose(b,thanks,"ok").ok and b.session.snapshot()==before,"save failure rolls back deleted herb and END")
 b.save_path=""
 thanks=choose(b,talk(b,GIRL),"yes")
 var token:String=thanks.dialogue.token
 check(choose(b,thanks,"ok").ok and Session.bag_slots(b.session.snapshot())==15 and 2427 in b.session.snapshot().original_items and not 2401 in b.session.snapshot().original_items,"net capacity return atomically exchanges reward")
 check(Rules.flag(b.session.snapshot(),"ended",1) and not Rules.flag(b.session.snapshot(),"now",1) and row(b).status=="已完成" and not row(b).can_restart,"END1 completed without repeat")
 check(not choose(b,{"dialogue":{"token":token}},"ok").ok,"completion token cannot replay")
 check(talk(b,GIRL).dialogue.text=="你的大恩大德，我一辈子都不会忘记的","original NomalMsg completion text")
 check(b.handle({"type":"quest_discard","item_id":2427}).ok and not row(b).can_restart,"lost reward never invents CLEAN")
 before=b.session.snapshot()
 check(talk(b,DOCTOR).ok and b.session.snapshot().original_items==before.original_items and b.session.snapshot().original_events==before.original_events and not 2401 in before.original_items,"completed doctor grants no new herb")
 var path:="user://herb-roundtrip.json"
 var loaded=Session.new()
 check(b.session.save_game(path) and loaded.load_game(path) and loaded.snapshot().original_events==b.session.snapshot().original_events and loaded.snapshot().original_items==b.session.snapshot().original_items,"flags and instances survive disk roundtrip")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(path+suffix)
 b.free()
 print("ORIGINAL HERB QUEST: %d failures" % failures)
 quit(1 if failures else 0)
