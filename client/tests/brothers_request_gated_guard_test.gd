extends SceneTree
## UNRUN. Real save seam; route setup uses existing original ordinary portal driver.
const B=preload("res://tests/support/brothers_request_fault_backend.gd")
const ParentRouter=preload("res://tests/support/brothers_request_parent_original.gd")
const ParentRunner=preload("res://tests/support/brothers_request_parent_runner.gd")
const Travel=preload("res://tests/support/water_route_driver.gd")
const Fixture=preload("res://tests/support/brothers_request_fixture.gd")
const Diff=preload("res://tests/support/brothers_request_compare.gd")
const Brothers=preload("res://server/quest_auto_brothers_plan.gd")
const Auto=preload("res://server/quest_auto.gd")
const Identity=preload("res://server/quest_auto_state.gd")
const PEER:int=182828
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
	b.save_path="user://brothers6d-%02d-%s.json"%[fixtures,tag]
	b.fee_attach(PEER)
	if parent:
		b.original_quests=ParentRouter.new();b.original_quests.catalog=b.quest_catalog
	if seed.is_empty():
		b.session._profile.player.level=31
		b.session._profile.player.gold=1234
		b.session._profile.no_random_encounters=true
		if not check(b.session.gm_grant_pet(74),tag+": real pet birth fixture with real UID"):b.free();return null
	else:b.session._profile=seed.duplicate(true)
	if not check(b.save(),tag+": genuine baseline disk save"):b.free();return null
	if not check(Fixture.enter(b),tag+": actual original portal establishes arrival; public entrance placement disclosed"):b.free();return null
	if not check(Travel.walk_near(b,b.original_quests.npc_by_id(Brothers.REQUEST_NPC),[31701]),tag+": real first-floor steps to original talk range"):b.free();return null

	return b
func expected_request(before:Dictionary)->Dictionary:
	var result:Dictionary=before.duplicate(true)
	result.original_events.now[0]=int(result.original_events.now[0]) | (1 << 28)
	return result
func start_page(b)->bool:
	var reply:Dictionary=b.handle({"type":"quest_auto_start","quest_id":18,"client":"brothers6d","_quest_connection":PEER})
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
	var private_call:Dictionary=b._begin_brothers_request_call(b.quest_auto)
	if not check(not private_call.is_empty(),"real started runner yields exact transient guard"):b.free();return
	b.fault=mode;b.armed=true
	# The exact production choose/save path, separated from outer Stop saves so
	# failure-before/after disk observations are not overwritten by cleanup.
	var reply:Dictionary=b.original_quests.choose(b,token,"yes")
	b._end_brothers_request_call(private_call)
	var written:bool=mode!="before"
	var expected_disks:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial[0],{"exists":false,"bytes":PackedByteArray()}] if written else initial
	check(b.writes==1 and b.actual_save==written,"one actual writer result independent of wrapper return")
	check(reply.get("ok",false)==(mode=="success"),"original true/false wrapper semantics")
	check(Diff.first(b.session._profile,expected if mode=="success" else before).is_empty(),"independent entire original success/rollback profile including all pets/gold/UID")
	check(b.disk_rows()==expected_disks,"independent main/bak/tmp actual bytes, including false-after disk commit")
	check(b.last_saved_payload==(JSON.stringify(expected) if written else cache) and b.quest_save_serial==serial+(1 if written else 0),"real cache/serial do not pretend rollback of written disk")
	check(b._brothers_request_call.is_empty(),"self-owned transient guard removed")
	check(not Brothers.Rules.flag(b.session._profile,"now",31) and not Brothers.Rules.flag(b.session._profile,"ended",28),"no follow-up REQUEST31/END28 flags")
	if mode=="success":
		var closed:Dictionary=b.original_quests.choose(b,b.original_quests.pending.token,"ok")
		check(closed.get("ok",false),"close real original end page")
		var replay:Dictionary=b.original_quests.choose(b,token,"yes")
		check(not replay.get("ok",false) and b.writes==1 and b.disk_rows()==expected_disks,"consumed token replay cannot save again")
		b.quest_auto.phase="travel"
		b.quest_auto.internal=false
		b.quest_auto.tick(b,0.21)
		check(not b.quest_auto.running and b.quest_auto.phase=="manual","actual runner stops at manual first-request boundary")
		check(b.session._profile==expected and b.disk_rows()==expected_disks,"manual boundary does not consume pets/money/items or change disks")
		var denied:Dictionary=b.handle({"type":"quest_auto_start","quest_id":18,"client":"brothers6d","_quest_connection":PEER})
		check(not denied.get("ok",false) and b.session._profile==expected,"repeat Start after NOW28 cannot select answers/rewards/second request")
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
	check(Diff.first(b.whole_state(),b.at_return).is_empty(),"whole successor profile/session pending/arrival/native page/cache/serial/disks/run/binding untouched after callback")
	if mode.begins_with("registration_"):check(is_same(b._brothers_request_call,b.successor_call),"old end does not clear successor registration")
	else:check(b._brothers_request_call.is_empty(),"old end clears only its own registration")
	check(Diff.first(b.old_session._profile,expected).is_empty(),"old candidate remains where real original install put it; no invented rollback")
	var expected_disks:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},initial[0],{"exists":false,"bytes":PackedByteArray()}] if mode.ends_with("after") else initial
	check(b.disk_rows()==expected_disks,"old disk independently reflects actual before/after physical save")
	b.free()
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
		var page:Dictionary=b.original_quests.talk(b,Brothers.REQUEST_NPC)
		if not check(page.get("ok",false),"manual real talk"):live.free();parent.free();return
		if not check(b.original_quests.serial==page_serial+1 and page.has("dialogue") and token_matches(page.dialogue.get("token"),page_serial+1) and b.original_quests.pending.get("token")==page.dialogue.token,"each manual request has genuine typed token and matching private page serial"):live.free();parent.free();return
		var before:Dictionary=b.session._profile.duplicate(true)
		var expected:Dictionary=expected_request(before)
		var disks:Array=b.disk_rows();var cache:String=b.last_saved_payload;var serial:int=b.quest_save_serial
		b.fault=mode;b.armed=true
		var reply:Dictionary=b.original_quests.choose(b,page.dialogue.token,"yes")
		var wrote:bool=mode!="before"
		var disk_expected:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},disks[0],{"exists":false,"bytes":PackedByteArray()}] if wrote else disks
		check(Diff.first(b.session._profile,expected if mode=="success" else before).is_empty() and b.disk_rows()==disk_expected,"manual independent full profile/three-disk oracle")
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
	var difference:Dictionary=Diff.first(outputs[0],outputs[1],"outputs")
	if not difference.is_empty():Diff.print_first(difference)
	check(difference.is_empty(),"gatefalse choose/transact complete parent-function comparison in candidate environment")
	live.free();parent.free()

