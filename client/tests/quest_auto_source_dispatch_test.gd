extends SceneTree
const Motion=preload("res://server/quest_auto_motion.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Encounters=preload("res://server/encounter_catalog.gd")
const Sources=preload("res://server/quest_auto_golden_bui_sources.gd")
const Wait=preload("res://tests/support/wait.gd")
class Backend extends "res://server/backend.gd":
 var cells:Array=[]
 var encode_source:=false
 func _cmd_field_step(command:Dictionary)->Dictionary:
  cells.append({"map_id":automation.position_map,"cell":[automation.position_cell.x,automation.position_cell.y]})
  return super._cmd_field_step(command)
 func _emit(message:Dictionary)->void:
  if encode_source and message.get("type")=="position" and message.get("client","")=="":
   # JSON source numbers are floats; actual WS codec normalizes finite ints.
   message=JSON.parse_string(JSON.stringify(message))
  super._emit(message)
var failures:=0
var assertions:=0
var link
func check(value:bool,label:String)->void:
 assertions+=1
 if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func fresh():
 var b=Backend.new();b.set_process(false)
 b.session._profile.player.level=35
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 b.session._profile.no_random_encounters=false
 Equipment.add(b.session._profile,2755)
 for index in range(7):Equipment.add(b.session._profile,2752)
 b.automation.position_changed(811,Vector2i(30,22),true)
 return b
func ack(b)->Dictionary:
 if b.quest_auto.issued.is_empty():return {}
 var p:Dictionary=b.quest_auto.issued[-1]
 var result:Dictionary={"type":"report_position","map_id":p.map_id,"cell":p.cell.duplicate(),"quest_position_seq":p.seq,"client":b.quest_auto.client,"_quest_connection":b.quest_auto.connection}
 for field in Motion.IDENTITY_FIELDS:result[field]=p[field]
 return result
func tick(b)->void:b._process(0.21)
func reach(b,predicate:Callable,limit:int=160)->bool:
 for index in range(limit):
  if predicate.call():return true
  if not b.quest_auto.running:return false
  if b.quest_auto.phase=="landing":b.handle(ack(b))
  tick(b)
 return predicate.call()
func run()->void:
 if "--numeric-only" in OS.get_cmdline_user_args():
  await numeric_ws();quit(1 if failures else 0);return
 var b=fresh();b.save_path="user://source-dispatch.json";check(b.save(),"Real baseline save")
 check(not b.handle({"type":"quest_auto_start","quest_id":2,"client":"dispatch","_quest_connection":17}).ok,"Public job2 still closed")
 check(b.quest_auto.begin_source_run(b,"dispatch",17).ok,"Narrow internal admission uses actual pure plan")
 var events:Array=[];b.event.connect(func(m):
  if m.get("type")=="position":events.append(m.duplicate(true))
 )
 check(reach(b,func():return b.automation.position_map==800 and b.quest_auto.phase=="landing"),"Actual source entry Warp: "+b.quest_auto.message)
 check(b.quest_arrival.has_arrival(b,800,Vector2i(14,26)),"Proof comes from original saved gate")
 var gate_ack:=ack(b)
 b.handle(gate_ack)
 # Find a deterministic original walking-stream hit on the next cell only;
 # no encounter-table override and no service/opponent RNG access.
 var point:Dictionary=b.quest_auto.navigation.next(b,b.original_quests.npc_by_id("genout/quz_800_29_19@800:29:19"))
 var chosen:=-1
 for seed_value in range(10000):
  var rng=RandomNumberGenerator.new();rng.seed=seed_value
  if Encounters.new(b.encounter_catalog.data).step(800,Vector2i(point.cell[0],point.cell[1]),rng):chosen=seed_value;break
 check(chosen>=0,"Original low-probability field encounter has reproducible seed")
 b.encounter_rng.seed=chosen
 var prior_calls:int=b.cells.size()
 tick(b)
 check(b.quest_auto.phase=="battle" and b.quest_auto.owns_battle and b.automation.compact_active and b.cells.size()==prior_calls+1,"Actual first field hit stops at that cell and starts attack+compact")
 var battle_id:String=b.session._pending.get("battle_id","")
 var saved_serial:int=b.quest_save_serial
 var battle_cell:Vector2i=b.automation.position_cell
 for index in range(200):
  if b.quest_auto.phase!="battle":break
  tick(b)
 check(not battle_id.is_empty() and battle_id in b.session._profile.completed_battles and b.quest_save_serial>saved_serial,"Actual ordinary victory saved before replanning")
 check(b.quest_auto.running and b.quest_auto.phase in ["travel","source_dialogue","battle"],"Post-win source plan remains live")
 # Natural field RNG remains on for the rest of this real first-floor route.
 check(reach(b,func():return b.quest_auto.phase=="source_dialogue" and b.quest_auto.step.get("id")=="golden44:challenge:genout/quz_800_29_19"),"Pure plan walks to real first quiz: "+b.quest_auto.message)
 tick(b) # Confirmation pays once and receives one public question.
 check(not b.quest_auto.source_frame.page.is_empty(),"One page per tick leaves public paid question")
 var paid_items:Array=b.session._profile.original_items.duplicate()
 var old_token:String=b.original_quests.pending.token
 b.quest_auto.detach(b,17)
 var old_identity:Dictionary=b.quest_auto.identity.checkpoint()
 tick(b)
 check(b.session._profile.original_items==paid_items and b.original_quests.pending.token==old_token,"Detach freezes already-paid page without resetting ticket")
 b.handle(gate_ack)
 check(b.quest_auto.detached,"Old gate packet cannot reconnect paid service")
 var pos:Vector2i=b.automation.position_cell
 b.handle({"type":"report_position","map_id":800,"cell":[float(pos.x)+0.25,pos.y],"client":"new","_quest_connection":22})
 check(b.quest_auto.detached,"Fractional reconnect coordinate is not truncated")
 b.handle({"type":"report_position","map_id":800,"cell":[pos.x,pos.y],"client":"new","_quest_connection":22})
 check(not b.quest_auto.detached and b.quest_auto.phase=="landing" and b.quest_auto.identity.revision>int(old_identity.revision),"Authenticated reconnect rotates identity and waits new ACK")
 var rebound:=ack(b)
 b.handle(gate_ack);tick(b)
 check(b.quest_auto.phase=="landing" and b.session._profile.original_items==paid_items,"Old ACK cannot release reconnect or charge again")
 b.quest_auto.detach(b,22)
 b.handle({"type":"report_position","map_id":800,"cell":[pos.x,pos.y],"client":"third","_quest_connection":23})
 b.handle(rebound)
 check(b.quest_auto.phase=="landing" and b.original_quests.pending.token==old_token,"Repeated disconnect before ACK preserves paid page and rejects previous device")
 b.handle(ack(b))
 check(b.quest_auto.phase=="source_dialogue" and b.original_quests.pending.token==old_token,"New full ACK resumes exactly the same legal page")
 tick(b)
 check(b.quest_auto.phase=="landing" and b.automation.position_cell==Vector2i(29,15),"Public resolver commits actual same-map quiz Warp")
 var same_map_ack:=ack(b)
 var position:Vector2i=b.automation.position_cell
 tick(b)
 check(b.automation.position_cell==position and b.quest_auto.phase=="landing","Same-map Warp blocks stairs before full ACK")
 b.handle(same_map_ack)
 check(reach(b,func():return b.automation.position_map==801 and b.quest_auto.phase=="landing"),"Frozen selected original portal reaches next floor: "+b.quest_auto.message)
 var row:Dictionary={}
 for candidate in Sources.table().portals:
  if int(candidate.from_map)==800:row=candidate;break
 check(b.automation.position_cell==Vector2i(row.to_cell[0],row.to_cell[1]) and b.quest_arrival.has_arrival(b,801,b.automation.position_cell),"Exact frozen landing and continuous original portal proof")
 check(events.all(func(m):return m.get("quest_segment",{}).get("mode")=="A"),"All protected source moves stay original A")
 var cells:int=b.cells.size();var final_ack:=ack(b)
 b.quest_auto.stop(b,"short boundary done")
 b.handle(final_ack);tick(b)
 check(not b.quest_auto.running and b.cells.size()==cells,"Cancel prevents old receipt and later field tail")
 var disk=JSON.parse_string(FileAccess.get_file_as_string(b.save_path))
 check(battle_id in disk.completed_battles and disk.original_items.any(func(item):return Motion.same_integer(item,2754)),"Actual source reward and ordinary battle survive disk readback")
 check(battle_cell!=Vector2i(-1,-1),"Encounter authority was a real route cell")
 b.free()
 await numeric_ws()
 print("QUEST AUTO SOURCE DISPATCH: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
func rpc(command:Dictionary)->Dictionary:
 var replies:Array=[];link.request(command,func(r):replies.append(r))
 check(await Wait.until(self,func():link.poll(0.01);return not replies.is_empty()),"Real WS roundtrip")
 return {} if replies.is_empty() else replies[0]
func numeric_ws()->void:
 var b=fresh();b.encode_source=true;root.add_child(b)
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"Isolated WS port0")
 link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port);link.connect_now()
 check(await Wait.until(self,func():link.poll(0.01);return link.online),"WS connects")
 await rpc({"type":"ping"})
 print("WS admission peer=",server.clients()[0].get_instance_id()," running=",b.quest_auto.running," battle=",b.battle_open," pending=",b.session._pending.size()," dialogue=",b.original_quests.pending.size()," auto=",b.automation.running," hunt=",b.automation.hunt_running," flow=",b.automation.flow_active())
 var started:Dictionary=b.quest_auto.begin_source_run(b,"numeric-source",server.clients()[0].get_instance_id())
 check(started.ok,"Server-only dispatch under actual socket identity: "+str(started)+" at "+str(b.automation.position_map)+"/"+str(b.automation.position_cell))
 check(reach(b,func():return b.quest_auto.phase=="landing"),"Float encoded original Warp is captured")
 var a:=ack(b);a.erase("_quest_connection")
 check(not a.is_empty() and b.quest_auto.issued[-1].cell==[14,26],"Finite integer floats produce normalized receipt")
 for value in [true,NAN,INF,14.25]:
  check(Motion.cell([value,26]).is_empty(),"Invalid scalar never matches source Warp")
 var bad:Dictionary=a.duplicate(true);bad.cell=[14.25,26]
 await rpc(bad)
 check(b.quest_auto.phase=="landing","Real WS fractional ACK refused")
 await rpc(a)
 check(b.quest_auto.phase=="travel","Real WS integer ACK matches original float source position")
 check(reach(b,func():return b.quest_auto.phase=="source_dialogue"),"Real socket session reaches first original quiz")
 tick(b)
 var token:String=str(b.original_quests.pending.get("token",""))
 var items:Array=b.session._profile.original_items.duplicate()
 var old_ack:Dictionary=a.duplicate(true)
 link.close()
 check(await Wait.until(self,func():link.poll(0.01);return server.clients().is_empty() and b.quest_auto.detached),"Transport close actually detaches source run")
 link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port);link.connect_now()
 check(await Wait.until(self,func():link.poll(0.01);return link.online),"Second real socket connects")
 await rpc(old_ack)
 check(b.quest_auto.detached,"Old socket receipt cannot rebind new transport")
 var pos:Vector2i=b.automation.position_cell
 await rpc({"type":"report_position","map_id":800,"cell":[pos.x,pos.y],"client":"numeric-return"})
 check(not b.quest_auto.detached and b.quest_auto.phase=="landing" and b.quest_auto.source_frame.connection==server.clients()[0].get_instance_id(),"Paid frame rebinds actual signed transport ID")
 a=ack(b);a.erase("_quest_connection");await rpc(a)
 check(b.quest_auto.phase=="source_dialogue" and b.original_quests.pending.token==token and b.session._profile.original_items==items,"Real WS full ACK resumes paid original page without repeat debit")
 tick(b)
 check(b.quest_auto.phase=="landing" and b.automation.position_cell==Vector2i(29,15),"Reconnected socket owns actual same-map source Warp")
 link.close();server.stop();server.queue_free();b.queue_free();await process_frame
