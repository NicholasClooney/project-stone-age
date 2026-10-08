extends "res://tests/support/fee_departure_harness.gd"
## UNRUN: real Accounts/login/logout/switch and actual writer disk oracles; no WS.
func run()->void:
	for kind:String in ["logout","switch","switch_distinct","busy_stop","busy_attempt","busy_close","busy_sidecar","w1_before","w1_after","w2_before","w2_after","unknown","foreign","mixed","residual","residual_stringname","remove_before","remove_after","write_before","target_failure","warm_retry","warm_successor","ordinary_save","closed_attempting","gate_false"]:
		var c:Dictionary=fixture(kind,kind!="gate_false",kind=="switch_distinct")
		if c.is_empty():quit(1);return
		var b=c.b;var hub=c.hub
		# No-pending entry keeps the exact original already-running rejection.
		var entry_disks:Array=disks(c.path)
		var entry_side:Array=side(b)
		check(not b._fee_cold_lifecycle.protects_resume(b),"fixture begins without departure pending")
		for enabled:bool in [false,true]:
			b.gate=enabled
			check(b._cmd_quest_auto_start({"quest_id":2})=={"ok":false,"reason":"自动任务已在运行。"},"no pending retains parent Start return under both gates")
			check(b.session._profile==c.before and b.last_saved_payload==JSON.stringify(c.before) and b.quest_save_serial==c.serial and b.session.writes==0,"no pending full profile/cache/serial/B1 zero writes")
			check(disks(c.path)==entry_disks and side(b)==entry_side and b._fee_start_intent._live.is_empty(),"no pending whole disks and no private Start grant")
		b.gate=kind!="gate_false"
		var closed:Dictionary=c.before.duplicate(true)
		closed.quest_auto_fee_lifecycle.current.run_status="closed"
		var held:RefCounted=RefCounted.new()
		match kind:
			"busy_stop":b._quest_auto_stop_operation_call=held;b._quest_auto_stop_operation_owner=b.quest_auto
			"busy_attempt","warm_retry","warm_successor","ordinary_save":b._fee_attempt_writer_call=held
			"busy_close":b._fee_attempt_close_call=held
			"busy_sidecar":b._fee_resume_sidecar_call=held
			"w1_before","w1_after":b.session.fail_write=1;b.session.after_false=kind=="w1_after"
			"w2_before","w2_after":b.session.fail_write=2;b.session.after_false=kind=="w2_after"
			"unknown":b.session.unknown=true
			"foreign":c.marker.quest_auto.identity.run_id=OTHER
			"mixed":c.marker.quest_auto.identity.step_id="jewels:hunt:2760"
			"residual","write_before":c.marker["sentinel"]={"keep":[1,"foreign"]}
			"residual_stringname":c.marker[&"sentinel"]={"keep":[1,"foreign"]}
			"target_failure":put(c.target_path,"bad-profile".to_utf8_buffer())
			"closed_attempting":
				c.before.quest_auto_fee_lifecycle.current.run_status="closed"
				c.before.quest_auto_fee_lifecycle.current.purchase={"state":"attempting","attempt_id":"44444444444444444444444444444444","source_id":"lobby","offer_id":"ticket","item_id":2600,"amount":100,"balance_before":500}
				b.session._profile=c.before.duplicate(true);b.last_saved_payload=JSON.stringify(c.before);closed=c.before.duplicate(true)
				put(c.path,JSON.stringify(c.before).to_utf8_buffer());put(c.path+".bak",JSON.stringify(c.before).to_utf8_buffer())
		if kind in ["remove_before","remove_after","write_before"]:b.side_fault=kind
		if kind in ["foreign","mixed","residual","residual_stringname","write_before"]:
			c.side=JSON.stringify(JSON.from_native(c.marker)).to_utf8_buffer();put(b._resume_file(),c.side)
		if kind=="busy_stop":
			b.quest_auto.source_frame=preload("res://server/quest_auto_source_frame.gd").new()
			b.quest_auto.source_frame.produced={"owned-page":true};b.original_quests.pending={"token":"owned-page","sentinel":7}
		if kind=="busy_attempt":b.original_quests.pending={"token":"foreign-page","sentinel":9}
		var initial_battle:Dictionary=b.battle.snapshot().duplicate(true)
		var target_initial:Dictionary=image(c.target_path)
		var reply:Dictionary=hub.handle(71,{"type":"login","name":"New","pin":"4321"} if kind in ["switch","switch_distinct","target_failure"] else {"type":"logout"})
		if kind=="target_failure":
			check(not truth(reply.get("ok")) and hub.profile_of(71)==c.a.id and is_same(b._fee_bindings.get(71),c.binding),"failed target keeps original binding")
			check(b.quest_auto.running and b.session._profile==c.before and disks(c.path)==[row(c.before),row(c.before),{"exists":false}],"failed target keeps complete old profile and execution")
			check(side(b)==[{"exists":true,"bytes":c.side},{"exists":false}] and image(c.target_path)==target_initial,"failed target keeps all disk evidence")
			var failed_accounts:Dictionary=c.accounts.duplicate(true)
			for entry:Dictionary in failed_accounts.profiles:
				if entry.id==c.z.id:entry.tokens.append(str(hub.accounts.issued[-1].token).sha256_text())
			check(hub.accounts.data==failed_accounts and truth(hub.accounts.verify_token("Old",c.token).get("ok")),"failed target preserves old token, only original target token issue remains")
			check(image(c.target_path+".bak")=={"exists":false} and image(c.target_path+".tmp")=={"exists":false},"failed target backup/tmp untouched")
			complete(c);continue
		check(truth(reply.get("ok")),"fee failure never rejects normal departure")
		check(hub.profile_of(71)==(c.z.id if kind in ["switch","switch_distinct"] else "") and not b._fee_bindings.has(71),"old connection/binding revoked, target mapping exact")
		check(not b.quest_auto.running,"busy and failed Stop cannot retain quest execution")
		if kind=="busy_stop":check(is_same(b._quest_auto_stop_operation_call,held) and b.original_quests.pending.is_empty(),"held Stop claim preserved; only owned source page revoked")
		if kind=="busy_attempt":check(is_same(b._fee_attempt_writer_call,held) and b.original_quests.pending=={"token":"foreign-page","sentinel":9},"held attempt claim and foreign source page preserved")
		if kind=="busy_close":check(is_same(b._fee_attempt_close_call,held),"held close claim preserved")
		if kind=="busy_sidecar":check(is_same(b._fee_resume_sidecar_call,held),"held sidecar claim preserved")
		if kind=="gate_false":check(b.quest_auto.connection==71 and b.quest_auto.identity.revision==4 and b._fee_departure_pending.is_empty(),"disabled gate preserves original Stop/detach identity behavior")
		check(b.battle.snapshot()==initial_battle and b.session._pending.is_empty(),"no battle settlement or pending mutation")
		var changed:bool=kind not in ["busy_stop","busy_attempt","busy_close","busy_sidecar","w1_before","unknown","warm_retry","warm_successor","ordinary_save","closed_attempting"]
		var expected:Dictionary=closed if changed else c.before
		var backup:Dictionary=c.before if kind in ["w1_after","w2_before"] else expected
		check(b.session._profile==expected and b.last_saved_payload==JSON.stringify(expected),"independent complete live/cache including money UID")
		check(disks(c.path)==[row(expected),row(backup),{"exists":false}],"independent complete primary/backup/tmp")
		check(b.quest_save_serial==c.serial+int(changed),"one W1 install serial, not one per physical write")
		var side_expected:Array=[{"exists":true,"bytes":c.side},{"exists":false}]
		if kind in ["logout","switch","switch_distinct","remove_after","gate_false"]:side_expected=[{"exists":false},{"exists":false}]
		if kind=="residual":side_expected=[{"exists":true,"bytes":JSON.stringify(JSON.from_native({"sentinel":{"keep":[1,"foreign"]}})).to_utf8_buffer()},{"exists":false}]
		if kind=="residual_stringname":side_expected=[{"exists":true,"bytes":'{"args":["sn:sentinel",{"args":["s:keep",["i:1","s:foreign"]],"type":"Dictionary"}],"type":"Dictionary"}'.to_utf8_buffer()},{"exists":false}]
		var first_side:Array=side(b)
		if not side_fact(first_side,side_expected,kind+":first","independent full sidecar pair, including false-after actual absence"):quit(1);return
		var account_expected:Dictionary=c.accounts.duplicate(true)
		if kind not in ["switch","switch_distinct"]:
			for entry:Dictionary in account_expected.profiles:
				if entry.id==c.a.id:entry.tokens.erase(c.token.sha256_text())
		else:
			for entry:Dictionary in account_expected.profiles:
				if entry.id==c.z.id:entry.tokens.append(str(reply.token).sha256_text())
		check(hub.accounts.data==account_expected,"complete account token dictionary exact")
		check(image(hub.accounts.path).bytes.get_string_from_utf8()==JSON.stringify(account_expected,"  "),"actual full account token disk")
		if kind in ["switch","switch_distinct"]:
			check(hub.backend_of(71).session._profile==c.target and disks(c.target_path)==[row(c.target),{"exists":false},{"exists":false}],"new profile not polluted with old pending")
			check(hub.backend_of(71)._fee_departure_pending.is_empty(),"old pending never assigned to target")
			check(c.before.profile_id=="samgir-singleplayer-v1" and c.target.profile_id=="samgir-singleplayer-v1","valid profile identifier retained for both accounts")
			check(c.before.character_id=="100000" and c.target.character_id==("100005" if kind=="switch_distinct" else "100000"),"different legal character owner versus same-owner account isolation")
			check(not is_same(b,hub.backend_of(71)) and not is_same(b.session,hub.backend_of(71).session) and c.path!=c.target_path,"real target load uses independent backend/session/path")

		if kind in ["warm_retry","warm_successor","ordinary_save"]:
			b._fee_attempt_writer_call=null
			if kind=="ordinary_save":
				b.session._profile.player.gold+=7
				c.before.player.gold+=7;closed.player.gold+=7
				check(b.save(),"manual save allowed during protected sidecar")
				check(side(b)==side_expected,"manual save keeps sidecar")
			if kind=="warm_successor":b.quest_auto.identity=preload("res://server/quest_auto_state.gd").new();b.quest_auto.identity.run_id=RUN
			var warm:Dictionary=hub.handle(71,{"type":"login","name":"Old","pin":"1234"})
			check(truth(warm.get("ok")) and hub.factories==1,"warm reentry succeeds with no load")
			var warm_expected:Dictionary=c.before if kind=="warm_successor" else closed
			check(b.session._profile==warm_expected and disks(c.path)==[row(warm_expected),row(warm_expected),{"exists":false}],"warm retry real provenance; successor holds full old anchor")
			check(side(b)==(side_expected if kind=="warm_successor" else [{"exists":false},{"exists":false}]),"warm sidecar outcome independently observed")
		# No generic writer may remove a foreign/residual anchor after logout.
		if kind in ["foreign","mixed","residual","residual_stringname","unknown","busy_stop"]:
			if not side_fact(side(b),side_expected,kind+":before_generic","sidecar unchanged before generic writers"):quit(1);return
			b._keep_resume_file()
			if not side_fact(side(b),side_expected,kind+":after_periodic","real periodic writer preserves protected sidecar"):quit(1);return
			b.record_shutdown()
			if not side_fact(side(b),side_expected,kind+":after_shutdown","real periodic/shutdown writer preserves protected sidecar"):quit(1);return
			# A held real Stop slot supplies a deterministic original preflight oracle.
			# Parent 3ebd prepare_start first rejects this slot; B3c gate must be the only difference.
			var prior_claim:Variant=b._quest_auto_stop_operation_call
			var proof_claim:RefCounted=RefCounted.new()
			b._quest_auto_stop_operation_call=proof_claim
			var pending_disks:Array=disks(c.path)
			var pending_serial:int=b.quest_save_serial
			var pending_writes:int=b.session.writes
			b.gate=false
			check(b._cmd_quest_auto_start({"quest_id":2})=={"ok":false,"reason":"自动任务正在停止，请稍后重试。"},"gatefalse pending Start equals parent full return")
			check(b.session._profile==expected and b.last_saved_payload==JSON.stringify(expected) and b.quest_save_serial==pending_serial and b.session.writes==pending_writes,"gatefalse pending full profile/cache/serial/B1 unchanged")
			check(disks(c.path)==pending_disks and side(b)==side_expected and b._fee_start_intent._live.is_empty(),"gatefalse pending complete disk and no mint")
			b.gate=true
			check(b._cmd_quest_auto_start({"quest_id":2})=={"ok":false,"reason":"收费任务收尾尚未核实，请先重试收尾或重新载入角色。"},"enabled pending takes precedence with exact return")
			check(b.session._profile==expected and b.quest_save_serial==pending_serial and b.session.writes==pending_writes and disks(c.path)==pending_disks and side(b)==side_expected,"enabled pending complete zero-write oracle")
			check(is_same(b._quest_auto_stop_operation_call,proof_claim),"Start does not consume another Stop claim")
			b._quest_auto_stop_operation_call=prior_claim
			var refused:Dictionary=b._cmd_quest_auto_start({"type":"quest_auto_start","quest_id":2,"seq":42,"_quest_connection":71})
			check(refused.get("reason")=="收费任务收尾尚未核实，请先重试收尾或重新载入角色。","pending cannot be bypassed with a new fee run")
			check(side(b)==side_expected and b.session._profile==expected,"Start interlock changes no complete profile or marker")
		complete(c)
	if not start_matrix():quit(1);return
	check(fixtures==33 and loads==36,"exact fixture and true load budget")
	finish("FEE DEPARTURE HUB")

