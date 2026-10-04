extends "res://tests/quest_delivery_loading_ui_test.gd"
## Internal job2 admission is an explicit fixture: no public start UI exists.
## All subsequent map loading, following and receipt ACKs use the real remote
## scene. Natural encounters/source RNG; strong stats are not normal Lv35 power.
const Equipment=preload("res://server/original_equipment.gd")
const RECEIPT_FIELDS=["quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq"]
class RecordingBackend extends "res://server/backend.gd":
 var reports:Array=[]
 var packets:Array=[]
 var checkpoints:Array=[]
 func handle(command:Dictionary)->Dictionary:
  var reply:Dictionary=super.handle(command)
  if command.get("type")=="report_position":
   reports.append({"command":command.duplicate(true),"reply":reply.duplicate(true)})
   print("SOURCE REPORT ",JSON.stringify({"t":Time.get_ticks_msec(),"command":command,"reply":reply,"phase_after":quest_auto.phase,"identity_after":quest_auto.identity.checkpoint()}))
  if command.get("type")=="checkpoint":checkpoints.append({"command":command.duplicate(true),"reply":reply.duplicate(true)})
  return reply
var ticks:=0
var first_floor_trace:=true
var previous_scene_trace:=""
func trace_scene(label:String)->void:
 if not is_instance_valid(world) or not is_instance_valid(backend_node):return
 var data:Dictionary={"map":world.data.get("map_id",-1),"cell":str(world.cell),"moving":world.moving,"transition":world.area_transition_busy,"followed":world._followed,"receipt":world.get_meta("quest_position_receipt",{}),"auto":world.state.derived.get("quest_auto",{}),"source_phase":backend_node.quest_auto.phase,"source_identity":backend_node.quest_auto.identity.checkpoint()}
 var serialized:String=JSON.stringify(data)
 if label!="frame" or serialized!=previous_scene_trace:print("SOURCE SCENE ",label," t=",Time.get_ticks_msec()," ",serialized)
 previous_scene_trace=serialized
func _process(_delta:float)->bool:
 if first_floor_trace:trace_scene("frame")
 return false
func check(value:bool,label:String)->bool:
 if not value and is_instance_valid(backend_node) and is_instance_valid(world):
  print("SOURCE FAILURE ",JSON.stringify({"label":label,"phase":backend_node.quest_auto.phase,"identity":backend_node.quest_auto.identity.checkpoint(),"authority_map":backend_node.automation.position_map,"authority_cell":str(backend_node.automation.position_cell),"scene_map":world.data.get("map_id",-1),"scene_cell":str(world.cell),"moving":world.moving,"transition":world.area_transition_busy,"followed":world._followed,"receipt":world.get_meta("quest_position_receipt",{}),"snapshot_auto":world.state.derived.get("quest_auto",{}),"packets":backend_node.packets,"reports":backend_node.reports,"checkpoints":backend_node.checkpoints}))
 return super.check(value,label)
func has_ack(packet:Dictionary)->bool:
 for entry in backend_node.reports:
  var command:Dictionary=entry.command
  if not entry.reply.get("ok",false):continue
  var same:bool=command.get("map_id")==packet.map_id and command.get("cell")==packet.cell
  for field in RECEIPT_FIELDS:
   if command.get(field)!=packet.get(field):same=false
  if same:return true
 return false
func shown()->bool:
 return int(world.data.get("map_id",-1))==backend_node.automation.position_map and world.cell==backend_node.automation.position_cell and not world.moving and not world.area_transition_busy
func paid_page()->bool:
 var frame=backend_node.quest_auto.source_frame
 return backend_node.quest_auto.phase=="source_dialogue" and frame!=null and str(frame.page.get("text","")).begins_with("猜谜 第")
func drive_to(predicate:Callable,label:String,hold_landing:bool=false)->bool:
 var deadline:int=Time.get_ticks_msec()+int(Wait.DEADLINE*1000)
 while Time.get_ticks_msec()<deadline:
  if predicate.call():return check(true,label)
  if not backend_node.quest_auto.running:return check(false,label+": "+backend_node.quest_auto.message)
  ticks+=1;backend_node._process(0.21)
  if not await Wait.settle(self,world):return check(false,"Source tick actual WS roundtrip")
  if predicate.call():return check(true,label)
  if backend_node.quest_auto.phase=="landing":
   if hold_landing:return check(false,label+": unexpected earlier landing")
   if not await ready(func():return backend_node.quest_auto.phase!="landing","Production UI confirms source landing"):return false
  elif backend_node.quest_auto.phase!="battle":
   if not await ready(shown,"Production scene shows committed authority before next tick"):return false
 return check(false,label+": original condition deadline")
