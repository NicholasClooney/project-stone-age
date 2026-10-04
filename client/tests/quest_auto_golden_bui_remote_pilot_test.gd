extends "res://tests/quest_auto_source_remote_ui_test.gd"
## One scheduled natural Lv35 audit, NOT a routine must-win full-suite test.
## Internal admission only. No seeds, refill, protected placement or fake ACK.
const BUDGET_MS:=300000
const MAX_TICKS:=10000
const SourcePlan=preload("res://server/quest_auto_golden_bui_plan.gd")
# main.tscn contains only this root script. Wrappers retain synchronous super
# calls; no observer sends commands, advances ticks or awaits a condition.
class ObservedGame extends "res://scripts/game.gd":
 var observer:Callable
 func note(label:String,event:Dictionary={}) -> void:
  if observer.is_valid():observer.call(label,event)
 func _on_backend_message(event:Dictionary)->void:
  var watched:bool=event.get("type") in ["position","profile","auto_status","battle_started","battle_turn","battle_closed"]
  if watched:note("WS before consumer",event)
  super._on_backend_message(event)
  if watched:note("WS after consumer",event)
 func checkpoint()->bool:
  note("checkpoint invocation",{"stack":get_stack()})
  var result:bool=super.checkpoint()
  note("checkpoint submitted",{"seq":link._seq,"result":result})
  return result
 func restore_location()->void:
  note("restore_location before",{"stack":get_stack()})
  super.restore_location()
  note("restore_location after")
class PilotBackend extends "res://server/backend.gd":
 var observer:Callable
 func note(label:String,event:Dictionary={}) -> void:
  if observer.is_valid():observer.call(label,event)
 func _process(delta:float)->void:
  note("backend tick before",{"stack":get_stack(),"delta":delta})
  super._process(delta)
  note("backend tick after")
 func call_quest_source(frame,proposal:Dictionary,choice:Dictionary={}) -> Dictionary:
  note("original source before",{"npc_id":proposal.get("npc_id",""),"token":choice.get("token",""),"is_choice":not choice.is_empty(),"stack":get_stack()})
  var reply:Dictionary=super.call_quest_source(frame,proposal,choice)
  note("original source after",{"ok":reply.get("ok",false),"closed":reply.get("closed",false),"source_commit":reply.get("source_commit",{}),"dialogue_token":reply.get("dialogue",{}).get("token","")})
  return reply
 var reports:Array=[]
 var packets:Array=[]
 var checkpoints:Array=[]
 var saves:Array=[]
 var reward_saved:Callable
 var reward_seen:=false
 var previous_successful_disk_payload:=""
 var previous_disk_payload:=""
 var successful_disk_payload:=""
 var current_tick:=0
 var field_steps:=0
 func handle(command:Dictionary)->Dictionary:
  var reply:Dictionary=super.handle(command)
  if command.get("type")=="report_position":reports.append({"command":command.duplicate(true),"reply":reply.duplicate(true)})
  if command.get("type")=="checkpoint":
   var entry:Dictionary={"t":Time.get_ticks_msec(),"tick":current_tick,"command":command.duplicate(true),"reply":reply.duplicate(true),"serial":quest_save_serial}
   checkpoints.append(entry);print("PILOT CHECKPOINT ",JSON.stringify(entry))
  return reply
 func _cmd_field_step(command:Dictionary)->Dictionary:
  field_steps+=1
  return super._cmd_field_step(command)
 func _save_profile_boundary()->bool:
  var previous:String=FileAccess.get_file_as_string(save_path) if not save_path.is_empty() and FileAccess.file_exists(save_path) else ""
  var ok:bool=super._save_profile_boundary()
  if not ok or save_path.is_empty():return ok
  var payload:String=FileAccess.get_file_as_string(save_path)
  var disk=JSON.parse_string(payload)
  if not disk is Dictionary:return ok
  previous_successful_disk_payload=successful_disk_payload
  previous_disk_payload=previous;successful_disk_payload=payload
  var entry:Dictionary={"t":Time.get_ticks_msec(),"tick":current_tick,"serial":quest_save_serial,"location":disk.get("location",{}),"ended44":preload("res://server/original_quests.gd").flag(disk,"ended",44),"items":disk.get("original_items",[]),"battles":disk.get("completed_battles",[]).size()}
  saves.append(entry);print("PILOT SAVED ",JSON.stringify(entry))
  if not reward_seen and entry.ended44:
   reward_seen=true
   if reward_saved.is_valid():reward_saved.call(payload,entry.duplicate(true))
  return ok