# The parent dispatch body is separately frozen in Probe.parent_start_3ebd.
# Profiles/disks are independently snapshotted before each call; no helper builds expected.
func start_matrix()->bool:
	var compared:Dictionary={}
	for mode:String in ["off_clear","off_pending","on_clear","on_pending"]:
		for parent:bool in [true,false]:
			var c:Dictionary=fixture("start-"+mode+("-parent" if parent else "-current"))
			if c.is_empty():return false
			var b=c.b;var hub=c.hub
			b.session._profile.player.level=35
			b.session._profile.no_random_encounters=true
			for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
			preload("res://server/original_equipment.gd").add(b.session._profile,2755)
			b.automation.position_changed(811,Vector2i(30,22),true)
			check(b.save(),"successful Start setup uses real ordinary save")
			var pending:bool=mode.ends_with("pending")
			if pending:
				var held:RefCounted=RefCounted.new()
				b._fee_attempt_writer_call=held
				var left:Dictionary=hub.handle(71,{"type":"logout"})
				check(truth(left.get("ok")) and not b.quest_auto.running,"real busy departure revokes execution and creates pending")
				var entered:Dictionary=hub.handle(71,{"type":"login","name":"Old","pin":"1234"})
				check(truth(entered.get("ok")) and is_same(hub.backend_of(71),b),"real warm login retains same backend and busy pending")
				if not truth(entered.get("ok")):complete(c);return false
				check(is_same(b._fee_attempt_writer_call,held),"held real claim remains intact through departure and warm retry")
				b._fee_attempt_writer_call=null
			else:
				b.quest_auto.running=false
			check(b._fee_cold_lifecycle.protects_resume(b)==pending,"pending exists only through actual departure provenance")
			check(not b._fee_start_intent_enabled(),"B3b Start intent gate stays disabled")
			check(truth(b.quest_auto.source_admission(b).get("ok")),"real original admission succeeds before dispatch")
			b.gate=mode.begins_with("on")
			var before:Dictionary=b.session._profile.duplicate(true)
			var expected_disks:Array=disks(c.path)
			var expected_side:Array=side(b)
			var cache:String=b.last_saved_payload
			var serial:int=b.quest_save_serial
			var writes:int=b.session.writes
			var b1:int=b.start_journal_frames
			var previous:Dictionary=b.quest_auto.identity.checkpoint()
			var binding:RefCounted=b._fee_bindings[71]
			var accounts:Dictionary=hub.accounts.data.duplicate(true)
			var account_disk:Dictionary=image(hub.accounts.path)
			var command:Dictionary={"type":"quest_auto_start","quest_id":2,"client":"explicit-test-device","_quest_connection":71,"seq":314}
			var reply:Dictionary=b.parent_start_3ebd(command) if parent else b._cmd_quest_auto_start(command)
			var refused:bool=mode=="on_pending" and not parent
			var expected:Dictionary={"ok":false,"reason":"收费任务收尾尚未核实，请先重试收尾或重新载入角色。"} if refused else {"ok":true}
			check(reply==expected,"independent complete successful/rejected Start return: "+mode)
			check(b.session._profile==before and b.last_saved_payload==cache and b.quest_save_serial==serial,"full profile including money/UID/cache/serial unchanged by legacy Start")
			check(b.session.writes==writes and b.start_journal_frames==b1 and b1==0,"zero physical writer and zero B1 frame attempt")
			check(disks(c.path)==expected_disks and side(b)==expected_side,"complete primary/backup/tmp and both sidecar images unchanged")
			check(hub.accounts.data==accounts and image(hub.accounts.path)==account_disk and is_same(b._fee_bindings[71],binding),"complete account token disk and binding preserved")
			check(b._fee_start_intent._live.is_empty(),"no private Start/purchase grant")
			if refused:
				check(not b.quest_auto.running and b.quest_auto.identity.checkpoint()==previous,"pending refusal does not install a runner")
			else:
				var identity:Dictionary=b.quest_auto.identity.checkpoint()
				check(b.quest_auto.running and b.quest_auto.quest_id==2 and b.quest_auto.connection==71 and b.quest_auto.client=="explicit-test-device" and b.quest_auto.phase=="travel" and not b.quest_auto.detached,"original successful runner installed")
				check(identity.run_id is String and identity.run_id.length()==32 and identity.run_id.is_valid_hex_number() and identity.run_id!=previous.run_id and identity.step_id=="" and identity.revision==previous.revision+1,"fresh random run follows original identity transition")
			var outcome:Dictionary={"reply":reply,"profile_unchanged":b.session._profile==before,"serial_delta":b.quest_save_serial-serial,"writes_delta":b.session.writes-writes,"b1_delta":b.start_journal_frames-b1,"running":b.quest_auto.running}
			if parent:compared[mode]=outcome
			elif mode!="on_pending":check(outcome==compared[mode],"complete dispatch outcome equals locked parent path: "+mode)
			complete(c)
	return true

