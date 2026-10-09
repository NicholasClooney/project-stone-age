extends SceneTree
## UNRUN. Real save seam; route setup uses existing original CaveRoute driver.
const B=preload("res://tests/support/doctor_request_fault_backend.gd")
const ParentRouter=preload("res://tests/support/doctor_request_parent_original.gd")
const ParentRunner=preload("res://tests/support/doctor_request_parent_runner.gd")
const Cave=preload("res://tests/support/legacy_cave_route.gd")
const Doctor=preload("res://server/quest_auto_doctor_plan.gd")
const Auto=preload("res://server/quest_auto.gd")
const Identity=preload("res://server/quest_auto_state.gd")
const PEER:int=61515
var checks:int=0
var failures:int=0
var fixtures:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->bool:
	checks+=1
	if not value:
		failures+=1;push_error(label)
	return value
func setup(tag:String,enabled:bool=true,parent:bool=false,seed:Dictionary={}):
	fixtures+=1
	var b=B.new()
	b.set_process(false);b.enabled=enabled
	b.save_path="user://doctor6a-%02d-%s.json"%[fixtures,tag]
	b.fee_attach(PEER)
	if parent:
		b.original_quests=ParentRouter.new();b.original_quests.catalog=b.quest_catalog
	if seed.is_empty():
		b.session._profile.player.level=10
		b.session._profile.player.gold=1234
		b.session._profile.no_random_encounters=true
		if not check(b.session.gm_grant_pet(74),tag+": real pet birth fixture with real UID"):b.free();return null
	else:b.session._profile=seed.duplicate(true)
	if not check(b.save(),tag+": genuine baseline disk save"):b.free();return null
	if not check(Cave.approach(b,b.original_quests.npc_by_id(Doctor.DOCTOR)).get("ok",false),tag+": genuine original six-floor approach; no fabricated arrival"):b.free();return null
	return b
func expected_request(before:Dictionary)->Dictionary:
	var result:Dictionary=before.duplicate(true)
	result.original_events.now[0]=int(result.original_events.now[0]) | (1 << 15)
	return result
func start_page(b)->bool:
	var reply:Dictionary=b.handle({"type":"quest_auto_start","quest_id":6,"client":"doctor6a","_quest_connection":PEER})
	if not check(reply.get("ok",false),"gated real product Start"):return false
	b.quest_auto.tick(b,0.21)
	return check(b.quest_auto.phase=="strict_dialogue" and b.original_quests.pending.get("phase")=="REQUEST","real product talk opens original REQUEST page")
func isolated_transaction(mode:String)->void:
	var b=setup(mode)
	if b==null:return
	if not start_page(b):b.free();return
	var before:Dictionary=b.session._profile.duplicate(true)
	var initial:Array=b.disk_rows()
	var cache:String=b.last_saved_payload
	var serial:int=b.quest_save_serial
	var expected:Dictionary=expected_request(before)
	var token:String=b.original_quests.pending.token
	# Isolated transaction fixture enters the runner internal lane after a real Start/talk.
	b.quest_auto.internal=true
	var private_call:Dictionary=b._begin_doctor_request_call(b.quest_auto)
	if not check(not private_call.is_empty(),"real started runner yields exact transient guard"):b.free();return
	b.fault=mode;b.armed=true
	# The exact production choose/save path, separated from outer Stop saves so
	# failure-before/after disk observations are not overwritten by cleanup.
	var reply:Dictionary=b.original_quests.choose(b,token,"yes")
	b._end_doctor_request_call(private_call)
	var written:bool=mode!="before"
	var expected_disks:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial[0],{"exists":false,"bytes":PackedByteArray()}] if written else initial
	check(b.writes==1 and b.actual_save==written,"one actual writer result independent of wrapper return")
	check(reply.get("ok",false)==(mode=="success"),"original true/false wrapper semantics")
	check(b.session._profile==(expected if mode=="success" else before),"independent entire original success/rollback profile including all pets/gold/UID")
	check(b.disk_rows()==expected_disks,"independent main/bak/tmp actual bytes, including false-after disk commit")
	check(b.last_saved_payload==(JSON.stringify(expected) if written else cache) and b.quest_save_serial==serial+(1 if written else 0),"real cache/serial do not pretend rollback of written disk")
	check(b._doctor_request_call.is_empty(),"self-owned transient guard removed")
	if mode=="success":
		var closed:Dictionary=b.original_quests.choose(b,b.original_quests.pending.token,"ok")
		check(closed.get("ok",false),"close real original end page")
		var replay:Dictionary=b.original_quests.choose(b,token,"yes")
		check(not replay.get("ok",false) and b.writes==1 and b.disk_rows()==expected_disks,"consumed token replay cannot save again")
		b.quest_auto.phase="travel"
		b.quest_auto.internal=false
		b.quest_auto.tick(b,0.21)
		check(not b.quest_auto.running and b.quest_auto.phase=="manual","actual runner stops at manual UID boundary")
		check(b.session._profile==expected and b.disk_rows()==expected_disks,"manual boundary does not consume pets/money/items or change disks")
		var denied:Dictionary=b.handle({"type":"quest_auto_start","quest_id":6,"client":"doctor6a","_quest_connection":PEER})
		check(not denied.get("ok",false) and b.session._profile==expected,"repeat Start after NOW15 cannot select pet/second request")
	b.free()