var pilot_start:=Time.get_ticks_msec()
var finished:=false
var reward_cut:=false
var reward_payload:=""
var reward_entry:Dictionary={}
var endpoint:Dictionary={}
var layers:Array=[]
var public_results:Array=[]
var stage:="setup"
var audit:Dictionary={}
var checkpoint_answers:Dictionary={}
var original_backend
var saved_pet_id:=""
var entry_disk:Dictionary={}
var award_baseline:Dictionary={}
var frozen_reward:Dictionary={}
var before_reward_payload:=""
var before_reward_backup:=""
var before_reward_successful:=""
func passive_scene_state()->Dictionary:
 if not is_instance_valid(world):return {}
 var value:Dictionary={"map":world.data.get("map_id",-1),"cell":str(world.cell),"display_cell":str(world.display_cell()) if not world.data.is_empty() else "unbuilt","moving":world.moving,"transition":world.area_transition_busy,"follow":world._follow,"followed":world._followed,"following_step":world._following_step,"receipt":world.get_meta("quest_position_receipt",{}),"auto":world.state.derived.get("quest_auto",{}),"automation_position":world.state.automation.get("position",{}),"profile_location":world.state.profile.get("location",{}),"battle_open":world.state.battle_open}
 if is_instance_valid(world.battle_view):value.battle_view=world.battle_view.visible
 return value
func trace_authority()->Dictionary:
 if not is_instance_valid(backend_node):return {}
 var runner=backend_node.quest_auto
 var page:Dictionary=runner.source_frame.page if runner.source_frame!=null else {}
 return {"map":backend_node.automation.position_map,"cell":str(backend_node.automation.position_cell),"phase":runner.phase,"identity":runner.identity.checkpoint(),"motion":runner.motion,"running":runner.running,"detached":runner.detached,"process_enabled":backend_node.is_processing(),"frame_token":page.get("token",""),"frame_npc":page.get("npc_id",""),"pending_token":backend_node.original_quests.pending.get("token",""),"profile_location":backend_node.session._profile.location,"has_membership":2753 in backend_node.session._profile.original_items}
func trace_event(event:Dictionary)->Dictionary:
 # Record public event metadata, never quiz text/options/private answers.
 var value:Dictionary={}
 for key in ["type","map_id","cell","client","quest_run_id","quest_step_id","quest_revision","quest_segment_id","quest_position_seq","quest_ack_required","quest_segment","quest_segment_index","quest_segment_done","outcome","battle_id","seq","result","stack","delta","npc_id","token","is_choice","ok","closed","source_commit","dialogue_token"]:
  if event.has(key):value[key]=event[key]
 if event.has("derived"):value.quest_auto=event.derived.get("quest_auto",{})
 if event.has("profile"):value.profile_location=event.profile.get("location",{})
 if event.has("status"):
  var status:Dictionary=event.status
  value.auto_status={"position":status.get("position",{}),"running":status.get("running",false)}
 return value
func observe_passive(label:String,event:Dictionary={}) -> void:
 var row:Dictionary={"t":Time.get_ticks_msec(),"tick":ticks,"stage":stage,"label":label,"event":trace_event(event),"scene":passive_scene_state(),"authority":trace_authority()}
 if label=="WS before consumer" and event.has("quest_position_seq"):
  row.consumer_identity_gate=world._remote.quest_receipt_current(event,world.state.derived.get("quest_auto",{}))
 print("REMOTE PILOT TRACE ",JSON.stringify(row))
func shown()->bool:
 var result:bool=super.shown()
 if result:observe_passive("shown success")
 return result
func create_world()->bool:
 # Exact inherited creation sequence/waits/freeze; only root type and observer
 # assignment differ so production consumers can be logged before AND after.
 var script=load("res://scripts/game.gd")
 if remote_mode:script.server_url_override="ws://127.0.0.1:%d"%server_node.port
 world=ObservedGame.new();script.server_url_override="";world.name="Samgir"
 world.observer=observe_passive
 world.profile_persistence=false;world.viewer_prefs_path="user://quest-background.cfg"
 root.add_child(world)
 if not await ready(func():return not world.data.is_empty() and (not remote_mode or world.link.online),"Real world ready"):return false
 if not check(await Wait.settle(self,world),"Initial world settles"):return false
 if not remote_mode:backend_node=world.backend
 backend_node.set_process(false)
 return check(not remote_mode or world.backend==null,"Remote UI has no backend")
