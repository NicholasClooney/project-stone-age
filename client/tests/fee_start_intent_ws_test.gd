extends SceneTree
## One real loopback WsServer/WsLink, no authenticated ProfileHub or GUI pixels.
## Explicit raw duplicate is adversarial test traffic, NOT client retry behavior.
const Backend=preload("res://tests/support/fee_start_intent_backend.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Wait=preload("res://tests/support/wait.gd")
const Codec=preload("res://network/codec.gd")
var checks:=0
var failures:=0
var link
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;push_error(label)
func until(predicate:Callable)->bool:
 return await Wait.until(self,func():link.poll(0.01);return predicate.call())
func rpc(command:Dictionary)->Dictionary:
 var answers:Array=[]
 link.request(command,func(reply):answers.append(reply))
 check(await until(func():return not answers.is_empty()),"real WS reply")
 return {} if answers.is_empty() else answers[0]
func profile_with(before:Dictionary,run_id:String,status:String)->Dictionary:
 var value:Dictionary=before.duplicate(true)
 value.quest_auto_fee_lifecycle={"schema":1,"owner":{"profile_id":before.profile_id,"character_id":before.character_id},"current":{"run_id":run_id,"run_status":status,"purchase":{"state":"manual_only"}},"unresolved_attempt":{}}
 return value
func disks(path:String,value:Dictionary)->void:
 check(FileAccess.get_file_as_bytes(path)==JSON.stringify(value).to_utf8_buffer(),"complete primary independent bytes")
 check(FileAccess.get_file_as_bytes(path+".bak")==JSON.stringify(value).to_utf8_buffer(),"complete backup independent bytes")
 check(not FileAccess.file_exists(path+".tmp"),"tmp absent")
func run()->void:
 var b=Backend.new();b.set_process(false);root.add_child(b)
 b.session._profile.player.level=35;b.session._profile.no_random_encounters=true
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 Equipment.add(b.session._profile,2755)
 b.automation.position_changed(811,Vector2i(30,22),true)
 b.save_path="user://fee-start-ws-%d.json"%Time.get_ticks_usec()
 check(b.session._valid_profile(b.session.snapshot()) and b.save(),"full initial save")
 var before:Dictionary=b.session._profile.duplicate(true)
 var serial:int=b.quest_save_serial
 var server=preload("res://server/ws_server.gd").new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"real isolated listener")
 link=preload("res://network/ws_link.gd").new("ws://127.0.0.1:%d"%server.port)
 link.connect_now();check(await until(func():return link.online),"real hello")
 var reply:Dictionary=await rpc({"type":"quest_auto_start","quest_id":2,"client":"menu"})
 check(reply.get("ok",false) and reply.get("persisted_intent",false),"wire Start ACK after private installation")
 if failures:link.close();server.stop();server.free();b.free();quit(1);return
 var run_id:String=reply.run_id
 var expected:Dictionary=profile_with(before,run_id,"active")
 var token:RefCounted=b._fee_start_intent._live.token
 var binding:RefCounted=b._fee_bindings[b.quest_auto.connection]
 check(b.session._profile==expected and b.quest_save_serial==serial+1,"full profile/gold/ticket UID and serial independent oracle")
 disks(b.save_path,expected)
 var answers:Array=[]
 link._callbacks[int(reply.seq)]=func(value):answers.append(value)
 link._send(Codec.encode({"type":"quest_auto_start","quest_id":2,"client":"menu","seq":reply.seq}))
 check(await until(func():return not answers.is_empty()),"raw same-binding duplicate reply")
 check(not answers.is_empty() and answers[0].get("duplicate",false) and b.candidates.size()==1 and is_same(b._fee_start_intent._live.token,token),"lost ACK simulation never new permission")
 link.close();check(await until(func():return b.quest_auto.detached),"real disconnect detaches")
 check(not b._fee_start_intent.live_current(b),"connection loss revokes private permission")
 var sent:int=b.candidates.size()
 link.connect_now();check(await until(func():return link.online),"actual new binding hello")
 await rpc({"type":"ping"})
 check(b.candidates.size()==sent and b.quest_auto.detached,"hello/reconnect sent no Start")
 await rpc({"type":"report_position","map_id":811,"cell":[30,22],"client":"menu"})
 check(not b.quest_auto.detached and not is_same(binding,b._fee_bindings[b.quest_auto.connection]) and b._fee_start_intent._live.is_empty(),"warm authoritative handshake does not mint")
 await rpc({"type":"quest_auto_continue","client":"menu"})
 check(b.candidates.size()==sent and b._fee_start_intent._live.is_empty(),"continue no new intent")
 disks(b.save_path,expected)
 var stopped:Dictionary=await rpc({"type":"quest_auto_stop","client":"menu"})
 var closed:Dictionary=profile_with(before,run_id,"closed")
 check(stopped.get("ok",false) and b.session._profile==closed,"actual old Stop closes full profile")
 disks(b.save_path,closed)
 var next:Dictionary=await rpc({"type":"quest_auto_start","quest_id":2,"client":"menu"})
 check(next.get("ok",false) and next.get("run_id",run_id)!=run_id and b.candidates.size()==sent+1,"only another explicit request starts a new run")
 if next.get("ok",false):
  var next_profile:Dictionary=profile_with(before,next.run_id,"active")
  check(b.session._profile==next_profile and not b._fee_start_intent._live.purchase_allowed,"new intent still has no purchase eligibility")
  disks(b.save_path,next_profile)
 link.close();server.stop();server.free();b.free()
 print("START INTENT WS SUMMARY: ",checks," checks, ",failures," failures; 1 fixture, 0 loads, no cleanup of disks")
 quit(1 if failures else 0)