# No I/O: caller supplies already-read complete two-file images.
# Exactly <=43 calls on a successful suite; each actual/expected image <=4096 bytes.
var side_fact_calls:=0
func side_fact(actual:Array,expected:Array,stage:String,label:String)->bool:
	side_fact_calls+=1
	check(side_fact_calls<=43 and actual.size()==2 and expected.size()==2,"bounded sidecar diagnostic count/shape")
	if side_fact_calls>43 or actual.size()!=2 or expected.size()!=2:return false
	var rendered:Array=[]
	for pair:Array in [actual,expected]:
		var encoded:Array=[]
		for image_value:Dictionary in pair:
			var bytes:PackedByteArray=image_value.get("bytes",PackedByteArray())
			check(bytes.size()<=4096,"sidecar diagnostic bytes within fixed cap")
			if bytes.size()>4096:
				print("B3C SIDE OVER_CAP stage=%s bytes=%d"%[stage,bytes.size()])
				return false
			encoded.append({"exists":image_value.get("exists",null),"unknown":image_value.get("unknown",false),"bytes_hex":bytes.hex_encode()})
		rendered.append(encoded)
	print("B3C SIDE "+JSON.stringify({"stage":stage,"actual":rendered[0],"expected":rendered[1]}))
	check(actual==expected,label)
	return failures==0