func _process(_delta:float)->bool:
 if not finished and Time.get_ticks_msec()-pilot_start>=BUDGET_MS:finish_pilot("time_limit","300 second total audit limit; no retry",2)
 return false
func check(value:bool,label:String)->bool:
 if not value:
  push_error(label)
  finish_pilot("failed",label,1)
 return value
func finish_pilot(outcome:String,reason:String,code:int)->void:
 if finished:return
 finished=true
 audit.merge({"outcome":outcome,"reason":reason,"stage":stage,"ticks":ticks,"wall_seconds":(Time.get_ticks_msec()-pilot_start)/1000.0,"layers":layers,"public_results":public_results,"reward_cut":reward_cut,"reward_entry":reward_entry,"endpoint":endpoint,"checkpoint_answers":checkpoint_answers},true)
 if is_instance_valid(original_backend):
  audit.saves=original_backend.saves;audit.checkpoints=original_backend.checkpoints
  audit.field_steps=original_backend.field_steps
  audit.final_source={"phase":original_backend.quest_auto.phase,"running":original_backend.quest_auto.running,"message":original_backend.quest_auto.message,"map_id":original_backend.automation.position_map,"cell":str(original_backend.automation.position_cell)}
 var file=FileAccess.open("user://golden-bui-remote-pilot35-result.json",FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(audit,"  "));file.close()
 print("REMOTE PILOT RESULT ",JSON.stringify(audit))
 print("REMOTE PILOT REPORT ",ProjectSettings.globalize_path("user://golden-bui-remote-pilot35-result.json"))
 quit(code)
func exact_numeric_tree(value:Variant)->bool:
 # Session's recursive normalizer casts every float. Guard that entire input
 # first, including optional pet fields, so no fraction/nonfinite is truncated.
 if value is float:return is_finite(value) and value==floor(value) and absf(value)<=9007199254740991.0
 if value is Dictionary:
  for item in value.values():
   if not exact_numeric_tree(item):return false
 elif value is Array:
  for item in value:
   if not exact_numeric_tree(item):return false
 return true
func comparison_profile(value:Variant)->Dictionary:
 var validator=Session.new()
 if not value is Dictionary or not validator._valid_profile(value) or not exact_numeric_tree(value):return {}
 # Same existing normalization as load_game, with all keys/arrays preserved.
 return validator._normalize_numbers(value)
func uid_map(pets:Array)->Dictionary:
 var result:Dictionary={}
 for pet in pets:result[str(pet.get("pet_id",""))]=pet
 return result
func valid_roster(profile:Dictionary)->bool:
 var seen:Dictionary={}
 for pet in profile.get("pets",[])+profile.get("pet_storage",[]):
  if not pet is Dictionary:return false
  var id:String=str(pet.get("pet_id",""))
  if id.is_empty() or seen.has(id):return false
  seen[id]=true
 return true
func no_quest_reward(profile:Dictionary)->bool:
 for pet in profile.get("pets",[])+profile.get("pet_storage",[]):
  if int(pet.get("quest_reward_event",-1))==44:return false
 return true
func reward_exact(profile:Dictionary)->bool:
 # Exact additive award against two genuine successful disk baselines.
 profile=comparison_profile(profile)
 if profile.is_empty():return false
 if entry_disk.is_empty() or award_baseline.is_empty() or frozen_reward.is_empty() or saved_pet_id.is_empty():return false
 if not valid_roster(profile) or not Rules.flag(profile,"ended",44):return false
 var before:Dictionary=uid_map(award_baseline.pets)
 var current:Dictionary=uid_map(profile.get("pets",[]))
 if current.size()!=before.size()+1 or not current.has(saved_pet_id) or before.has(saved_pet_id):return false
 for id in before:
  if not current.has(id) or current[id]!=before[id]:return false
 if profile.get("pet_storage",[])!=award_baseline.get("pet_storage",[]):return false
 if int(profile.get("next_pet_id",-1))!=int(award_baseline.next_pet_id)+1:return false
 var reward:Dictionary=current[saved_pet_id]
 if reward!=frozen_reward:return false
 var expected:Dictionary={"source_enemy_id":14,"template_id":12,"quest_reward_event":44,"level":1}
 for field in expected:
  if not reward.get(field) is int or reward[field]!=expected[field]:return false
 var awards:int=0
 for pet in profile.get("pets",[])+profile.get("pet_storage",[]):
  if int(pet.get("quest_reward_event",-1))==44:awards+=1
 return awards==1
