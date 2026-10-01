extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const WorldCatalog=preload("res://scripts/world_catalog.gd")
const WsServer=preload("res://server/ws_server.gd")
const WsLink=preload("res://network/ws_link.gd")
const ClientState=preload("res://network/client_state.gd")
const Wait=preload("res://tests/support/wait.gd")
const MapFile=preload("res://scripts/map_file.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok: bool, note: String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func quest(b,event:int) -> Dictionary:
 for row in b.full_snapshot().derived.quest_helper.quests:
  if row.event==event:return row
 return {}
func has_current(row:Dictionary,npc:String,kind:String) -> bool:
 for step in row.steps:
  if step.current and step.npc_id==npc and step.source.type==kind:return true
 return false
func exchange(b,npc:String) -> void:
 var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":npc,"mode":"near"})
 check(visit.ok,"visit real source NPC")
 var reply:Dictionary=b.handle({"type":"quest_talk","npc_id":npc})
 check(reply.ok,"source talk")
 if not reply.ok:return
 reply=b.handle({"type":"quest_choose","token":reply.dialogue.token,"choice":"yes"})
 check(reply.ok,"source yes")
 if reply.has("dialogue"):
  reply=b.handle({"type":"quest_choose","token":reply.dialogue.token,"choice":"ok"})
  check(reply.ok,"source confirmation")
func run() -> void:
 for bit in range(4):shell(bit)
 visits()
 wood()
 harvest_visit()
 await remote()
 print("QUEST HELPER: %d failures" % failures)
 quit(1 if failures else 0)
func shell(bit:int) -> void:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2]
 b.session._profile.original_savepoint_bits=1<<bit
 var first: String="sainasu/event/event02_2" if bit in [0,3] else "sainasu/event/event02_1"
 var last: String="sainasu/event/event02_1" if bit in [0,3] else "sainasu/event/event02_2"
 check(quest(b,2).status=="未开始" and quest(b,18).blocked_reason=="尚未开放","all known jobs retained before starting")
 check(has_current(quest(b,2),first,"REQUEST"),"SP%d original starting branch" % bit)
 exchange(b,first)
 check(quest(b,2).status=="进行中" and has_current(quest(b,2),last,"ACCEPT"),"active direction derives from actual item")
 exchange(b,last)
 check(quest(b,2).status=="已完成" and quest(b,2).repeatable and not quest(b,2).can_restart,"reward in bag prevents CLEAN")
 var reward:int=2414 if bit in [0,3] else 2415
 check(b.handle({"type":"quest_discard","item_id":reward}).ok,"explicit player discard")
 check(quest(b,2).can_restart,"real CLEAN eligibility after discard")
 exchange(b,last)
 check(quest(b,2).status=="未开始","real CLEAN returns to not started")
 b.free()
func visits() -> void:
 var b=Backend.new()
 var before:Vector2i=b.automation.position_cell
 var origin:int=b.automation.position_map
 check(not b.handle({"type":"quest_visit","npc_id":"invented","cell":[1,2],"map_id":42}).ok,"unknown NPC refused")
 check(b.automation.position_cell==before and b.automation.position_map==origin,"rejection preserves position")
 b.battle_open=true
 check(not b.handle({"type":"quest_visit","npc_id":"sainasu/event/event02_2"}).ok,"battle locks travel")
 b.battle_open=false
 b.quest_visit_guard=func():return "party locked"
 check(not b.handle({"type":"quest_visit","npc_id":"sainasu/event/event02_2"}).ok,"party guard locks travel")
 b.quest_visit_guard=Callable()
 for mode in ["near","arrival"]:
  var reply:Dictionary=b.handle({"type":"quest_visit","npc_id":"sainasu/event/event02_2","mode":mode,"cell":[-999,-999],"map_id":42})
  check(reply.ok,"real map %s landing" % mode)
  if reply.ok:
   check(b.automation.position_map==int(reply.target.map_id) and b.automation.position_cell==Vector2i(reply.target.cell[0],reply.target.cell[1]),"server owns returned position")
   var world=WorldCatalog.new()
   var data:Dictionary=MapFile.load_map(world.file(int(reply.target.map_id)))
   var cell:Vector2i=b.automation.position_cell
   check(int(data.blocked[cell.y*int(data.width)+cell.x])==0 and int(data.ground[cell.y*int(data.width)+cell.x])!=0 and not world.links(int(reply.target.map_id)).has(cell),"landing has ground, no collision or portal")
   check(not b.quest_helper.safe(data,Vector2i(-1,-1),{},{}),"out of bounds is unsafe")
   check(not b.quest_helper.safe(data,cell,{cell:true},{}),"occupied cell is unsafe")
 b.free()
