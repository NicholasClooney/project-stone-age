extends "res://tests/quest_delivery_remote_ui_test.gd"
## Original public gate and real encounter/battle; only the walking stream is
## chosen to hit the first cell. No source/battle RNG selection or fake win.
const Equipment=preload("res://server/original_equipment.gd")
const Motion=preload("res://server/quest_auto_motion.gd")
const Encounters=preload("res://server/encounter_catalog.gd")
class ControlledBackend extends "res://server/backend.gd":
 var trace_ticks:=false
 var manual:=false
 var manual_ticks:=0
 var unexpected_ticks:=0
 var events:Array=[]
 func _process(delta:float)->void:
  if trace_ticks:
   if manual:manual_ticks+=1
   else:unexpected_ticks+=1
  super._process(delta)
var serial:=0
func fresh():
 serial+=1
 var b=ControlledBackend.new();b.set_process(false)
 b.session._profile.player.level=35
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 b.session._profile.no_random_encounters=false
 Equipment.add(b.session._profile,2755);Equipment.add(b.session._profile,2752)
 b.automation.position_changed(811,Vector2i(30,22),true)
 b.save_path="user://source-battle-order-%d.json"%serial
 b.event.connect(func(m):b.events.append(m.duplicate(true)))
 return b
func drive(b)->void:
 b.manual=true;b._process(0.21);b.manual=false
func ack(b)->Dictionary:
 var p:Dictionary=b.quest_auto.issued[-1]
 var c:Dictionary={"type":"report_position","map_id":p.map_id,"cell":p.cell.duplicate(),"quest_position_seq":p.seq,"client":b.quest_auto.client,"_quest_connection":b.quest_auto.connection}
 for field in Motion.IDENTITY_FIELDS:c[field]=p[field]
 return c
func walking_hit(b)->bool:
 var npc:Dictionary=b.original_quests.npc_by_id("genout/quz_800_29_19@800:29:19")
 var point:Dictionary=b.quest_auto.navigation.next(b,npc)
 if not check(not point.is_empty(),"Actual original first approach step"):return false
 for candidate in range(10000):
  var rng=RandomNumberGenerator.new();rng.seed=candidate
  if Encounters.new(b.encounter_catalog.data).step(800,Vector2i(point.cell[0],point.cell[1]),rng):
   b.encounter_rng.seed=candidate
   return true
 return check(false,"Original walking stream first-cell encounter exists")
func local_entry(b)->bool:
 if not check(b.save() and b.quest_auto.begin_source_run(b,"local",71).ok,"Local boundary actual public gate admission"):return false
 drive(b);drive(b)
 if not check(b.quest_auto.phase=="landing" and b.quest_arrival.has_arrival(b,800,b.automation.position_cell),"Original committed gate grants actual proof"):return false
 b.handle(ack(b))
 return walking_hit(b)
func settle_only(b)->bool:
 for index in range(200):
  if not b.automation.running:break
  b.automation.tick(0.21)
 return check(not b.battle_open and b.session._pending.is_empty() and b.battle_state.get("outcome")=="win" and b.quest_auto.phase=="battle","Actual compact win closed and saved before runner continuation")
func boundaries()->bool:
 var b=fresh()
 if not local_entry(b):return false
 var fired:Array=[]
 b.event.connect(func(m):
  if fired.is_empty() and m.get("type")=="auto_status" and b.quest_auto.phase=="battle":
   fired.append(m.status.duplicate(true));b.quest_auto.stop(b,"entry publication observer cancellation")
 )
 drive(b)
 if not check(fired.size()==1 and not fired[0].running and not b.quest_auto.running and not b.automation.running and b.battle_open,"Entry status states real unstarted runner; reentrant cancel prevents starting it but preserves opened battle"):return false
 var position:Vector2i=b.automation.position_cell
 drive(b)
 if not check(b.automation.position_cell==position and b.quest_auto.issued.is_empty(),"Entry cancellation cannot emit continuation"):return false
 b.free()
 for savefail in [false,true]:
  b=fresh()
  if not local_entry(b):return false
  drive(b)
  if not check(b.quest_auto.phase=="battle" and b.automation.running,"Actual boundary encounter starts compact runner"):return false
  var battle_id:String=b.session._pending.battle_id
  if not settle_only(b):return false
  var before:Dictionary=b.session.snapshot()
  position=b.automation.position_cell
  var disk:String=FileAccess.get_file_as_string(b.save_path)
  if not check(battle_id in JSON.parse_string(disk).completed_battles,"Completed original battle already persisted"):return false
  var signals:Array=[]
  var blocked:String=ProjectSettings.globalize_path(b.save_path+".tmp")
  if savefail:
   # The real continuation candidate equals the last save; invalidate only
   # the optimization cache so the unchanged candidate reaches the real writer.
   b.last_saved_payload=""
   if not check(DirAccess.make_dir_absolute(blocked)==OK,"Real tmp directory blocks continuation save"):return false
  b.event.connect(func(m):
   if m.get("type")=="profile" and m.derived.quest_auto.phase=="travel":
    signals.append(m.duplicate(true))
    b.quest_auto.stop(b,"travel publication observer cancellation")
  )
  b.quest_auto.tick(b,0.21) # Depth zero exposes immediate observer reentry.
  if savefail:
   if not check(signals.is_empty() and b.quest_auto.phase=="manual" and b.quest_auto.pause_reason=="沿途战斗保存失败，停止自动任务。","Save failure cannot publish resumable travel"):return false
   if not check(DirAccess.remove_absolute(blocked)==OK,"Remove only owned tmp blocker"):return false
  else:
   if not check(signals.size()==1 and not b.quest_auto.running,"Post-save travel observer cancellation occurs exactly once"):return false
  if not check(b.session.snapshot()==before and FileAccess.get_file_as_string(b.save_path)==disk and b.automation.position_cell==position and b.quest_auto.issued.is_empty(),"Cancelled/failed continuation preserves saved battle/profile/position with no next receipt"):return false
  b.quest_auto.tick(b,0.21)
  if not check(b.automation.position_cell==position and not b.quest_auto.running,"Later tick cannot restart cancelled/failed battle continuation"):return false
  b.free()
 return true