func capture_entry_disk()->bool:
 var raw:String=FileAccess.get_file_as_string(backend_node.save_path)
 var parsed=JSON.parse_string(raw)
 if not check(parsed is Dictionary and Session.new()._valid_profile(parsed) and raw==backend_node.successful_disk_payload,"Entry baseline is the actual last successful primary bytes"):return false
 entry_disk=comparison_profile(parsed)
 if not check(not entry_disk.is_empty(),"Entry profile passes validation and exact numeric normalization"):return false
 if not check(valid_roster(entry_disk) and no_quest_reward(entry_disk) and not Rules.flag(entry_disk,"ended",44) and entry_disk.get("default_companions_claimed",false) and same_location(entry_disk.location,{"map_id":811,"x":30,"y":22}),"Real initialization companions and public entrance are durably saved"):return false
 audit.entry_disk_baseline={"sha256":raw.sha256_text(),"profile":parsed.duplicate(true),"serial":backend_node.quest_save_serial}
 print("REMOTE PILOT ENTRY BASELINE ",JSON.stringify(audit.entry_disk_baseline))
 return true
func prepare_reward_comparison()->bool:
 var parsed=JSON.parse_string(before_reward_payload)
 var awarded=JSON.parse_string(reward_payload)
 if not check(parsed is Dictionary and awarded is Dictionary and Session.new()._valid_profile(parsed) and before_reward_backup==before_reward_payload and before_reward_successful==before_reward_payload,"Award baseline equals actual pre-save primary and writer backup bytes"):return false
 award_baseline=comparison_profile(parsed)
 awarded=comparison_profile(awarded)
 if not check(not award_baseline.is_empty() and not awarded.is_empty(),"Both award disks pass the same validated exact numeric normalization"):return false
 if not check(valid_roster(award_baseline) and valid_roster(awarded) and no_quest_reward(award_baseline) and not Rules.flag(award_baseline,"ended",44),"Pre-award roster has unique UIDs across storage and no event44 pet"):return false
 if not check(uid_map(award_baseline.pets)==uid_map(entry_disk.pets) and award_baseline.get("pet_storage",[])==entry_disk.get("pet_storage",[]) and award_baseline.next_pet_id==entry_disk.next_pet_id,"Every entry pet retains its full dictionary and UID through pre-award disk"):return false
 var before:Dictionary=uid_map(award_baseline.pets)
 var current:Dictionary=uid_map(awarded.pets)
 var added:Array=[]
 for id in current:
  if not before.has(id):added.append(id)
 if not check(added.size()==1,"Actual reward disk adds exactly one UID"):return false
 saved_pet_id=str(added[0]);frozen_reward=current[saved_pet_id].duplicate(true)
 if not check(saved_pet_id=="pet-%d"%int(award_baseline.next_pet_id) and reward_exact(awarded),"Exact original reward is the sole addition; no removed or changed pets, counter +1"):return false
 audit.pre_award_disk_baseline={"sha256":before_reward_payload.sha256_text(),"backup_sha256":before_reward_backup.sha256_text(),"profile":parsed.duplicate(true)}
 audit.exact_reward={"pet_id":saved_pet_id,"pet":frozen_reward.duplicate(true),"reward_disk_sha256":reward_payload.sha256_text()}
 print("REMOTE PILOT AWARD BASELINE ",JSON.stringify(audit.pre_award_disk_baseline))
 print("REMOTE PILOT EXACT REWARD ",JSON.stringify(audit.exact_reward))
 return true
func same_location(location:Dictionary,point:Dictionary)->bool:
 return int(location.get("map_id",-1))==int(point.get("map_id",-2)) and int(location.get("x",-1))==int(point.get("x",-2)) and int(location.get("y",-1))==int(point.get("y",-2))
