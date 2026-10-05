extends SceneTree
## UNRUN: requires actual core A0/A1/A2/A3 original commits, not yet supplied.
## Internal server acquire/open/sample/close fixture, NOT public loot admission.
## Actual two remote scenes consume production publication; no ClientState injection.
const Backend=preload("res://server/backend.gd")
const Server=preload("res://server/ws_server.gd")
const Session=preload("res://server/game_session.gd")
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const State=preload("res://server/quest_auto_loot_state.gd")
const Sources=preload("res://server/quest_auto_loot_sources.gd")
const Game=preload("res://scripts/game.gd")
const Wait=preload("res://tests/support/wait.gd")
const ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
var host
var server
var worlds:Array=[]
var clock_ms:int=1000
var path:String="user://loot-projection-remote.json"
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->bool:
 print(("PASS " if ok else "FAIL ")+note)
 if not ok:quit(1)
 return ok
func ready(condition:Callable,note:String)->bool:
 return check(await Wait.until(self,condition),note)
func budget(world)->Dictionary:
 return world.state.derived.get("quest_auto",{}).get("budget",{})
func panel(world):return world.find_child("QuestAutoChip",true,false).loot_panel
func entry()->Dictionary:return host.session._profile.quest_loot.entries[State.STEP]
func persisted(stage:String)->bool:
 var payload:String=host.last_saved_payload
 var disk:String=FileAccess.get_file_as_string(path)
 var copy:Dictionary=ProfileCompare.validated_copy(host.session,payload)
 if not check(copy.get("ok",false),"Complete cached profile validates before independent normalization: "+stage):return false
 if not check(copy.profile==host.session.snapshot(),"Full native profile equals validated cache copy: "+stage):return false
 if not check(disk==payload,"Exact primary bytes equal acknowledged payload: "+stage):return false
 for pair in [["payload",payload],["primary",disk]]:
  var file=FileAccess.open("user://loot-projection-"+stage+"-"+pair[0]+".json",FileAccess.WRITE)
  if not check(file!=null,"Independent raw evidence file opens"):return false
  file.store_string(pair[1]);file.close()
 print("LOOT PERSISTENCE ",JSON.stringify({"stage":stage,"payload_sha256":payload.sha256_text(),"primary_sha256":disk.sha256_text(),"bytes":disk.to_utf8_buffer().size()}))
 return true
func lifecycle(stage:String)->Dictionary:
 var q=host.quest_auto
 var peers:Array=[]
 for peer in server.clients():peers.append(peer.get_instance_id())
 var clients:Array=[]
 for world in worlds:
  clients.append({"scene":world.get_instance_id(),"online":world.link.online,"current_peer":world.link._peer.get_instance_id() if world.link._peer!=null else 0,"cached_identity":world.state.derived.get("quest_auto",{}).duplicate(true)})
 var binding:Dictionary={"identity":q.identity.checkpoint().duplicate(true),"connection":q.connection,"client":q.client,"detached":q.detached}
 print("LOOT LIFECYCLE ",JSON.stringify({"stage":stage,"binding":binding,"running":q.running,"server_peers":peers,"clients":clients}))
 return binding
func idle(operation:String,args:Dictionary)->bool:
 var owner=host.session
 var saved_path:String=host.save_path
 var expected:Dictionary=owner.snapshot()
 var result:Dictionary=owner.commit_loot_idle_transition(expected,expected.quest_loot.duplicate(true),operation,args,saved_path,host._loot_settlement_written.bind(owner,saved_path))
 if not check(result.get("ok",false) and result.get("installed",false) and host.session==owner and host.save_path==saved_path,"Actual idle "+operation+" commits to same owner/path"):return false
 return persisted("idle-"+operation)
func entry_args()->Dictionary:
 return {"step_id":State.STEP,"expected_entry":State.identity(entry())}
func connect_scene(tag:String):
 Game.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate()
 Game.server_url_override=""
 world.profile_persistence=false
 world.viewer_prefs_path="user://loot-projection-"+tag+".cfg"
 root.add_child(world);worlds.append(world)
 if not await ready(func():return world.link.online and not world.data.is_empty(),"Actual remote scene "+tag+" authenticated"):return null
 if not check(world.backend==null and await Wait.settle(self,world),"Remote backend=null and real roundtrip"):return null
 world.quest_helper_menu.close_menu()
 return world
func published_sample(used:int)->bool:
 host.publish()
 for world in worlds:
  if not await ready(func():
   var value=budget(world).get("entry")
   return value is Dictionary and int(value.used_ms)==used and panel(world).visible and panel(world).content().contains("本步已用 %d ms"%used),"Production WS/state/chip reflects exact cached sample"):return false
 return check(budget(worlds[0])==budget(worlds[1]),"Both clients consume complete identical budget projection")
