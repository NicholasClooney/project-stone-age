extends "res://tests/support/fee_departure_harness.gd"
## UNRUN independent lifetime observations; no product private-field cleanup.
func run()->void:
	for mode:String in ["logout","switch","busy","target_fail","superseded"]:
		var refs:Array=hub_case(mode)
		for ref:WeakRef in refs:check(ref.get_ref()==null,"call-owned object released after fixture stack exits: "+mode)
	for mode:String in ["take","wrong_take","invalid","revoke","stop","replacement","abandon"]:
		var refs:Array=auto_case(mode)
		for ref:WeakRef in refs:check(ref.get_ref()==null,"Automation and session released after own references end: "+mode)
	check(fixtures==12 and loads==15,"exact lifecycle fixture/load budget")
	finish("FEE DEPARTURE LIFETIME")
func hub_case(mode:String)->Array:
	var c:Dictionary=fixture("lifetime-"+mode)
	if c.is_empty():quit(1);return []
	var b=c.b;var hub=c.hub
	var refs:Array=[weakref(b.session),weakref(b.automation),weakref(b.quest_auto)]
	if mode=="busy":b._fee_attempt_writer_call=RefCounted.new()
	if mode=="target_fail":put(c.target_path,"bad-profile".to_utf8_buffer())
	if mode=="superseded":
		hub.at="listing"
		hub.hook=func():hub.handle(71,{"type":"login","name":"New","pin":"4321"})
	var result:Dictionary=hub.handle(71,{"type":"login","name":"New","pin":"4321"} if mode in ["switch","target_fail"] else {"type":"logout"})
	check(truth(result.get("ok"))==not (mode in ["target_fail","superseded"]),"real Hub result retains contract")
	if mode=="busy":check(refs[0].get_ref()!=null and not b._fee_departure_pending.is_empty(),"legitimate pending owns session while backend lives")
	# Only the test's callback is removed; product pending/frame fields untouched.
	hub.hook=Callable()
	for ref:WeakRef in hub.ended_calls:check(ref.get_ref()==null,"every finished call token released before Hub destruction")
	complete(c)
	return refs
func auto_case(mode:String)->Array:
	var c:Dictionary=fixture("handoff-"+mode)
	if c.is_empty():quit(1);return []
	var b=c.b;var a=b.automation
	var refs:Array=[weakref(a),weakref(b.session),weakref(b.quest_auto),weakref(b.battle)]
	var config:Dictionary=b.session.start_battle_config()
	config.enemies=[{"name":"lifetime fixture","species":"wooli","sprite":100250,"level":10,"hp":100000,"max_hp":100000,"attack":1,"defence":1,"speed":1,"can_capture":false}]
	b.open_battle(config)
	b.quest_auto.running=true;b.quest_auto.owns_battle=true;b.quest_auto.phase="battle"
	a.client_attached=false;a.settings=a.profile_settings();a.settings.merge({"preset":"attack","compact":true,"hp":1,"spirit":false,"select_troops":false,"borrow_troops":false},true)
	var before:Dictionary=b._fee_execution_scope()
	var profile:Dictionary=b.session._profile.duplicate(true)
	var pending:Dictionary=b.session._pending.duplicate(true)
	var battle:Dictionary=b.battle.snapshot().duplicate(true)
	var disks_before:Array=disks(c.path);var side_before:Array=side(b)
	check(a.start_training(),"real successful unconsumed handoff")
	check(not a._fee_started.is_empty(),"legal unconsumed handoff retained")
	if mode=="wrong_take":check(not a.take_fee_battle_start({}) and not a._fee_started.is_empty(),"wrong take cannot erase legal authority")
	if mode in ["take","wrong_take"]:check(a.take_fee_battle_start(before) and not a.take_fee_battle_start(before),"real one-shot take then replay rejection")
	if mode=="invalid":
		b.fee_attach(71)
		check(not a.take_fee_battle_start(before) and a._fee_started.is_empty(),"successor binding invalidates old handoff without adoption")
	if mode=="replacement":
		var next_before:Dictionary=b._fee_execution_scope()
		check(a.start_training(),"legitimate replacement starts")
		check(not a.take_fee_battle_start(before) and not a._fee_started.is_empty(),"old take preserves replacement authority")
		check(a.take_fee_battle_start(next_before),"only replacement owner consumes")
	if mode=="stop":a.stop("lifetime test")
	if mode=="revoke":
		var f:Dictionary=b._begin_fee_departure(71,b._fee_bindings[71],func():return true)
		b.quest_auto.revoke_fee_execution(b,f,"lifetime revoke")
		b._end_fee_departure(f)
	if mode in ["stop","revoke"]:check(a._fee_started.is_empty(),"real stop/revoke abandons owned handoff")
	check(b.session._profile==profile and b.session._pending==pending,"no reward/profile/Session pending settlement")
	check(disks(c.path)==disks_before and side(b)==side_before,"all persistent bytes unchanged")
	check(b.battle.snapshot().get("battle_id")==battle.get("battle_id"),"same manual battle retained")
	complete(c)
	return refs