func on_reward_saved(payload:String,entry:Dictionary)->void:
 reward_cut=true;reward_payload=payload;reward_entry=entry
 endpoint={"map_id":backend_node.automation.position_map,"x":backend_node.automation.position_cell.x,"y":backend_node.automation.position_cell.y}
 var before:Array=[]
 for row in backend_node.checkpoints:
  if row.reply.get("ok",false) and same_location(row.command,endpoint):before.append(row.duplicate(true))
 audit.endpoint_checkpoints_before_reward=before
 audit.disk_at_reward_is_endpoint=same_location(JSON.parse_string(payload).get("location",{}),endpoint)
 audit.precheckpoint_window="already_saved_before_reward" if audit.disk_at_reward_is_endpoint else "reward_saved_before_endpoint_checkpoint"
 print("REMOTE PILOT CUT ",JSON.stringify({"t":Time.get_ticks_msec(),"reward_save":entry,"endpoint":endpoint,"previous_endpoint_checkpoints":before,"window":audit.precheckpoint_window}))
 # Actual owner close, not a write rollback or a fabricated saved location.
 world.link.close()
 print("REMOTE PILOT SOCKET CLOSE t=",Time.get_ticks_msec())
 # Capture only; validation runs after the unchanged close handshake. Never
 # gate the save callback on reward_exact before its baselines are initialized.
 before_reward_successful=backend_node.previous_successful_disk_payload
 before_reward_payload=backend_node.previous_disk_payload
 before_reward_backup=FileAccess.get_file_as_string(backend_node.save_path+".bak")
func observe_source(message:Dictionary)->void:
 if message.get("type") in ["position","profile","auto_status","battle_started","battle_turn","battle_closed"]:observe_passive("final backend event",message)
 if message.get("type")=="position" and message.has("quest_position_seq"):
  backend_node.packets.append(message.duplicate(true))
  if layers.is_empty() or int(layers[-1].map_id)!=int(message.map_id):
   var row:Dictionary={"t":Time.get_ticks_msec(),"tick":ticks,"map_id":message.map_id,"cell":message.cell,"step":message.quest_step_id,"revision":message.quest_revision,"seq":message.quest_position_seq,"proof":backend_node.quest_arrival.has_arrival(backend_node,int(message.map_id),Vector2i(int(message.cell[0]),int(message.cell[1])))}
   layers.append(row);print("REMOTE PILOT LAYER ",JSON.stringify(row))
 if message.get("type")=="quest_result":
  var row:Dictionary={"t":Time.get_ticks_msec(),"tick":ticks,"text":message.get("text","")}
  public_results.append(row);print("REMOTE PILOT PUBLIC ",JSON.stringify(row))
func setup_pilot()->bool:
 backend_node=PilotBackend.new();backend_node.set_process(false);original_backend=backend_node
 backend_node.observer=observe_passive
 var profile:Dictionary=backend_node.session._profile
 profile.player.level=35;profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(profile.player)
 profile.player.hp=profile.player.max_hp
 for key in profile.inventory:profile.inventory[key]=0
 profile.no_random_encounters=false
 Equipment.add(profile,2755)
 for index in range(14):Equipment.add(profile,2752)
 backend_node.automation.position_changed(811,Vector2i(30,22),true)
 backend_node.save_path="user://golden-bui-remote-pilot35.json"
 audit.input={"level":profile.player.level,"base_stats":profile.player.base_stats,"hp":profile.player.hp,"gold":profile.player.gold,"items":profile.original_items.duplicate(),"slots":Session.bag_slots(profile),"start":{"map_id":811,"cell":[30,22]},"rng":"natural; no seed selected or inspected","admission":"internal begin_source_run; no public job2 button","budget_ms":BUDGET_MS}
 print("REMOTE PILOT INPUT ",JSON.stringify(audit.input))
 if not check(Session.bag_slots(profile)==15 and profile.pets.is_empty() and int(profile.player.gold)==20 and backend_node.save(),"Exact legal initial inventory and actual baseline save"):return false
 backend_node.reward_saved=on_reward_saved;backend_node.event.connect(observe_source)
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,"Pilot actual remote server port0"):return false
 if not await create_world():return false
 world.profile_persistence=true
 if not await ready(shown,"Pilot scene shows public811 actual authority"):return false
 if not check(await Wait.settle(self,world) and world.backend==null,"Pilot initial WS settles, backend=null"):return false
 if not check(server_node.clients().size()==1,"Pilot has one owner socket"):return false
 if not capture_entry_disk():return false
 return check(backend_node.quest_auto.begin_source_run(backend_node,world._client_id,server_node.clients()[0].get_instance_id()).get("ok",false),"Internal fixture starts actual source plan")
