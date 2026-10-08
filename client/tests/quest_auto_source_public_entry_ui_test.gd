extends "res://tests/quest_auto_source_remote_ui_test.gd"
## Public admission only, not another natural route. Independent public811
## fixtures; completed END44 is a denial fixture, not terminal-route proof.
const PublicPolicy=preload("res://scripts/quest_auto_policy.gd")
class PublicBackend extends "res://server/backend.gd":
 var reports:Array=[]
 var packets:Array=[]
 var checkpoints:Array=[]
 var starts:Array=[]
 func handle(command:Dictionary)->Dictionary:
  var reply:Dictionary=super.handle(command)
  var row:Dictionary={"command":command.duplicate(true),"reply":reply.duplicate(true)}
  if command.get("type")=="quest_auto_start":starts.append(row)
  if command.get("type")=="report_position":reports.append(row)
  if command.get("type")=="checkpoint":checkpoints.append(row)
  return reply
var ui_stage:="setup"
var previous_ui_trace:=""
func ui_trace(label:String,detail:Dictionary={}) -> void:
 if not is_instance_valid(world) or not is_instance_valid(backend_node):return
 var menu=world.quest_helper_menu
 if not is_instance_valid(menu):return
 var auto:Dictionary=world.state.derived.get("quest_auto",{})
 var stop=menu.find_child("QuestAutoStop",true,false)
 print("PUBLIC UI TRACE ",JSON.stringify({"t":Time.get_ticks_msec(),"frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"stage":ui_stage,"label":label,"detail":detail,"menu_key":menu.refresh_key(),"menu_last":menu.last_model,"viewport":str(menu.viewport_size),"stop_id":stop.get_instance_id() if is_instance_valid(stop) else 0,"client_phase":auto.get("phase",""),"client_identity":{"run_id":auto.get("run_id",""),"step_id":auto.get("step_id",""),"revision":auto.get("revision",-1)},"source_entry":auto.get("source_entry",{}),"server_phase":backend_node.quest_auto.phase,"server_identity":backend_node.quest_auto.identity.checkpoint()}))
func _process(_delta:float)->bool:
 if not is_instance_valid(world) or not is_instance_valid(backend_node):return false
 var menu=world.quest_helper_menu
 if not is_instance_valid(menu):return false
 var stop=menu.find_child("QuestAutoStop",true,false)
 var value:String=JSON.stringify([ui_stage,menu.last_model,menu.refresh_key(),menu.viewport_size,stop.get_instance_id() if is_instance_valid(stop) else 0])
 if value!=previous_ui_trace:previous_ui_trace=value;ui_trace("frame state changed")
 return false
func observed_click(name:String)->bool:
 ui_stage+="/"+name
 var button=world.quest_helper_menu.find_child(name,true,false)
 ui_trace("click captured",{"name":name,"node_id":button.get_instance_id() if is_instance_valid(button) else 0})
 var ok:bool=await click(button)
 ui_trace("click returned",{"name":name,"ok":ok,"captured_valid":is_instance_valid(button)})
 return ok
func stop_model_current()->bool:
 var auto:Dictionary=world.state.derived.get("quest_auto",{})
 var identity:Dictionary=backend_node.quest_auto.identity.checkpoint()
 for field in ["run_id","step_id","revision"]:
  if auto.get(field)!=identity[field]:return false
 var menu=world.quest_helper_menu
 var button=menu.find_child("QuestAutoStop",true,false)
 return auto.get("phase")==backend_node.quest_auto.phase and menu.last_model==menu.refresh_key() and is_instance_valid(button) and not button.disabled
func run()->void:
 first_floor_trace=false;remote_mode=true
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844)
 if not check(PublicPolicy.supports(2,44) and not PublicPolicy.supports(2,43) and not PublicPolicy.supports(35,44),"Production policy opens exactly job2/event44"):return
 for kind in ["eligible","ticket_missing","underlevel","completed"]:
  if not await public_case(kind):return
 print("QUEST AUTO SOURCE PUBLIC ENTRY UI: PASS")
 quit(0)
func public_case(kind:String)->bool:
 ui_stage=kind
 backend_node=PublicBackend.new();backend_node.set_process(false)
 var profile:Dictionary=backend_node.session._profile
 profile.player.level=29 if kind=="underlevel" else 35
 preload("res://server/progression.gd").refresh(profile.player);profile.player.hp=profile.player.max_hp
 # No walking encounter is needed for public start -> first gate. This is
 # explicitly a short admission fixture, not natural RNG/route evidence.
 profile.no_random_encounters=true
 if kind!="ticket_missing":Equipment.add(profile,2755)
 Equipment.add(profile,2752)
 if kind=="completed":Rules.set_flag(profile,"ended",44,true)
 backend_node.automation.position_changed(811,Vector2i(30,22),true)
 backend_node.save_path="user://source-public-entry-%s.json"%kind
 if not check(backend_node.save(),kind+": valid public baseline saved"):return false
 backend_node.event.connect(func(event:Dictionary):
  if event.get("type")=="position" and event.has("quest_position_seq"):backend_node.packets.append(event.duplicate(true))
  if event.get("type") in ["position","profile","auto_status"]:ui_trace("final backend event",{"type":event.type}))
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,kind+": real server port0"):return false
 if not await create_world():return false
 world.link.message.connect(func(event:Dictionary):
  if event.get("type") in ["position","profile","auto_status"]:ui_trace("WS after production consumer",{"type":event.type}))
 if not check(await Wait.settle(self,world) and world.backend==null,kind+": actual remote scene has no backend"):return false
 if kind=="eligible":
  var settings:Dictionary=await rpc(world.link,{"type":"set_automation_settings","settings":{"quest":{"mode":"B","loot_minutes":30}}})
  if not check(settings.get("ok",false) and await Wait.settle(self,world),"Real global B preference saved before source admission"):return false
 var menu=world.quest_helper_menu
 menu.open_menu();menu.select_quest(2)
 if not await ready(func():return is_instance_valid(menu.find_child("QuestAutoStart_2",true,false)),kind+": real public job2 start control exists"):return false
 var entry:Dictionary=world.state.derived.get("quest_auto",{}).get("source_entry",{})
 var action=menu.find_child("QuestAutoStart_2",true,false)
 if not check(entry.get("job_id")==2 and entry.get("enabled",false) and entry.get("effective_mode")=="A",kind+": source admission is authority projection"):return false
 if not check(action.disabled==(not entry.get("can_start",false)) and action.text=="自动推进",kind+": button consumes projected eligibility and original-route label"):return false
 var details=menu.find_child("QuestAutoSourceDetails",true,false)
 if not check(is_instance_valid(details) and details.text.contains("唯一 Lv1") and details.text.contains("不保证获胜") and details.text.contains("此金布伊任务路径不会自动送往大厅、购票或刷物。"),kind+": source-specific reward/random/loot boundaries shown"):return false
 if kind=="eligible":
  if not check(entry.can_start and not action.disabled,"Qualified public source start enabled"):return false
  if not await observed_click("QuestAutoSettingsOpen"):return false
  if not await ready(func():return is_instance_valid(menu.settings_panel) and menu.settings_panel.is_visible_in_tree(),"Actual settings panel visible"):return false
  if not check(menu.settings_panel.mode.selected==1 and menu.settings_panel.feedback.text.contains("金布伊任务实际执行 A") and menu.settings_panel.feedback.text.contains("其他支持任务"),"Saved B preference and job-specific A are both explicit"):return false
  if not await observed_click("QuestAutoSettingsBack"):return false
  action=menu.find_child("QuestAutoStart_2",true,false)
  if not await observed_click("QuestAutoStart_2"):return false
  if not await ready(func():return backend_node.quest_auto.running and not backend_node.starts.is_empty(),"Real button/asset-ready path sends actual public WS start"):return false
  if not check(await Wait.settle(self,world),"Public start ACK settles before further action"):return false
  var request:Dictionary=backend_node.starts[-1]
  if not check(request.reply.get("ok",false) and int(request.command.quest_id)==2 and request.command.client==world._client_id and backend_node.quest_auto.quest_id==2,"Public quest_auto_start ACK starts exactly selected job"):return false
  var auto:Dictionary=world.state.derived.quest_auto
  if not check(auto.effective_mode=="A" and auto.settings.mode=="B" and auto.available_modes==["A"],"Running source remains A without erasing B preference"):return false
  menu.close_menu()
  if not await drive_to(func():return backend_node.automation.position_map==800 and backend_node.quest_auto.phase=="travel" and shown(),"Public-start original gate reaches production scene ACK"):return false
  if not check(not backend_node.packets.is_empty() and has_ack(backend_node.packets[-1]),"Gate confirmation uses complete actual receipt"):return false
  ui_stage="eligible/after-complete-gate-ACK"
  ui_trace("before landing publication roundtrip")
  if not check(await Wait.settle(self,world),"Landing ACK publication roundtrip settles before Stop capture"):return false
  menu.open_menu()
  if not await ready(stop_model_current,"Client complete identity/phase and current menu projection agree before Stop"):return false
  ui_trace("current Stop projection ready")
  if not await observed_click("QuestAutoStop"):return false
  if not check(await Wait.settle(self,world) and not backend_node.quest_auto.running,"Existing stop UI stops publicly admitted source run"):return false
 else:
  var reason=menu.find_child("QuestAutoSourceReason",true,false)
  if not check(not entry.can_start and is_instance_valid(reason) and reason.text==str(entry.reason) and not reason.text.is_empty(),kind+": UI shows exact authority refusal reason"):return false
  var before:Dictionary=backend_node.session.snapshot()
  var disk:String=FileAccess.get_file_as_string(backend_node.save_path)
  var identity:Dictionary=backend_node.quest_auto.identity.checkpoint()
  var cell:Vector2i=backend_node.automation.position_cell
  var reply:Dictionary=await rpc(world.link,{"type":"quest_auto_start","quest_id":2,"client":world._client_id})
  if not check(not reply.get("ok",true) and not str(reply.get("reason","")).is_empty() and await Wait.settle(self,world),kind+": actual WS still rejects despite bypassing disabled control"):return false
  if not check(backend_node.session.snapshot()==before and FileAccess.get_file_as_string(backend_node.save_path)==disk and backend_node.automation.position_cell==cell and backend_node.quest_auto.identity.checkpoint()==identity and backend_node.quest_auto.issued.is_empty() and not backend_node.quest_auto.running,kind+": refusal preserves complete profile/disk/position/identity, no reward or receipt"):return false
 world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return not is_instance_valid(world),kind+": remote scene disposed"):return false
 server_node.stop();server_node.queue_free();backend_node.queue_free()
 return true