func successor(mode:String)->void:
	var b=setup(mode)
	if b==null:return
	if not start_page(b):b.free();return
	var expected:Dictionary=expected_request(b.session._profile)
	var initial:Array=b.disk_rows()
	b.fault=mode;b.armed=true
	b.quest_auto.tick(b,0.21) # Actual product caller, including its return path.
	check(b.writes==1,"successor injection reached real save seam exactly once")
	check(b.whole_state()==b.at_return,"whole successor profile/session pending/arrival/native page/cache/serial/disks/run/binding untouched after callback")
	if mode.begins_with("registration_"):check(is_same(b._doctor_request_call,b.successor_call),"old end does not clear successor registration")
	else:check(b._doctor_request_call.is_empty(),"old end clears only its own registration")
	check(b.old_session._profile==expected,"old candidate remains where real original install put it; no invented rollback")
	var expected_disks:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial[0],{"exists":false,"bytes":PackedByteArray()}] if mode.ends_with("after") else initial
	check(b.disk_rows()==expected_disks,"old disk independently reflects actual before/after physical save")
	b.free()
func first_difference(a:Variant,b:Variant,path:String)->Dictionary:
	if typeof(a)!=typeof(b):return {"path":path,"left_type":typeof(a),"right_type":typeof(b),"left":a,"right":b}
	if a is Dictionary:
		var left_keys:Array=a.keys();var right_keys:Array=b.keys()
		for key in left_keys:
			var found:bool=false
			for other in right_keys:
				if typeof(key)==typeof(other) and key==other:found=true;break
			if not found:return {"path":path+".<key>","left_type":typeof(key),"right_type":-1,"left":key,"right":"MISSING_TYPED_KEY"}
			var child:Dictionary=first_difference(a[key],b[key],path+"."+str(key))
			if not child.is_empty():return child
		for key in right_keys:
			var found:bool=false
			for other in left_keys:
				if typeof(key)==typeof(other) and key==other:found=true;break
			if not found:return {"path":path+".<key>","left_type":-1,"right_type":typeof(key),"left":"MISSING_TYPED_KEY","right":key}
	elif a is Array:
		if a.size()!=b.size():return {"path":path+".size","left_type":TYPE_INT,"right_type":TYPE_INT,"left":a.size(),"right":b.size()}
		for index in range(a.size()):
			var child:Dictionary=first_difference(a[index],b[index],path+"["+str(index)+"]")
			if not child.is_empty():return child
	if a!=b:return {"path":path,"left_type":typeof(a),"right_type":typeof(b),"left":a,"right":b}
	return {}
func token_matches(value:Variant,serial:int)->bool:
	if not value is String:return false
	var parts:PackedStringArray=value.split("-")
	if parts.size()!=2:return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():return false
	return parts[0].to_int()>0 and str(parts[0].to_int())==parts[0] and parts[1]==str(serial)
