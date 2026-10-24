extends SceneTree
const Clock=preload("res://scripts/clock.gd")
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Probe=preload("res://tests/support/fee_departure_backend.gd")
const Fault=preload("res://tests/support/fee_departure_session.gd")
const SaveLock=preload("res://server/save_lock.gd")
const RUN="11111111111111111111111111111111"
const OTHER="22222222222222222222222222222222"
var checks:=0
var failures:=0
var fixtures:=0
var loads:=0
var paths:Array[String]=[]
class CallbackAccounts extends "res://server/accounts.gd":
	var callback:Callable
	var issued:Array=[]
	func issue_token(id:String)->String:
		var token:String=super.issue_token(id);issued.append({"id":id,"token":token});return token
	func revoke_token(id:String,token:String)->void:
		super.revoke_token(id,token)
		if callback.is_valid():
			var call:Callable=callback;callback=Callable();call.call()
class Hub extends "res://server/profile_hub.gd":
	var gate:=true
	var factories:=0
	var actual_loads:=0
	var ended_calls:Array[WeakRef]=[]
	func _connection_done(f:Dictionary)->void:
		ended_calls.append(weakref(f.call))
		super._connection_done(f)
	var hook:Callable
	var at:=""
	func fire(point:String)->void:
		if at!=point or not hook.is_valid():return
		at="";hook.call()
	func _listing()->Array:
		var result:Array=super._listing();fire("listing");return result
	func _attach(id:String)->void:
		super._attach(id);fire("attach")
	func _party_gone(id:String)->void:
		super._party_gone(id);fire("party")
	func open_profile(id:String)->String:
		var result:String=super.open_profile(id);fire("open");return result
	func _new_profile_backend()->Backend:
		factories+=1
		var b=preload("res://tests/support/fee_departure_backend.gd").new()
		b.gate=gate
		b.load_observer=func():actual_loads+=1
		var rng:=RandomNumberGenerator.new();rng.seed=2193
		b.session=preload("res://tests/support/fee_departure_session.gd").new(Callable(),rng)
		b.session.battle_pets_hook=b._live_battle_pets;b.session.capture_entry_hook=b._capture_entry
		return b
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func truth(value:Variant)->bool:
	if not value is bool:return false
	return value
func put(path:String,bytes:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	check(file!=null,"fixture open")
	if file==null:return
	file.store_buffer(bytes);file.flush();check(file.get_error()==OK,"fixture write");file.close()
func image(path:String)->Dictionary:
	if not FileAccess.file_exists(path):return {"exists":false}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"unknown":true}
	var bytes:PackedByteArray=file.get_buffer(file.get_length())
	file.close();return {"exists":true,"bytes":bytes}
func row(profile:Dictionary)->Dictionary:return {"exists":true,"bytes":JSON.stringify(profile).to_utf8_buffer()}
func disks(path:String)->Array:return [image(path),image(path+".bak"),image(path+".tmp")]
func side(b)->Array:return [image(b._resume_file()),image(b._resume_file()+".tmp")]
func fixture(tag:String,gate:bool=true,distinct_owner:bool=false)->Dictionary:
	fixtures+=1
	var dir:String="user://fee-departure-%d-%02d-%s"%[Clock.ticks_usec(),fixtures,tag]
	check(DirAccess.make_dir_recursive_absolute(dir)==OK,"fixture directory")
	paths.append(ProjectSettings.globalize_path(dir))
	var hub:=Hub.new(dir+"/accounts.json")
	hub.accounts=CallbackAccounts.new(dir+"/accounts.json")
	hub.gate=gate;hub.tick=false;hub.backups=false;hub.share_dir=""
	check(hub.accounts.load_file(),"real Accounts read")
	var a:Dictionary=hub.accounts.create("Old","1234")
	var z:Dictionary=hub.accounts.create("New","4321")
	check(truth(a.get("ok")) and truth(z.get("ok")),"real Accounts two owners")
	var source:=Session.new()
	var original:Dictionary=source.snapshot()
	var target:Dictionary=original.duplicate(true)
	if distinct_owner:target.character_id="100005"
	check(source._valid_profile(original) and source._valid_profile(target),"both full fixture profiles obey real loader schema")
	if not source._valid_profile(original) or not source._valid_profile(target):hub.free();return {}
	put(hub.accounts.save_path(a.entry),JSON.stringify(original).to_utf8_buffer())
	put(hub.accounts.save_path(z.entry),JSON.stringify(target).to_utf8_buffer())
	var login:Dictionary=hub.handle(71,{"type":"login","name":"Old","pin":"1234"})
	print("B3C LOGIN fixture=%d reply=%s"%[fixtures,JSON.stringify({"ok":login.get("ok"),"reason":login.get("reason","")})])
	check(truth(login.get("ok")),"actual Hub login")
	if not truth(login.get("ok")):
		hub.free()
		return {}
	var b=hub.backend_of(71)
	var before:Dictionary=b.session._profile.duplicate(true)
	before.quest_auto_fee_lifecycle={"schema":1,"owner":{"profile_id":before.profile_id,"character_id":before.character_id},"current":{"run_id":RUN,"run_status":"active","purchase":{"state":"manual_only"}},"unresolved_attempt":{}}
	# Fixture installation, not an RPC or a claim that Start was tested here.
	b.session._profile=before.duplicate(true);b.last_saved_payload=JSON.stringify(before)
	put(b.save_path,JSON.stringify(before).to_utf8_buffer());put(b.save_path+".bak",JSON.stringify(before).to_utf8_buffer())
	b.quest_auto.identity.run_id=RUN;b.quest_auto.identity.step_id="fee:test";b.quest_auto.identity.revision=3
	b.quest_auto.running=true;b.quest_auto.quest_id=2;b.quest_auto.connection=71;b.quest_auto.client="fixture-device";b.quest_auto.phase="travel"
	b.quest_auto.strict_walk=true;b.quest_auto.internal=true
	var marker:Dictionary={"quest_auto":{"identity":{"run_id":RUN,"step_id":"fee:test","revision":3}},"fee_attempt_binding":{"owner":{"profile_id":before.profile_id,"character_id":before.character_id},"run_id":RUN}}
	var bytes:PackedByteArray=JSON.stringify(JSON.from_native(marker)).to_utf8_buffer()
	put(b._resume_file(),bytes)
	b.session.writes=0
	print("B3C BEGIN fixture=%d tag=%s path=%s"%[fixtures,tag,b.save_path])
	return {"hub":hub,"b":b,"a":a.entry,"z":z.entry,"before":before,"target":target,"serial":b.quest_save_serial,"marker":marker,"side":bytes,"token":login.token,"binding":b._fee_bindings[71],"accounts":hub.accounts.data.duplicate(true),"path":b.save_path,"target_path":hub.accounts.save_path(z.entry)}
func complete(c:Dictionary)->void:
	loads+=c.hub.actual_loads
	check(image(c.hub.accounts.path)=={"exists":true,"bytes":JSON.stringify(c.hub.accounts.data,"  ").to_utf8_buffer()},"complete account disk equals retained actual token table")
	check(c.b._fee_start_intent._live.is_empty(),"never minted purchase/Start permission")
	for b in c.hub.backends.values():SaveLock.release(b.save_path)
	c.hub.free()
	print("B3C END fixture=%d path=%s checks=%d failures=%d"%[fixtures,c.path,checks,failures])
func finish(name:String)->void:
	print("%s SUMMARY: %d checks, %d failures; %d fixtures, %d real loads, 0 Wait"%[name,checks,failures,fixtures,loads])
	for path:String in paths:print("RETAINED "+path)
	quit(0 if failures==0 else 1)