func admission()->void:
	# Every negative case first earns genuine portal authority; no interior placement grants proof.
	for mode in ["gatefalse","job19","level","wrong_map","no_arrival","reset_arrival","now28","end28","no_binding","source_drift","duplicate","binding_during_start"]:
		fixtures+=1
		var b=B.new();b.set_process(false);b.enabled=mode!="gatefalse"
		b.session._profile.player.level=30 if mode=="level" else 31
		b.session._profile.no_random_encounters=true
		if not check(Fixture.enter(b),"negative fixture starts with real portal authority"):b.free();return
		if mode=="wrong_map":b.automation.position_changed(300,Vector2i(384,432),true,"project")
		if mode=="no_arrival":
			b.automation.position_changed(300,Vector2i(384,432),true,"project")
			b.automation.position_changed(31701,Vector2i(29,43),true,"project")
		if mode=="reset_arrival":b.quest_arrival.reset()
		if mode=="now28":Brothers.Rules.set_flag(b.session._profile,"now",28,true)
		if mode=="end28":Brothers.Rules.set_flag(b.session._profile,"ended",28,true)
		b.save_path="user://brothers6d-admission-%s.json"%mode
		b.fee_attach(PEER)
		if mode=="no_binding":b.fee_detach(PEER)
		if mode=="binding_during_start":
			b.quest_visit_guard=func()->String:
				b._fee_bindings[PEER]=RefCounted.new()
				return ""
		if mode=="source_drift":
			for npc in b.quest_catalog.npcs:
				if npc.id==Brothers.REQUEST_NPC:npc.branches[0].condition="LV>29"
		if not check(b.save(),"admission baseline"):b.free();return
		var before:Dictionary=b.session.snapshot();var disks:Array=b.disk_rows();var cache:String=b.last_saved_payload;var serial:int=b.quest_save_serial
		var arrival:Dictionary=b.arrival_state()
		var cmd:Dictionary={"type":"quest_auto_start","quest_id":19 if mode=="job19" else 18,"client":"brothers6d","_quest_connection":PEER}
		var expected:Dictionary={}
		if mode=="gatefalse":
			expected=ParentRunner.new().prepare_start(b,cmd)
			# Fixed parent Backend._handle public rejected envelope; body locked in freeze report.
			expected.seq=0;expected.type="rejected"
		var reply:Dictionary=b.handle(cmd)
		if mode=="duplicate":
			check(reply.get("ok",false),"first Start admitted with real parent preconditions")
			var checkpoint:Dictionary=b.quest_auto.identity.checkpoint()
			reply=b.handle(cmd)
			check(not reply.get("ok",false) and b.quest_auto.identity.checkpoint()==checkpoint,"duplicate running Start cannot install new run")
		else:check(not reply.get("ok",false),"exact negative admission "+mode)
		if mode=="gatefalse":check(reply==expected and b._capabilities()=={"quest_loot_enabled":b._quest_loot_public_enabled()},"gatefalse parent output and capabilities exactly unchanged")
		check(Diff.first(b.session._profile,before).is_empty() and b.disk_rows()==disks and b.last_saved_payload==cache and b.quest_save_serial==serial,"admission never changes full profile/UID/money/disk/cache/serial")
		check(Diff.first(b.arrival_state(),arrival).is_empty(),"admission never manufactures or refreshes complete arrival state")
		check(b._required_fee_runner_authority==null and b._required_fee_runner._cap.is_empty(),"no D issuer or authority preinstalled")
		if mode=="source_drift":
			for npc in b.quest_catalog.npcs:
				if npc.id==Brothers.REQUEST_NPC:npc.branches[0].condition="LV>30"
		b.free()
		if failures:return