func run()->void:
 root.size=Vector2i(390,844);root.content_scale_size=Vector2i.ZERO
 host=Backend.new();root.add_child(host);host.set_process(false);host.save_path=path
 if not check(host.save(),"Actual independent disk baseline before projection"):return
 if not persisted("initial"):return
 host.publish()
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Real isolated server port0"):return
 var first=await connect_scene("a")
 if first==null:return
 var second=await connect_scene("b")
 if second==null:return
 for world in worlds:
  if not check(not budget(world).is_empty() and budget(world).enabled==false and budget(world).entry==null,"Production disabled nonempty budget has no fabricated entry"):return
  if not check(world.quest_helper_travel.auto_status().contains("尚未开放") and not world.quest_helper_travel.auto_status().contains("本步已用"),"Empty ledger has unavailable text and no fake zero usage"):return
 var q=host.quest_auto
 q.identity.begin();q.identity.select_step(State.STEP)
 var existing:int=host.session.snapshot().get("original_items",[]).count(2760)
 if not idle("acquire",{"step_id":State.STEP,"budget_id":ID,"run_id":q.identity.run_id,"minutes":30,"existing_items":existing}):return
 if not await published_sample(0):return
 if not check(entry().saved_battles==0 and entry().new_items==0,"Idle fixture never manufactures battles or drops"):return
 var durable=Session.new()
 if not check(durable.load_game(path) and durable.snapshot()==host.session.snapshot(),"Independent Session reads exact full native closed-entry profile"):return
 for world in worlds:
  if not check(panel(world).controls.disabled and panel(world).controls.pressed.get_connections().is_empty() and panel(world).content().contains("尚未开放"),"Real entry does not expose commands"):return
 # Internal initial-state binding only. No route/proof/admission/executor claim.
 q.running=true;q.step=Sources.step();q.detached=false
 var run_binding:Dictionary=lifecycle("internal-active-unbound-peer")
 if not idle("open",entry_args()):return
 var timer=host.quest_loot;timer.clock=func():return clock_ms
 if not check(timer.start_after_commit(State.STEP,entry(),q.identity.checkpoint()),"Timer starts only after actual durable open"):return
 clock_ms=1250
 if not check(timer.sample_active(),"Explicit first server sample"):return
 if not await published_sample(250):return
 var identity:Dictionary=State.identity(entry())
 clock_ms=1750
 if not check(timer.sample_active(),"Explicit second server sample"):return
 if not await published_sample(750):return
 if not check(State.identity(entry())==identity and budget(first).entry.saved_used_ms==0,"Same ledger revision accepts newer sample, saved time stays committed"):return
 var ack:Dictionary={}
 first.link.request({"type":"set_automation_settings","settings":{"quest":{"loot_minutes":45}}},func(reply):ack.merge(reply))
 if not await ready(func():return not ack.is_empty(),"Real settings ACK arrives"):return
 if not check(ack.get("ok",false),"Existing settings command succeeds"):return
 if not persisted("settings-ack"):return
 for world in worlds:
  if not await ready(func():return budget(world).get("default_limit_minutes")==45,"Real preference projection reaches each client"):return
  if not check(budget(world).entry.limit_ms==1800000 and budget(world).entry.budget_id==ID,"Preference cannot adjust existing entry"):return
 var before_disconnect:Dictionary=budget(first).duplicate(true)
 if not check(lifecycle("before-client-close")==run_binding,"Internal run identity/connection/detached unchanged before stale check"):return
 first.link.close()
 if not await ready(func():return panel(first).content().contains("连接状态已过期"),"Disconnected panel marks actual cached view stale"):return
 if not check(lifecycle("after-client-close-stale")==run_binding,"Unbound peer close is only client stale, not a claimed loot detach"):return
 clock_ms=2000 # Clock advances without sampling; rendering cannot read it.
 if not check(budget(first)==before_disconnect and panel(first).content().contains("本步已用 750 ms"),"Offline display never extrapolates server clock"):return
 # Explicit internal no-battle freeze/close, NOT production detach scheduling.
 if not check(timer.pause_idle(),"Internal idle driver freezes span"):return
 if not check(timer.sample_active(),"Explicit frozen sample records final1000 before close"):return
 if not check(timer.cached_sample.used_ms==1000,"Frozen sample is final1000, not previous750"):return
 var close_args=entry_args();close_args.total_used_ms=timer.cached_sample.used_ms
 if not idle("close",close_args):return
 if not check(timer.accept_commit(host.session.snapshot().quest_loot),"Timer acknowledges actual closed ledger"):return
 q.running=false;host.publish()
 if not check(lifecycle("closed-history-before-reconnect")==run_binding,"Internal close preserves identity and unbound connection"):return
 first.link.connect_now()
 if not await ready(func():return first.link.online and budget(first).get("entry",{}).get("saved_used_ms")==1000,"Reconnection receives actual frozen persisted record"):return
 if not await published_sample(1000):return
 if not check(lifecycle("historical-budget-reconnected")==run_binding,"Historical reconnect does not bind or resume an active run"):return
 if not check(not panel(first).content().contains("连接状态已过期"),"Current authenticated projection replaces stale panel"):return
 if not persisted("final-before-independent-load"):return
 var final_session=Session.new()
 if not check(final_session.load_game(path) and final_session.snapshot()==host.session.snapshot(),"Independent final disk retains full native profile without UI reset"):return
 for world in worlds:
  world.link.close();world.music.stop();world.effect.stop();world.queue_free()
 if not await ready(func():return worlds.all(func(world):return not is_instance_valid(world)),"Both real scenes disposed"):return
 server.stop();server.queue_free();host.queue_free()
 print("LOOT PROJECTION REMOTE UI: PASS (internal idle driver only; no public admission/battle/storage coverage)")
 quit(0)
