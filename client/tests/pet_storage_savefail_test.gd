extends SceneTree
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Link=preload("res://network/ws_link.gd")
const State=preload("res://network/client_state.gd")
const Wait=preload("res://tests/support/wait.gd")
var failures:=0
var links:Array=[]
var states:Array=[]
var events:Array=[]
func _initialize():call_deferred("run")
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func poll()->void:
 for link in links:link.poll(0.01)
func request(index:int,command:Dictionary)->Dictionary:
 var replies:Array=[]
 links[index].request(command,func(reply):replies.append(reply))
 var answered:bool=await Wait.until(self,func():poll();return not replies.is_empty())
 check(answered,"websocket reply %s"%command.type)
 return replies[0] if answered else {"ok":false,"reason":"timeout"}
func sync()->void:
 for i in range(links.size()):await request(i,{"type":"ping"})
func run()->void:
 var b=Backend.new();root.add_child(b)
 b.save_path="user://pet-storage-savefail-%d.json"%OS.get_process_id()
 b.session.grant_starter_pets()
 # Keep distinct active/riding references while moving a third individual.
 b.session.select_pet(1);b.session._profile.ride_pet=2
 b.session.store_pet(0,true)
 var extra:Dictionary=b.session.snapshot().pet_storage[0].duplicate(true)
 b.session._assign_pet_id(extra);b.session._profile.pet_storage.append(extra)
 b.session._profile.pet_storage[0].auto_qualified=true
 check(b.save(),"fixture saved through real persistence")
 b.publish()
 var before:Dictionary=b.session.snapshot()
 var disk_before:=FileAccess.get_file_as_string(b.save_path)
 var revision:int=b.rev
 var payload:String=b.last_saved_payload
 var storage_json:String=b._storage_json
 b.event.connect(func(event):events.append(event.duplicate(true)))
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1")
 root.add_child(server);check(server.start()==OK,"ephemeral websocket server")
 for i in range(2):
  var link=Link.new("ws://127.0.0.1:%d"%server.port);var state=State.new()
  links.append(link);states.append(state);link.message.connect(state.apply);link.connect_now()
 check(await Wait.until(self,func():poll();return links[0].online and links[1].online),"two websocket devices online")
 await sync();events.clear()
 check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"real temp-save directory blocks FileAccess.open")
 var command:={"type":"retrieve_pet_by_id","pet_id":str(before.pet_storage[0].pet_id)}
 var reply:Dictionary=await request(0,command)
 await sync()
 print("SAVE FAILURE OBSERVED: reply=%s memory_moved=%s disk_unchanged=%s revision_delta=%d"%[JSON.stringify(reply),b.session.snapshot()!=before,FileAccess.get_file_as_string(b.save_path)==disk_before,b.rev-revision])
 check(not reply.ok and str(reply.get("reason","")).contains("保存失败"),"filesystem failure returns readable rejection")
 check(b.session.snapshot()==before,"failure restores full profile including UID flags order active riding and counter")
 check(b.rev==revision and b.last_saved_payload==payload and b._storage_json==storage_json and events.is_empty(),"failure does not publish or advance revision/save cache")
 check(FileAccess.get_file_as_string(b.save_path)==disk_before,"failure leaves disk bytes unchanged")
 for state in states:check(state.full_profile()==before and state.rev==revision,"both devices retain original profile and revision")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path) and loaded.snapshot()==before,"failed operation reads back unchanged")
 DirAccess.remove_absolute(b.save_path+".tmp")
 if reply.ok:
  # Stop here on the unfixed backend: retry would correctly find the UID gone.
  cleanup(b,server);print("PET STORAGE ATOMIC SAVE: %d failures"%failures);quit(1);return
 reply=await request(1,command);await sync()
 var expected:Dictionary=before.duplicate(true)
 var moved:Dictionary=expected.pet_storage.pop_front()
 for flag in ["auto_reject","auto_hunt","auto_qualified"]:moved.erase(flag)
 expected.pets.append(moved)
 check(reply.ok and b.session.snapshot()==expected and b.rev==revision+1,"other device retries successfully exactly once with original success semantics")
 check(loaded.load_game(b.save_path) and loaded.snapshot()==expected,"retry persists exact pet properties and warehouse order")
 for state in states:check(state.full_profile()==expected,"both devices receive committed retry")
 events.clear();revision=b.rev;disk_before=FileAccess.get_file_as_string(b.save_path)
 reply=await request(0,command);await sync()
 check(not reply.ok and str(reply.reason).contains("已不在仓库") and b.session.snapshot()==expected and b.rev==revision and events.is_empty() and FileAccess.get_file_as_string(b.save_path)==disk_before,"stale UID cannot retrieve twice or publish")
 # The indexed route and symmetric store share this exact save boundary.
 for cmd in [{"type":"retrieve_pet","index":0},{"type":"store_pet","index":2,"auto_hunt":true},{"type":"store_pet","index":0}]:
  check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"block symmetric save")
  reply=await request(0,cmd);await sync()
  check(not reply.ok and str(reply.reason).contains("保存失败") and b.session.snapshot()==expected and b.rev==revision and events.is_empty(),"%s failure restores active/riding refs and every property"%cmd.type)
  check(FileAccess.get_file_as_string(b.save_path)==disk_before,"symmetric failure leaves disk unchanged")
  DirAccess.remove_absolute(b.save_path+".tmp")
 # Real carried-capacity refusal must retain its original reason.
 while b.session._profile.pets.size()<Session.PET_CAPACITY:
  var pet:Dictionary=moved.duplicate(true);b.session._assign_pet_id(pet);b.session._profile.pets.append(pet)
 check(b.save(),"full roster saved")
 b.publish();await sync();events.clear();before=b.session.snapshot();revision=b.rev;disk_before=FileAccess.get_file_as_string(b.save_path)
 reply=await request(1,{"type":"retrieve_pet_by_id","pet_id":str(before.pet_storage[0].pet_id)});await sync()
 check(not reply.ok and str(reply.reason).contains("已满") and b.session.snapshot()==before and b.rev==revision and events.is_empty() and FileAccess.get_file_as_string(b.save_path)==disk_before,"capacity rejection preserves profile UID disk and publication")
 var settings=preload("res://server/server_settings.gd")
 settings.path_override="user://pet-storage-savefail-settings.cfg"
 var config=ConfigFile.new();config.set_value("pet_storage","capacity",before.pet_storage.size())
 check(config.save(settings.path_override)==OK,"isolated warehouse capacity setting")
 reply=await request(0,{"type":"store_pet","index":2});await sync()
 check(not reply.ok and str(reply.reason).contains("仓库已满") and b.session.snapshot()==before and b.rev==revision and events.is_empty() and FileAccess.get_file_as_string(b.save_path)==disk_before,"warehouse capacity refusal preserves both collections and disk")
 DirAccess.remove_absolute(settings.path_override);settings.path_override=""
 cleanup(b,server)
 print("PET STORAGE ATOMIC SAVE: %d failures"%failures)
 quit(1 if failures else 0)
func cleanup(b,server)->void:
 for link in links:link.close()
 server.stop();server.queue_free()
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(b.save_path+suffix)
 b.queue_free()