func scope_isolation()->void:
	var b=setup("scope-isolation")
	if b==null:return
	if not start_page(b):b.free();return
	b.quest_auto.internal=true
	var frame:Dictionary=b._begin_brothers_request_call(b.quest_auto)
	if not check(not frame.is_empty(),"genuine Brothers call exists for negative cross-scope cases"):b.free();return
	b.foreign_enabled=true
	var baseline:Dictionary=b.whole_state()
	check(b._begin_doctor_request_call(b.quest_auto).is_empty() and b._begin_saton_request_call(b.quest_auto).is_empty() and b._begin_munde_request_call(b.quest_auto).is_empty(),"Brothers live run cannot mint Doctor/Saton/Munde call")
	check(not b._doctor_request_call_live(frame) and not b._saton_request_call_live(frame) and not b._munde_request_call_live(frame),"Brothers frame not accepted as another private call")
	b._end_doctor_request_call(frame);b._end_saton_request_call(frame);b._end_munde_request_call(frame)
	check(is_same(frame,b._brothers_request_call) and b.whole_state()==baseline,"wrong module end does not consume Brothers authority or alter full state")
	b._end_brothers_request_call(frame)
	b.free()
func before_install()->void:
	var b=setup("before-install")
	if b==null:return
	if not start_page(b):b.free();return
	# Isolated transaction fixture enters the runner internal lane after a real Start/talk.
	b.quest_auto.internal=true
	var private_call:Dictionary=b._begin_brothers_request_call(b.quest_auto)
	if not check(not private_call.is_empty(),"genuine call before native candidate construction"):b.free();return
	check(not b._brothers_request_call_live({"ok":true}) and not b._brothers_request_install({"ok":true},b.session._profile.duplicate(true)),"public ok cannot manufacture private request authority")
	b._end_brothers_request_call({"ok":true})
	check(is_same(b._brothers_request_call,private_call),"wrong end cannot consume genuine call")
	b.session._profile.player.gold+=1
	var native:Dictionary=b.session._profile.duplicate(true)
	var disks:Array=b.disk_rows();var cache:String=b.last_saved_payload;var serial:int=b.quest_save_serial
	var arrival:Dictionary=b.arrival_state()
	b.fault="success";b.armed=true
	var reply:Dictionary=b.original_quests.choose(b,b.original_quests.pending.token,"yes")
	b._end_brothers_request_call(private_call)
	check(not reply.get("ok",false) and b.writes==0,"same-owner native drift rejects before installation and writer")
	check(b.session._profile==native and b.disk_rows()==disks and b.last_saved_payload==cache and b.quest_save_serial==serial and b.arrival_state()==arrival,"entire drifted native profile/arrival/disks/cache/serial retained; no old candidate install")
	b.free()
func arrival_lifetime(mode:String)->void:
	var b=setup("arrival-lifetime-"+mode)
	if b==null:return
	if not start_page(b):b.free();return
	if mode=="replace":b.quest_arrival=preload("res://server/quest_legitimate_arrival.gd").new()
	else:b.quest_arrival.reset()
	var before:Dictionary=b.whole_state()
	b.quest_auto.tick(b,0.21)
	check(not b.quest_auto.running,"next tick revokes stale arrival execution")
	check(Diff.first(b.session._profile,before.profile).is_empty() and b.disk_rows()==before.disks and b.last_saved_payload==before.cache and b.quest_save_serial==before.serial and Diff.first(b.arrival_state(),before.arrival).is_empty(),"revocation keeps entire profile/disks/cache/serial/arrival without synthetic proof")
	b.free()
func run()->void:
	admission()
	if failures:finish();return
	for mode in ["reset","replace"]:
		arrival_lifetime(mode)
		if failures:finish();return
	scope_isolation()
	if failures:finish();return
	before_install()
	if failures:finish();return
	for mode in ["success","before","after"]:
		isolated_transaction(mode)
		if failures:finish();return
	for mode in ["session_before","session_after","run_before","run_after","binding_before","binding_after","registration_after","arrival_before","arrival_after"]:
		successor(mode)
		if failures:finish();return
	for mode in ["success","before","after"]:
		manual_pair(mode)
		if failures:finish();return
	manual_pair("success",true)
	finish()
func finish()->void:
	print("BROTHERS 6D GUARD: %d checks; %d failures; %d backend fixtures; 0 loads; 0 Wait"%[checks,failures,fixtures])
	quit(1 if failures else 0)