func wood() -> void:
 var b=Backend.new()
 b.quest_catalog.enabled_events=[2,18,19]
 b.session._profile.player.level=20
 Rules.set_flag(b.session._profile,"ended",18,true)
 b.session._profile.original_items=[2467]
 check(has_current(quest(b,18),"jaruga/event/20501ev5","REQUEST"),"END18 recommendation continues into permit stage")
 b.session._profile.original_items=[2478]
 check(quest(b,18).steps.any(func(step):return step.id=="wood:harvest" and step.current),"permit explicitly retains harvest prompt")
 for amount in [0,12,14]:
  b.session._profile.original_items=[2478]
  for i in range(amount):b.session._profile.original_items.append(2468)
  check(quest(b,18).steps.any(func(step):return step.id=="wood:exchange" and step.source.type=="ACCEPT" and step.source.condition==b.original_quests.branch_for(b.original_quests.npc_by_id("jaruga/event/20501ev5"),b.session.snapshot()).condition),"actual ordered wood payout branch %d" % amount)
 b.session._profile.original_items=[2467,2468]
 check(has_current(quest(b,18),"jaruga/event/20501ev5","MESSAGE") and not has_current(quest(b,18),"jaruga/event/20501ev5","REQUEST"),"wood without permit refusal precedes recommendation")
 Rules.set_flag(b.session._profile,"ended",19,true)
 b.session._profile.original_items=[2465]
 check(not has_current(quest(b,18),"jaruga/event/20501ev1","CLEAN"),"axe masks original CLEAN19")
 b.session._profile.original_items=[2484]
 check(not has_current(quest(b,18),"jaruga/event/20501ev1","CLEAN"),"broken axe masks CLEAN19")
 check(quest(b,18).steps.any(func(step):return step.id=="wood:optional_axe" and step.get("optional",false) and not step.current),"effective optional axe branch is separate from main progress")
 b.free()

func harvest_visit() -> void:
 var b=Backend.new()
 b.session._profile.original_items=[2478]
 var row:Dictionary=quest(b,18)
 check(row.steps.size()<=10,"wood tiers collapse to canonical route")
 var harvest:Dictionary=b.quest_helper.resolve_step(b,22,"wood:harvest")
 check(not harvest.is_empty() and int(harvest.source.area_id)==88 and int(harvest.map_id)==200,"harvest sourced from imported original area88")
 for mode in ["near","arrival"]:
  var reply:Dictionary=b.handle({"type":"quest_visit","quest_id":22,"step_id":"wood:harvest","mode":mode,"map_id":999,"cell":[-2,-3]})
  check(reply.ok,"harvest step RPC %s" % mode)
  if reply.ok:
   check(b.automation.position_map==int(reply.target.map_id) and b.automation.position_cell==Vector2i(int(reply.target.cell[0]),int(reply.target.cell[1])),"harvest RPC owns final position")
   if mode=="near":
    var rect:Array=harvest.source.area_rect
    check(b.automation.position_cell.x>=int(rect[0]) and b.automation.position_cell.x<=int(rect[2]) and b.automation.position_cell.y>=int(rect[1]) and b.automation.position_cell.y<=int(rect[3]),"harvest near landing remains in source encounter area")
 var before:Vector2i=b.automation.position_cell
 check(not b.handle({"type":"quest_visit","quest_id":22,"step_id":"forged"}).ok and b.automation.position_cell==before,"forged step cannot move server")
 check(not b.handle({"type":"quest_visit","quest_id":"invalid","step_id":"wood:harvest"}).ok,"invalid quest id rejected")
 for step in row.steps:
  if step.source.has("branch_data"):check(step.source.branch_data.enabled,"helper never publishes disabled branch")
 b.free()

func remote() -> void:
 var b=Backend.new()
 root.add_child(b)
 var server=WsServer.new(b,0,"127.0.0.1")
 root.add_child(server)
 check(server.start()==OK,"real quest helper WebSocket listens on port0")
 var link=WsLink.new("ws://127.0.0.1:%d" % server.port)
 var state=ClientState.new()
 link.message.connect(state.apply)
 var polling:Callable=func():link.poll(0.016)
 process_frame.connect(polling)
 link.connect_now()
 check(await Wait.until(self,func():return link.online and state.derived.has("quest_helper")),"remote initial snapshot contains server quest model")
 check(link.backend==null,"remote reader has no backend authority")
 var replies:Array=[]
 link.request({"type":"quest_visit","quest_id":11,"step_id":"shell:request","mode":"near"},func(reply):replies.append(reply))
 check(await Wait.until(self,func():return not replies.is_empty()),"quest step visit works over real remote RPC")
 check(not replies.is_empty() and replies[0].ok,"remote visit accepted")
 Rules.set_flag(b.session._profile,"ended",2,true)
 b.session._profile.original_items=[2414]
 b.publish()
 check(await Wait.until(self,func():return state.derived.quest_helper.quests.any(func(row):return int(row.event)==2 and row.status=="已完成")),"publish updates remote completed quest while preserving row")
 link.close()
 process_frame.disconnect(polling)
 server.stop()
 server.free()
 b.free()