func independent_read(path:String,label:String)->Dictionary:
 # This completes before any new scene can checkpoint/rewrite the file.
 var raw:String=FileAccess.get_file_as_string(path)
 var parsed=JSON.parse_string(raw)
 var reader=Session.new()
 if not check(parsed is Dictionary and reader._valid_profile(parsed) and reader.load_game(path),label+": independent primary and new Session load"):return {}
 var profile:Dictionary=reader.snapshot()
 if not check(reward_exact(parsed) and reward_exact(profile),label+": raw disk and new Session retain exact baseline plus unique reward"):return {}
 var probe=PilotBackend.new();probe.set_process(false);probe.save_path=path
 if not check(probe.load_profile(path),label+": independent new Backend load"):probe.free();return {}
 if not check(reward_exact(probe.session.snapshot()),label+": new Backend retains identical full roster and reward UID"):probe.free();return {}
 var location:Dictionary=profile.location
 var point:=Vector2i(int(location.x),int(location.y))
 if not check(not probe.quest_arrival.has_arrival(probe,int(location.map_id),point) and probe.quest_auto.issued.is_empty() and not probe.quest_auto.running,label+": disk position never restores protected proof or receipt"):probe.free();return {}
 if not check(SourcePlan.select(probe,2).get("status")=="done",label+": saved END44 has no second reward plan"):probe.free();return {}
 probe.free()
 audit[label]={"location":location.duplicate(),"pet_id":saved_pet_id,"sha256":raw.sha256_text()}
 return profile
func actual_checkpoint(label:String)->Dictionary:
 world.checkpoint()
 var seq:int=world.link._seq
 if not check(world.link._callbacks.has(seq),label+": production checkpoint has actual response callback"):return {}
 var original:Callable=world.link._callbacks[seq]
 var answers:Array=[]
 world.link._callbacks[seq]=func(reply:Dictionary):
  answers.append(reply.duplicate(true));original.call(reply)
  checkpoint_answers[label]={"t":Time.get_ticks_msec(),"seq":seq,"reply":reply.duplicate(true)}
  print("REMOTE PILOT CHECKPOINT ACK ",label," ",JSON.stringify(checkpoint_answers[label]))
 if not await ready(func():return not answers.is_empty(),label+": actual WS checkpoint reply arrives"):return {}
 return answers[0]
func close_scene()->bool:
 world.link.close()
 if not await ready(func():return server_node.clients().is_empty() and not world.link.online,"Actual close handshake completes before disposing scene"):return false
 world.music.stop();world.effect.stop();world.queue_free()
 return await ready(func():return not is_instance_valid(world),"Old remote scene disposed")