func fresh_source()->bool:
 backend_node=RecordingBackend.new();backend_node.set_process(false)
 # Source Warp receives its receipt at _deliver_event, after _emit queued it.
 # Observe the final production event, exactly as the WS transport does.
 backend_node.event.connect(func(message:Dictionary):
  if message.get("type")=="position" and message.has("quest_position_seq"):backend_node.packets.append(message.duplicate(true))
  if first_floor_trace and message.get("type") in ["position","profile","snapshot"]:
   print("SOURCE EVENT ",JSON.stringify({"t":Time.get_ticks_msec(),"type":message.get("type"),"packet":message if message.get("type")=="position" else {},"auto":message.get("derived",{}).get("quest_auto",{}),"live_identity":backend_node.quest_auto.identity.checkpoint(),"live_phase":backend_node.quest_auto.phase})))
 var profile:Dictionary=backend_node.session._profile
 profile.player.level=35
 profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(profile.player)
 profile.player.hp=profile.player.max_hp
 for key in profile.inventory:profile.inventory[key]=0
 profile.no_random_encounters=false
 Equipment.add(profile,2755)
 for index in range(7):Equipment.add(profile,2752)
 backend_node.automation.position_changed(811,Vector2i(30,22),true)
 backend_node.save_path="user://quest-source-remote-short.json"
 if not check(backend_node.save(),"Real source baseline persisted"):return false
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,"Source UI server port0"):return false
 if not await create_world():return false
 world.link.message.connect(func(message:Dictionary):
  if first_floor_trace and message.get("type") in ["position","profile","snapshot"]:
   print("SOURCE WS ",JSON.stringify({"t":Time.get_ticks_msec(),"type":message.get("type"),"packet":message if message.get("type")=="position" else {},"auto":message.get("derived",{}).get("quest_auto",{})}))
   trace_scene("after-client-consume"))
 if not await ready(shown,"Remote scene restores actual public811 entrance"):return false
 if not check(await Wait.settle(self,world),"Public initial position settles"):return false
 if not check(not (await rpc(world.link,{"type":"quest_auto_start","quest_id":2,"client":world._client_id})).get("ok",false),"Job2 public entry remains closed"):return false
 if not check(server_node.clients().size()==1,"One real authenticated owner transport"):return false
 var peer:int=server_node.clients()[0].get_instance_id()
 if not check(backend_node.quest_auto.begin_source_run(backend_node,world._client_id,peer).get("ok",false),"Explicit internal fixture admits source plan using actual socket identity"):return false
 return check(await Wait.settle(self,world) and world.backend==null,"Production remote snapshot sees internal run without a backend reference")