func manual_pair(mode:String,gate:bool=false)->void:
	var live=setup("manual-live-"+mode,gate)
	if live==null:return
	var parent=setup("manual-parent-"+mode,false,true,live.session._profile)
	if parent==null:live.free();return
	var outputs:Array=[]
	for b in [live,parent]:
		var page_serial:int=b.original_quests.serial
		var page:Dictionary=b.original_quests.talk(b,Doctor.DOCTOR)
		if not check(page.get("ok",false),"manual real talk"):live.free();parent.free();return
		if not check(b.original_quests.serial==page_serial+1 and page.has("dialogue") and token_matches(page.dialogue.get("token"),page_serial+1) and b.original_quests.pending.get("token")==page.dialogue.token,"each manual request has genuine typed token and matching private page serial"):live.free();parent.free();return
		var before:Dictionary=b.session._profile.duplicate(true)
		var expected:Dictionary=expected_request(before)
		var disks:Array=b.disk_rows();var cache:String=b.last_saved_payload;var serial:int=b.quest_save_serial
		b.fault=mode;b.armed=true
		var reply:Dictionary=b.original_quests.choose(b,page.dialogue.token,"yes")
		var wrote:bool=mode!="before"
		var disk_expected:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},disks[0],{"exists":false,"bytes":PackedByteArray()}] if wrote else disks
		check(b.session._profile==(expected if mode=="success" else before) and b.disk_rows()==disk_expected,"manual independent full profile/three-disk oracle")
		check(b.last_saved_payload==(JSON.stringify(expected) if wrote else cache) and b.quest_save_serial==serial+(1 if wrote else 0),"manual native cache/serial original semantics")
		if failures:live.free();parent.free();return
		var compared_reply:Dictionary=reply.duplicate(true)
		var compared_pending:Dictionary=b.original_quests.pending.duplicate(true)
		if mode=="success":
			if not check(reply.get("ok",false) and reply.has("dialogue") and token_matches(reply.dialogue.get("token"),page_serial+2) and b.original_quests.serial==page_serial+2 and typeof(compared_pending.get("token"))==TYPE_STRING and compared_pending.token==reply.dialogue.token and reply.dialogue.token!=page.dialogue.token,"each new window token has incremented serial, exact pending link and differs from old request"):live.free();parent.free();return
			var before_replay:Dictionary=b.whole_state()
			var replay:Dictionary=b.original_quests.choose(b,page.dialogue.token,"yes")
			if not check(replay=={"ok":false,"reason":"对话已过期。"} and b.whole_state()==before_replay and b.original_quests.serial==page_serial+2,"old request token cannot consume new window or mutate complete state/disks"):live.free();parent.free();return
			# Only already-proven associated tokens in comparison copies are mapped.
			compared_reply.dialogue.token="<verified-associated-window-token>"
			compared_pending.token="<verified-associated-window-token>"
		else:
			if not check(not reply.has("dialogue") and compared_pending.is_empty() and b.original_quests.serial==page_serial+1,"failed save creates no window and adds no synthetic token"):live.free();parent.free();return
		outputs.append({"reply":compared_reply,"profile":b.session._profile.duplicate(true),"pending":compared_pending,"disks":b.disk_rows(),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"cap":b._capabilities()})
	if outputs[0]!=outputs[1]:
		var difference:Dictionary=first_difference(outputs[0],outputs[1],"outputs")
		print("PAIR_DIAG mode=%s gate=%s path=%s"%[mode,str(gate),str(difference.get("path","UNKNOWN"))])
		print("PAIR_DIAG left_type=%s right_type=%s"%[str(difference.get("left_type","UNKNOWN")),str(difference.get("right_type","UNKNOWN"))])
		print("PAIR_DIAG left="+str(difference.get("left","UNKNOWN")).left(600))
		print("PAIR_DIAG right="+str(difference.get("right","UNKNOWN")).left(600))
		check(outputs[0]==outputs[1],"gatefalse choose/transact complete parent-function comparison in candidate environment")
		live.free();parent.free();return
	check(outputs[0]==outputs[1],"gatefalse choose/transact complete parent-function comparison in candidate environment")
	live.free();parent.free()