func run()->void:
 first_floor_trace=false
 root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(390,844);remote_mode=true
 if not await setup_pilot():return
 stage="natural_route"
 while not reward_cut and ticks<MAX_TICKS and not finished:
  if not backend_node.quest_auto.running:
   finish_pilot("manual",backend_node.quest_auto.message,2);return
  ticks+=1;backend_node.current_tick=ticks;backend_node._process(0.21)
  if reward_cut:break
  if not check(await Wait.settle(self,world),"Natural source tick actual WS roundtrip"):return
  if backend_node.quest_auto.phase=="landing":
   if not await ready(func():return backend_node.quest_auto.phase!="landing","Natural source landing acknowledged by production scene"):return
  elif backend_node.quest_auto.phase!="battle":
   if not await ready(shown,"Natural source scene follows committed authority"):return
 if finished:return
 if not reward_cut:finish_pilot("tick_limit","No reward within10000 actual ticks; no retry",2);return
 stage="reward_saved_disconnect"
 if not await ready(func():return server_node.clients().is_empty() and not world.link.online,"Terminal reward close is observed by both real transport ends"):return
 if not prepare_reward_comparison():return
 var cut_path:="user://golden-bui-remote-precheckpoint.json"
 var cut_file=FileAccess.open(cut_path,FileAccess.WRITE)
 if not check(cut_file!=null,"Write untouched actual reward-save bytes for independent branch"):return
 cut_file.store_string(reward_payload);cut_file.close()
 var old_disk:Dictionary=independent_read(cut_path,"reward_disk_before_newscene")
 if old_disk.is_empty():return
 var actual_disk:Dictionary=independent_read(backend_node.save_path,"actual_primary_after_disconnect")
 if actual_disk.is_empty():return
 audit.checkpoints_after_reward_before_disconnect=backend_node.checkpoints.filter(func(row):return int(row.t)>=int(reward_entry.t))
 stage="live_checkpoint_failure"
 if not await close_scene():return
 var blocked_path:String=ProjectSettings.globalize_path(backend_node.save_path+".tmp")
 if not check(DirAccess.make_dir_absolute(blocked_path)==OK,"Create real checkpoint temporary-path IO obstruction after reward"):return
 if not await create_world():return
 world.profile_persistence=true
 if not await ready(shown,"Fresh remote scene restores surviving actual endpoint authority"):return
 # Rebind may still need one source tick to observe the already-saved done plan.
 if backend_node.quest_auto.running:
  if not await ready(func():return not backend_node.quest_auto.detached and backend_node.quest_auto.phase!="landing","Reconnected source receipt accepted normally"):return
  backend_node._process(0.21)
 if not check(not backend_node.quest_auto.running,"Saved final source plan stops without a second reward"):return
 var failed:Dictionary=await actual_checkpoint("io_failed")
 if not check(not failed.get("ok",true) and failed.get("reason")=="save_failed" and world.last_adventure_message.contains("保存失败"),"Actual checkpoint IO failure reaches original UI callback"):return
 if independent_read(backend_node.save_path,"primary_after_failed_checkpoint").is_empty():return
 if not check(FileAccess.get_file_as_string(backend_node.save_path).sha256_text()==str(audit.actual_primary_after_disconnect.sha256),"Failed checkpoint does not replace actual saved primary"):return
 if not check(DirAccess.remove_absolute(blocked_path)==OK,"Remove only this audit's IO obstruction"):return
 stage="successful_checkpoint"
 var success:Dictionary=await actual_checkpoint("successful")
 if not check(success.get("ok",false),"Normal production checkpoint ACK confirms successful write"):return
 var persisted:Dictionary=independent_read(backend_node.save_path,"primary_after_successful_checkpoint")
 if not check(not persisted.is_empty() and same_location(persisted.location,endpoint),"Independent primary/newSession/newBackend see actual endpoint after ACK"):return
 var final_path:="user://golden-bui-remote-final-restart.json"
 var final_file=FileAccess.open(final_path,FileAccess.WRITE)
 if not check(final_file!=null,"Retain successful actual primary for restart branch"):return
 final_file.store_string(FileAccess.get_file_as_string(backend_node.save_path));final_file.close()
 if not await close_scene():return
 server_node.stop();server_node.queue_free()
 stage="new_backend_newscene"
 backend_node=PilotBackend.new();backend_node.set_process(false);backend_node.save_path=final_path
 backend_node.observer=observe_passive
 backend_node.event.connect(func(event:Dictionary):
  if event.get("type") in ["position","profile","auto_status","battle_started","battle_turn","battle_closed"]:observe_passive("final backend event",event))
 if not check(backend_node.load_profile(final_path),"Final fresh Backend loads successful primary before scene"):return
 root.add_child(backend_node)
 server_node=preload("res://server/ws_server.gd").new(backend_node,0,"127.0.0.1");root.add_child(server_node)
 if not check(server_node.start()==OK,"Fresh restart server port0"):return
 if not await create_world():return
 if not await ready(func():return int(world.data.get("map_id",-1))==int(endpoint.map_id) and world.cell==Vector2i(int(endpoint.x),int(endpoint.y)) and not world.area_transition_busy,"New scene normally restores independently validated terminal disk location"):return
 if not check(await Wait.settle(self,world) and reward_exact(backend_node.session.snapshot()),"New remote scene retains the exact unique original reward"):return
 if not check(not backend_node.quest_arrival.has_arrival(backend_node,int(endpoint.map_id),Vector2i(int(endpoint.x),int(endpoint.y))) and backend_node.quest_auto.issued.is_empty(),"New scene checkpoint does not grant old protected proof or receipt"):return
 if not await close_scene():return
 server_node.stop();server_node.queue_free();backend_node.queue_free()
 stage="done"
 finish_pilot("complete","One natural35 route and real persistence branches; see actual precheckpoint-window classification",0)