func run()->void:
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
 print("SOURCE REMOTE INPUT: Lv35/base_stats50000, 2755x1/2752x7, natural RNG, public811(30,22), internal begin_source_run only")
 if not await fresh_source():return
 var original_packs=world.asset_packs
 var cold:=ColdMapPacks.new();root.add_child(cold);world.asset_packs=cold
 if not await drive_to(func():return backend_node.automation.position_map==800 and backend_node.quest_auto.phase=="landing","Original paid gate reaches first-floor landing",true):return
 if not check(not backend_node.packets.is_empty(),"Source gate emits a final receipt packet"):return
 var gate:Dictionary=backend_node.packets[-1].duplicate(true)
 if not await ready(func():return cold.waiting.is_valid(),"First-floor cold map readiness requested by real scene"):return
 if not check(not has_ack(gate) and int(world.data.map_id)==811,"Unready first floor cannot acknowledge landing"):return
 trace_scene("before-cold-finish")
 cold.finish(true)
 trace_scene("after-cold-finish")
 if not await ready(func():return shown() and backend_node.quest_auto.phase=="travel","Actual first-floor ready releases full receipt"):return
 first_floor_trace=false
 if not check(has_ack(gate),"Gate ACK retains all five frozen event fields"):return
 world.asset_packs=original_packs
 if not await drive_to(paid_page,"Actual first quiz confirmation paid once and exposes public question"):return
 var paid_items:Array=backend_node.session._profile.original_items.duplicate()
 var paid_token:String=str(backend_node.original_quests.pending.token)
 var revision:int=backend_node.quest_auto.identity.revision
 if not check(not backend_node.packets.is_empty(),"Paid page retains an observed receipt history"):return
 var prior_packet:Dictionary=backend_node.packets[-1].duplicate(true)
 world.link.close()
 if not await ready(func():return backend_node.quest_auto.detached and not world.link.online,"Actual paid-page socket close detaches owner"):return
 backend_node._process(0.21)
 if not check(backend_node.session._profile.original_items==paid_items and str(backend_node.original_quests.pending.token)==paid_token,"Disconnected paid page stays paid without repeated confirmation"):return
 if not check(world.get_meta("quest_position_receipt",{}).is_empty(),"Disconnect clears prior UI receipt"):return
 world.link.connect_now()
 if not await ready(func():return world.link.online and not backend_node.quest_auto.detached and backend_node.quest_auto.phase=="source_dialogue","Production reconnect handshakes and ACKs new receipt before resuming paid page"):return
 if not check(await Wait.settle(self,world),"Paid-page reconnect roundtrip settles"):return
 if not check(not backend_node.packets.is_empty(),"Reconnect emits a final receipt packet"):return
 var rebound:Dictionary=backend_node.packets[-1].duplicate(true)
 if not check(has_ack(rebound) and backend_node.quest_auto.identity.revision>revision and rebound.quest_position_seq!=prior_packet.quest_position_seq,"New transport confirms only fresh complete receipt"):return
 if not check(backend_node.session._profile.original_items==paid_items and str(backend_node.original_quests.pending.token)==paid_token,"Reconnect does not debit paid page twice"):return
 var warp_index:int=backend_node.packets.size()
 if not await drive_to(func():
  for index in range(warp_index,backend_node.packets.size()):
   var packet:Dictionary=backend_node.packets[index]
   if int(packet.map_id)==800 and bool(packet.get("quest_ack_required",false)):return true
  return false,"Original public quiz resolves to same-map service Warp"):return
 if not check(backend_node.packets.size()>warp_index,"Same-map Warp emits a new final receipt packet"):return
 var warp:Dictionary=backend_node.packets[-1].duplicate(true)
 if not await ready(func():return shown() and backend_node.quest_auto.phase=="travel","Same-map Warp presentation sends full ACK"):return
 if not check(int(warp.map_id)==800 and has_ack(warp),"Same-map service Warp receipt accepted after actual UI follow"):return
 # Hold then complete the actual staircase destination readiness. No fixture
 # positions/proof are introduced inside the protected route.
 cold.available=false;world.asset_packs=cold
 if not await drive_to(func():return backend_node.automation.position_map==801 and backend_node.quest_auto.phase=="landing","Original staircase reaches next floor",true):return
 if not check(not backend_node.packets.is_empty(),"Staircase emits a final receipt packet"):return
 var stairs:Dictionary=backend_node.packets[-1].duplicate(true)
 if not await ready(func():return cold.waiting.is_valid(),"Staircase destination awaits actual map loading"):return
 if not check(not has_ack(stairs) and backend_node.quest_arrival.has_arrival(backend_node,801,backend_node.automation.position_cell),"Original server staircase owns proof; cold UI has not acknowledged"):return
 cold.finish(true)
 if not await ready(func():return shown() and backend_node.quest_auto.phase=="travel","Original staircase destination ready sends its complete ACK"):return
 if not check(has_ack(stairs) and int(world.data.map_id)==801,"Production remote scene confirms real second-floor landing"):return
 world.quest_helper_travel.cancel("source remote test cancellation")
 if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running,"Production client cancellation stops authoritative source run"):return
 var reports_after_stop:int=backend_node.reports.size()
 world._remote._on_backend_message(stairs)
 if not check(await Wait.settle(self,world),"Late cancelled packet roundtrip settles"):return
 if not check(backend_node.reports.size()==reports_after_stop and world.get_meta("quest_position_receipt",{}).is_empty() and not backend_node.quest_auto.running,"Late cancelled receipt cannot send another ACK or revive source run"):return
 world.asset_packs=original_packs;cold.queue_free()
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return not is_instance_valid(world),"Remote source scene disposed"):return
 server_node.stop();server_node.queue_free();backend_node.queue_free()
 print("QUEST AUTO SOURCE REMOTE UI: PASS ticks=",ticks)
 quit(0)