func admission()->void:
	# No route work needed: fresh full profiles and actual save baseline only.
	for mode in ["gatefalse","job7","level","no_binding","source_drift","duplicate","binding_during_start"]:
		fixtures+=1
		var b=B.new();b.set_process(false);b.enabled=mode!="gatefalse"
		b.session._profile.player.level=9 if mode=="level" else 10
		b.save_path="user://doctor6a-admission-%s.json"%mode
		b.fee_attach(PEER)
		if mode=="no_binding":b.fee_detach(PEER)
		if mode=="binding_during_start":
			b.quest_visit_guard=func()->String:
				b._fee_bindings[PEER]=RefCounted.new()
				return ""
		if mode=="source_drift":
			for npc in b.quest_catalog.npcs:
				if npc.id==Doctor.DOCTOR:npc.branches[2].condition="LV>8"
		if not check(b.save(),"admission baseline"):b.free();return
		var before:Dictionary=b.session.snapshot();var disks:Array=b.disk_rows();var cache:String=b.last_saved_payload;var serial:int=b.quest_save_serial
		var cmd:Dictionary={"type":"quest_auto_start","quest_id":7 if mode=="job7" else 6,"client":"doctor6a","_quest_connection":PEER}
		var expected:Dictionary={}
		if mode=="gatefalse":
			expected=ParentRunner.new().prepare_start(b,cmd)
			# Fixed parent Backend._handle:1352-1353 public envelope.
			expected.seq=0;expected.type="rejected"
		var reply:Dictionary=b.handle(cmd)
		if mode=="duplicate":
			check(reply.get("ok",false),"first Start admitted with real parent preconditions")
			var checkpoint:Dictionary=b.quest_auto.identity.checkpoint()
			reply=b.handle(cmd)
			check(not reply.get("ok",false) and b.quest_auto.identity.checkpoint()==checkpoint,"duplicate running Start cannot install new run")
		else:check(not reply.get("ok",false),"exact negative admission "+mode)
		if mode=="gatefalse":check(reply==expected and b._capabilities()=={"quest_loot_enabled":b._quest_loot_public_enabled()},"gatefalse parent output and capabilities exactly unchanged")
		check(b.session._profile==before and b.disk_rows()==disks and b.last_saved_payload==cache and b.quest_save_serial==serial,"admission never changes full profile/UID/money/disk/cache/serial")
		check(b._required_fee_runner_authority==null and b._required_fee_runner._cap.is_empty(),"no D issuer or authority preinstalled")
		if mode=="source_drift":
			for npc in b.quest_catalog.npcs:
				if npc.id==Doctor.DOCTOR:npc.branches[2].condition="LV>9"
		b.free()
		if failures:return
func before_install()->void:
	var b=setup("before-install")
	if b==null:return
	if not start_page(b):b.free();return
	# Isolated transaction fixture enters the runner internal lane after a real Start/talk.
	b.quest_auto.internal=true
	var private_call:Dictionary=b._begin_doctor_request_call(b.quest_auto)
	if not check(not private_call.is_empty(),"genuine call before native candidate construction"):b.free();return
	check(not b._doctor_request_call_live({"ok":true}) and not b._doctor_request_install({"ok":true},b.session._profile.duplicate(true)),"public ok cannot manufacture private request authority")
	b._end_doctor_request_call({"ok":true})
	check(is_same(b._doctor_request_call,private_call),"wrong end cannot consume genuine call")
	b.session._profile.player.gold+=1
	var native:Dictionary=b.session._profile.duplicate(true)
	var disks:Array=b.disk_rows();var cache:String=b.last_saved_payload;var serial:int=b.quest_save_serial
	var arrival:Dictionary=b.arrival_state()
	b.fault="success";b.armed=true
	var reply:Dictionary=b.original_quests.choose(b,b.original_quests.pending.token,"yes")
	b._end_doctor_request_call(private_call)
	check(not reply.get("ok",false) and b.writes==0,"same-owner native drift rejects before installation and writer")
	check(b.session._profile==native and b.disk_rows()==disks and b.last_saved_payload==cache and b.quest_save_serial==serial and b.arrival_state()==arrival,"entire drifted native profile/arrival/disks/cache/serial retained; no old candidate install")
	b.free()
func run()->void:
	admission()
	if failures:finish();return
	before_install()
	if failures:finish();return
	for mode in ["success","before","after"]:
		isolated_transaction(mode)
		if failures:finish();return
	for mode in ["session_before","session_after","run_before","run_after","binding_before","binding_after","registration_after"]:
		successor(mode)
		if failures:finish();return
	for mode in ["success","before","after"]:
		manual_pair(mode)
		if failures:finish();return
	manual_pair("success",true)
	finish()
func finish()->void:
	print("DOCTOR 6A GUARD: %d checks; %d failures; %d backend fixtures; 0 loads; 0 Wait"%[checks,failures,fixtures])
	quit(1 if failures else 0)