func shown()->bool:
 return int(world.data.get("map_id",-1))==backend_node.automation.position_map and world.cell==backend_node.automation.position_cell and not world.moving and not world.area_transition_busy
func run()->void:
 if not boundaries():return
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
 backend_node=fresh()
 if not check(backend_node.save(),"Remote strong35/base50000 original baseline saved"):return
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,"Battle order actual WS port0"):return
 if not await create_world():return
 backend_node.set_process(false);backend_node.trace_ticks=true
 if not check(not backend_node.is_processing() and backend_node.unexpected_ticks==0,"Backend frozen after actual ready"):return
 if not await ready(shown,"Public scene agrees before internal source admission"):return
 if not check(backend_node.quest_auto.begin_source_run(backend_node,world._client_id,server_node.clients()[0].get_instance_id()).ok,"Internal source admission uses real transport"):return
 drive(backend_node);drive(backend_node)
 if not await ready(func():return backend_node.quest_auto.phase=="travel" and shown(),"Actual original gate acknowledged by production scene"):return
 if not walking_hit(backend_node):return
 var client_rows:Array=[]
 world.link.message.connect(func(m):
  if m.get("type") in ["profile","position","auto_status"]:
   client_rows.append({"type":m.type,"event":m.duplicate(true),"phase":world.state.derived.get("quest_auto",{}).get("phase",""),"position":world.state.automation.get("position",{}).duplicate(true),"follow":world._follow.duplicate(),"receipt":world.get_meta("quest_position_receipt",{}).duplicate(true)})
 )
 drive(backend_node)
 var battle_cell:Vector2i=backend_node.automation.position_cell
 var battle_id:String=backend_node.session._pending.battle_id
 if not check(backend_node.quest_auto.phase=="battle" and await Wait.settle(self,world),"Real encounter and battle start messages settle"):return
 var battle_profiles:int=0
 for row in client_rows:
  if row.type=="profile" and row.phase=="battle":
   battle_profiles+=1
   if not check(row.position.cell==[battle_cell.x,battle_cell.y] and row.follow in [[],[800,battle_cell]],"Every receipt-clearing battle profile uses actual encounter position, never old gate"):return
 if not check(battle_profiles>0,"Observed real battle phase profile"):return
 client_rows.clear()
 for index in range(200):
  if backend_node.quest_auto.phase!="battle":break
  drive(backend_node)
  if not check(await Wait.settle(self,world),"Controlled compact battle tick roundtrip"):return
 if not check(backend_node.quest_auto.phase=="travel" and backend_node.automation.position_cell!=battle_cell,"Winning continuation emitted its first next cell in same controlled tick"):return
 var target:Vector2i=backend_node.automation.position_cell
 var count:int=backend_node.manual_ticks
 if not await ready(shown,"Frozen backend: first post-win packet alone reaches production scene"):return
 if not check(backend_node.manual_ticks==count and backend_node.unexpected_ticks==0 and not backend_node.is_processing(),"No extra or unexpected tick masks first-packet consistency"):return
 var accepted:int=0
 for row in client_rows:
  if row.type=="position" and row.event.cell==[target.x,target.y]:
   accepted+=1
   if not check(row.phase=="travel" and row.receipt.get("quest_position_seq")==row.event.quest_position_seq,"First post-win WS receipt accepted under already-published travel identity"):return
 if not check(accepted==1,"Exactly one post-win destination packet suffices"):return
 var reader=Session.new()
 if not check(reader.load_game(backend_node.save_path) and battle_id in reader.snapshot().completed_battles,"Real winning battle survives independent Session disk readback"):return
 print("BATTLE ORDER controlled manual_ticks=",count," unexpected_ticks=",backend_node.unexpected_ticks," first_next_cell=",target)
 backend_node.quest_auto.stop(backend_node,"regression complete")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return not is_instance_valid(world),"Battle order scene disposed"):return
 server_node.stop();server_node.queue_free();backend_node.queue_free()
 print("QUEST AUTO SOURCE BATTLE ORDER: PASS; entry/travel reentry cancellation; real tmp failure; frozen WS first packet")
 quit(0)
