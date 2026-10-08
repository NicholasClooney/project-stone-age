extends "res://tests/support/fee_departure_harness.gd"
## UNRUN. Actual private scopes/Stop/Accounts/Automation, callback fault doubles.
func counters(a)->Dictionary:
	return {"running":a.running,"compact":a.compact_active,"turns":a.turns,"battles":a.battles,"xp":a.earned_xp,"text":a.turn_text,"reason":a.stop_reason,"finish_after_capture":a.finish_after_capture}
func run()->void:
	for point:String in ["stop_claim","profile_read","profile_write","profile_write_2","side_read","side_remove","side_write","side_rename","publish","account_revoke","attach","party","listing","open","observation"]:
		var c:Dictionary=fixture("nested-"+point)
		if c.is_empty():quit(1);return
		var b=c.b;var hub=c.hub
		var observed:Dictionary={}
		if point in ["side_write","side_rename"]:
			c.marker["sentinel"]={"keep":[1,"residual"]};c.side=JSON.stringify(JSON.from_native(c.marker)).to_utf8_buffer();put(b._resume_file(),c.side)
		var nested:Callable=func():
			var reply:Dictionary=hub.handle(71,{"type":"login","name":"New","pin":"4321"})
			observed.reply=reply;observed.record=hub._connections[71];observed.binding=hub.backend_of(71)._fee_bindings[71]
			observed.old=b.session._profile.duplicate(true);observed.disk=disks(c.path);observed.side=side(b)
			observed.target=hub.backend_of(71).session._profile.duplicate(true);observed.accounts=hub.accounts.data.duplicate(true)
		if point=="account_revoke":hub.accounts.callback=nested
		elif point in ["attach","party","listing","open"]:hub.at=point;hub.hook=nested
		elif point=="profile_read":b.session.read_callback=nested
		elif point in ["profile_write","profile_write_2"]:b.session.callback=nested;b.session.callback_write=2 if point=="profile_write_2" else 1
		else:b.at=point;b.hook=nested
		var result:Dictionary=hub.handle(71,{"type":"login","name":"New","pin":"4321"} if point=="open" else {"type":"logout"})
		check(not observed.is_empty(),"specified real callback reached: "+point)
		if not observed.is_empty():
			check(truth(observed.reply.get("ok")) and hub.profile_of(71)==c.z.id,"nested target login succeeds")
			check(is_same(hub._connections[71],observed.record) and is_same(hub.backend_of(71)._fee_bindings.get(71),observed.binding),"old logout cannot erase successor connection/binding")
			check(b.session._profile==observed.old and disks(c.path)==observed.disk and side(b)==observed.side,"no old mutation after nested callback, complete three-disk/side images")
			check(hub.backend_of(71).session._profile==observed.target and observed.target==c.target and hub.accounts.data==observed.accounts,"complete new profile and token table retained")
			check(not truth(result.get("ok")) and truth(result.get("stale")),"true successor uses original stale contract")
		complete(c)
	for mutation:String in ["owner","path","runner","identity","auto_token","battle","binding","journal","wrong_handle"]:
		var c:Dictionary=fixture("scope-"+mutation)
		if c.is_empty():quit(1);return
		var b=c.b
		var f:Dictionary=b._begin_fee_departure(71,c.binding,func():return true)
		check(not f.is_empty(),"real private departure scope captured")
		var before:Dictionary=c.before.duplicate(true)
		match mutation:
			"owner":b.session._profile.profile_id="successor";before.profile_id="successor"
			"path":b.save_path=c.path+".successor"
			"runner":b.quest_auto=preload("res://server/quest_auto.gd").new()
			"identity":b.quest_auto.identity=preload("res://server/quest_auto_state.gd").new();b.quest_auto.identity.run_id=RUN
			"auto_token":b.automation.start_lifetime=RefCounted.new()
			"battle":b.battle=preload("res://server/battle_session.gd").new()
			"binding":b.fee_attach(71)
			"journal":b.session._profile.quest_auto_fee_lifecycle.current.run_id=OTHER;before.quest_auto_fee_lifecycle.current.run_id=OTHER
		var id_before:Dictionary=b.quest_auto.identity.checkpoint()
		var token:RefCounted=b._fee_bindings[71]
		var running:bool=b.quest_auto.running
		b._finish_fee_departure(f.duplicate(true) if mutation=="wrong_handle" else f,"fixture")
		if mutation=="journal":check(not b.quest_auto.running,"same real execution revoked without foreign journal write")
		else:check(b.quest_auto.identity.checkpoint()==id_before and b.quest_auto.running==running,"stale or copied frame cannot revoke successor")
		check(is_same(b._fee_bindings[71],token) and b.session._profile==before,"complete successor owner/profile/token preserved")
		check(disks(c.path)==[row(c.before),row(c.before),{"exists":false}] and image(c.path+".successor")=={"exists":false},"no old or successor disk write")
		b.save_path=c.path;b._end_fee_departure(f)
		complete(c)
	for point:String in ["start_publish","start_assist","stop_publish","stop_assist","step_assist","step_battle","capture_assist","quest_rebind_event","normal_start"]:
		var c:Dictionary=fixture("auto-"+point)
		if c.is_empty():quit(1);return
		var b=c.b;var a=b.automation
		# Real battle engine state, no settlement. The enemy survives one turn.
		var config:Dictionary=b.session.start_battle_config()
		config.enemies=[{"name":"scope fixture","species":"wooli","sprite":100250,"level":10,"hp":100000,"max_hp":100000,"attack":1,"defence":1,"speed":1,"can_capture":false}]
		b.open_battle(config)
		b.quest_auto.running=true;b.quest_auto.owns_battle=true;b.quest_auto.phase="battle"
		a.client_attached=false;a.settings=a.profile_settings();a.settings.merge({"preset":"attack","compact":true,"hp":1,"spirit":false,"select_troops":false,"borrow_troops":false},true)
		a.position_map=1000;a.origin_map=1000;a.position_cell=Vector2i(80,90);a.origin_cell=a.position_cell
		a.running=true;a.compact_active=true
		var guard:Dictionary={"valid":true}
		var observed:Dictionary={}
		var cancel:Callable=func():
			var frame:Dictionary=b._begin_fee_departure(71,b._fee_bindings[71],func():return guard.valid)
			check(not frame.is_empty(),"callback captured actual execution provenance")
			b.fee_detach(71)
			b._fee_attempt_writer_call=RefCounted.new() # actual early-busy branch
			b._finish_fee_departure(frame,"callback departure")
			observed.profile=b.session._profile.duplicate(true);observed.pending=b.session._pending.duplicate(true)
			observed.battle=b.battle.snapshot().duplicate(true);observed.counters=counters(a);observed.commands=b.battle_commands
			observed.disk=disks(c.path);observed.side=side(b)
		if point=="quest_rebind_event":
			b.hook=func():
				b.fee_attach(71)
				observed.token=a.start_lifetime;observed.counters=counters(a);observed.profile=b.session._profile.duplicate(true);observed.battle=b.battle.snapshot().duplicate(true)
			b.at="event"
		elif point!="normal_start":
			b.hook=cancel
			b.at="publish" if point in ["start_publish","stop_publish"] else ("battle_command" if point=="step_battle" else "assist")
		if point=="quest_rebind_event":
			b.quest_auto.start_battle(b)
			check(b.fired==1 and not observed.is_empty(),"real quest pre-start status callback reached")
			if not observed.is_empty():check(is_same(a.start_lifetime,observed.token) and counters(a)==observed.counters and b.session._profile==observed.profile and b.battle.snapshot()==observed.battle,"pre-publication binding cannot adopt same-run rebind")
		elif point.begins_with("stop"):
			a.clone_override_active=point=="stop_publish";a.previous_clone_enabled=false
			a.stop("fixture stop")
		elif point=="capture_assist":
			a.start_capture_battle(0,true)
		elif point.begins_with("step"):
			a.step()
		else:
			var before_token:RefCounted=a.start_lifetime
			var scope:Dictionary=b._fee_execution_scope()
			var started:bool=a.start_training()
			if point=="normal_start":
				check(started and a.running and not is_same(a.start_lifetime,before_token),"legal accepted lifetime replacement")
				check(a.take_fee_battle_start(scope) and not a.take_fee_battle_start(scope),"private completed handoff consumed once")
		if point not in ["normal_start","quest_rebind_event"]:
			check(b.fired==1 and not observed.is_empty(),"exact Automation callback reached")
			if not observed.is_empty():
				check(not a.running and not b.quest_auto.running and counters(a)==observed.counters,"old continuation cannot restart or update counters/status")
				check(b.battle.snapshot()==observed.battle and b.session._pending==observed.pending,"current battle remains manual, no settlement/pending clear")
				check(b.session._profile==observed.profile and b.battle_commands==observed.commands,"no post-cancel reward/money/UID or new command")
				check(disks(c.path)==observed.disk and side(b)==observed.side,"full actual disk images unchanged after callback")
		complete(c)
	for kind:String in ["diagnostic","copied_pending","used_pending","cold_reload","failed_load"]:
		var c:Dictionary=fixture("authority-"+kind)
		if c.is_empty():quit(1);return
		var b=c.b
		var held:RefCounted=RefCounted.new();b._fee_attempt_writer_call=held
		check(truth(c.hub.handle(71,{"type":"logout"}).get("ok")),"real busy logout completes")
		check(is_same(b._fee_attempt_writer_call,held),"departure does not steal held claim")
		var original:Dictionary=b._fee_departure_pending
		check(not original.is_empty(),"private genuine pending provenance exists")
		b._fee_attempt_writer_call=null
		if kind=="used_pending":b._retry_fee_departure(func():return true)
		if kind in ["cold_reload","failed_load"]:
			var loaded:bool=b.load_profile(c.path if kind=="cold_reload" else c.path+".missing")
			check(loaded==(kind=="cold_reload"),"actual successful/failed load returns unchanged")
			check(b._fee_pending_record.is_empty(),"real load revokes old private retry provenance")
		var before:Dictionary=b.session._profile.duplicate(true)
		var old_disk:Array=disks(c.path);var old_side:Array=side(b);var writes:int=b.session.writes
		b._fee_departure_pending={"ok":true,"profile":"closed_pair_observed"} if kind=="diagnostic" else original.duplicate(true)
		b._retry_fee_departure(func():return true)
		check(b.session._profile==before and disks(c.path)==old_disk and side(b)==old_side and b.session.writes==writes,"diagnostic/copy/used record cannot regain retry authority")
		complete(c)
	check(fixtures==38 and loads==55,"38 fixtures and 55 real loads; no Wait or wall polling")
	finish("FEE DEPARTURE SCOPE")
