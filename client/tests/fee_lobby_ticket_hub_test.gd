extends SceneTree
const Clock=preload("res://scripts/clock.gd")
## Real Accounts and Hub handlers, synchronous transport (no WebSocket).
const B=preload("res://tests/support/fee_lobby_ticket_backend.gd")
const S=preload("res://tests/support/fee_lobby_ticket_fault_session.gd")
const Lock=preload("res://server/save_lock.gd")
var checks:int=0
var failures:int=0
var fixtures:int=0
var loads:int=0
class Accounts extends "res://server/accounts.gd":
 var issued:Array=[]
 func issue_token(id:String)->String:
  var token:String=super.issue_token(id)
  issued.append({"id":id,"token":token})
  return token
class Hub extends "res://server/profile_hub.gd":
 var load_counter:Dictionary={"count":0}
 func _new_profile_backend()->Backend:
  var b=preload("res://tests/support/fee_lobby_ticket_backend.gd").new()
  b.load_counter=load_counter
  b.session=preload("res://tests/support/fee_lobby_ticket_fault_session.gd").new(func():return 1791504000)
  b.session.host=weakref(b)
  b.session.battle_pets_hook=b._live_battle_pets;b.session.capture_entry_hook=b._capture_entry
  return b
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;push_error(label)
func put(path:String,data:PackedByteArray)->void:
 var f=FileAccess.open(path,FileAccess.WRITE)
 check(f!=null,"fixture file open")
 if f==null:return
 f.store_buffer(data);f.flush();check(f.get_error()==OK,"fixture flush");f.close()
func raw(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"exists":false,"bytes":PackedByteArray()}
 var f=FileAccess.open(path,FileAccess.READ)
 if f==null:return {"exists":true,"unknown":true}
 var bytes:PackedByteArray=f.get_buffer(f.get_length());f.close()
 return {"exists":true,"bytes":bytes}
func disks(b)->Array:return [raw(b.save_path),raw(b.save_path+".bak"),raw(b.save_path+".tmp"),raw(b._resume_file()),raw(b._resume_file()+".tmp")]
func one(kind:String)->void:
 fixtures+=1
 var dir:String="user://lobby-hub-%d-%d-%s"%[Clock.ticks_usec(),fixtures,kind]
 check(DirAccess.make_dir_recursive_absolute(dir)==OK,"fixture directory")
 var hub=Hub.new(dir+"/accounts.json");hub.accounts=Accounts.new(dir+"/accounts.json");hub.tick=false;hub.backups=false;hub.share_dir=""
 check(hub.accounts.load_file(),"real accounts load")
 var a:Dictionary=hub.accounts.create("Old","1234")
 var z:Dictionary=hub.accounts.create("New","4321")
 check(a.get("ok")==true and z.get("ok")==true,"two real accounts")
 if not a.get("ok",false) or not z.get("ok",false):hub.free();return
 var source=S.new(func():return 1791504000)
 source._profile.player.level=35;source._profile.player.gold=1000000
 for key in source._profile.inventory:source._profile.inventory[key]=0
 source.set_location(811,30,22)
 var initial:Dictionary=source.snapshot()
 var target:Dictionary=initial.duplicate(true);target.character_id="100005"
 put(hub.accounts.save_path(a.entry),JSON.stringify(initial).to_utf8_buffer())
 put(hub.accounts.save_path(z.entry),JSON.stringify(target).to_utf8_buffer())
 var login:Dictionary=hub.handle(71,{"type":"login","name":"Old","pin":"1234"})
 check(login.get("ok")==true,"actual Hub login "+str(login.get("reason","")))
 if not login.get("ok",false):hub.free();return
 var b=hub.backend_of(71)
 b.automation.position_changed(811,Vector2i(30,22),true)
 check(b.save(),"canonical seed")
 var target_live:Dictionary=b.session._profile.duplicate(true);target_live.character_id="100005"
 var start:Dictionary=hub.handle(71,{"type":"quest_auto_start","quest_id":2,"seq":71,"client":"explicit"})
 check(start.get("ok")==true,"real Hub Start "+str(start.get("reason","")))
 if not start.get("ok",false):
  Lock.release(b.save_path);hub.free();return
 b.session.writes=0;b.session.calls=[];b.session.at=3;b.session.mode="unknown"
 b.purchase_turn()
 check(b._fee_lobby_ticket.held(b) and not b.quest_auto.running,"real purchase created hold and stopped execution")
 var marker:Dictionary={"foreign":{"keep":"native"},"quest_auto":{"identity":{"run_id":"ffffffffffffffffffffffffffffffff","step_id":"foreign","revision":1}}}
 if kind=="mixed":
  marker.quest_auto.identity.run_id=start.run_id;marker.quest_auto.identity.step_id="jewels:hunt:2760"
  marker["fee_attempt_binding"]={"owner":{"profile_id":b.session._profile.profile_id,"character_id":b.session._profile.character_id},"run_id":start.run_id}
 var bytes:PackedByteArray=JSON.stringify(JSON.from_native(marker)).to_utf8_buffer()
 put(b._resume_file(),bytes);put(b._resume_file()+".tmp",bytes)
 var frozen:Array=disks(b);var before:Dictionary=b.session._profile.duplicate(true);var serial:int=b.quest_save_serial
 var binding:RefCounted=b._fee_bindings[71]
 var tokens_before:Dictionary=hub.accounts.data.duplicate(true)
 var issued_before:int=hub.accounts.issued.size()
 var connection_before:Dictionary=hub._connections.duplicate(true)
 var result:Dictionary
 match kind:
  "logout","warm","mixed":result=hub.handle(71,{"type":"logout"})
  "switch":result=hub.handle(71,{"type":"login","name":"New","pin":"4321"})
  "target_failure":
   put(hub.accounts.save_path(z.entry),"bad".to_utf8_buffer())
   result=hub.handle(71,{"type":"login","name":"New","pin":"4321"})
  "generic":
   b.keep_resume_file()
   result={"ok":not b.save()}
 check(result.get("ok")== (kind!="target_failure"),kind+": real completion/rejection")
 check(disks(b)==frozen and b.session._profile==before and b.quest_save_serial==serial,kind+": entire old profile/main/bak/tmp/native sidecars unchanged")
 check(b._fee_lobby_ticket.held(b),kind+": hold survives departure/run lifecycle")
 if kind in ["logout","warm","switch","mixed"]:
  check(not b._fee_bindings.has(71),kind+": old binding revoked")
 if kind=="target_failure":check(hub.backend_of(71)==b and is_same(b._fee_bindings.get(71),binding),"target open failure keeps original character/binding")
 if kind in ["logout","warm","mixed"]:
  check(not hub.accounts.verify_token("Old",login.token).get("ok",false),"real logout revokes old account token")
 if kind=="warm":
  var n:int=b.actual_loads
  result=hub.handle(71,{"type":"login","name":"Old","pin":"1234"})
  check(result.get("ok")==true and hub.backend_of(71)==b and b.actual_loads==n and b._fee_lobby_ticket.held(b),"warm cached login is not a load and cannot release")
  check(not b.save() and disks(b)==frozen,"warm stale profile cannot overwrite")
 if kind=="switch":
  var other=hub.backend_of(71)
  check(other!=b and other.session._profile==target_live and not other._fee_lobby_ticket.held(other),"different real owner does not inherit hold")
  var expected:Dictionary=other.session._profile.duplicate(true)
  check(other.save() and other.session._profile==expected,"successor ordinary save works")
 var expected_accounts:Dictionary=tokens_before.duplicate(true)
 if kind in ["logout","warm","mixed"]:
  for entry in expected_accounts.profiles:
   if entry.id==a.entry.id:entry.tokens.erase(login.token.sha256_text())
 for issued in hub.accounts.issued.slice(issued_before):
  for entry in expected_accounts.profiles:
   if entry.id==issued.id:entry.tokens.append(issued.token.sha256_text())
 check(hub.accounts.data==expected_accounts and raw(hub.accounts.path)=={"exists":true,"bytes":JSON.stringify(expected_accounts,"  ").to_utf8_buffer()},"independent entire Accounts and token disk")
 var expected_connections:Dictionary=connection_before.duplicate(true)
 if kind in ["logout","mixed"]:expected_connections.erase(71)
 if kind in ["warm","switch"]:expected_connections[71]={"id":a.entry.id if kind=="warm" else z.entry.id,"token":hub.accounts.issued[-1].token}
 check(hub._connections==expected_connections,"independent whole connection token mapping")
 loads+=hub.load_counter.count
 for backend in hub.backends.values():Lock.release(backend.save_path)
 hub.free()
 print("LOBBY HUB FIXTURE ",fixtures," ",kind," end")
func run()->void:
 for kind in ["logout","switch","warm","target_failure","generic","mixed"]:one(kind)
 print("LOBBY HUB SUMMARY checks=",checks," failures=",failures," fixtures=",fixtures," real_loads=",loads)
 quit(1 if failures else 0)
