extends "res://tests/quest_legitimate_arrival_test.gd"
const Policy=preload("res://server/quest_arrival_policy.gd")

func run() -> void:
	var b=fresh()
	integrated=b.get("quest_arrival")!=null
	var a=b.get("quest_arrival") if integrated else Arrival.new()
	var sage: Dictionary=b.original_quests.npc_by_id("sainasu/event/event12@11107:24:6")
	observed(b,a,11107,Vector2i(24,7),"project")
	for branch in sage.branches:
		check(not a.check_action(b,sage,branch,"reward").is_empty(),"project arrival cannot advance shared event12 branch")
	check(Policy.action_marks(sage,{"source_branch_index":0})==["munde_final"] and Policy.action_marks(sage,{"source_branch_index":2})==["munde_final"] and Policy.action_marks(sage,{"source_branch_index":3})==["munde_final"],"legacy stones and wind replacement/new lute share original Munde access")
	for map_id in range(11201,11216):
		check(Policy.scope(map_id)=="wind","all actual wind maps share continuous route without invented numeric order")
	check(Policy.scope(100).is_empty() and Policy.scope(32021).is_empty(),"public return and staged spirit king do not acquire an active policy")
	check(Policy.script_root("genout/wpm_100_278_325",11201) and not Policy.portal_root(100,11201),"wind root requires original gate transaction, scenic portal is insufficient")
	check(Policy.battle_mark("100/sb_kgi.arg")=="wind_final" and Policy.battle_mark("100/sb_kbu.arg").is_empty(),"middle guard cannot issue summit proof")
	for script in ["sainasu/event/genou_1","sainasu/event/genou_2"]:
		check(Policy.action_marks({"source_script":script},{})==["wind_final"],"summit request/reward/pet exchange use final proof")
	check(Policy.action_marks({"source_script":"sainasu/event/genou_3"},{}).is_empty(),"public NOW42 receives no cave prerequisite")
	# Contract-level transaction test: use the actual pinned gate and real
	# persistence, invoking the after-save hook explicitly on old backends.
	# This is not a claim that an old backend has the shared transaction hook.
	var gate: Dictionary=b.original_quests.npc_by_id("genout/wpm_100_443_127@100:443:127")
	b.automation.position_changed(100,Vector2i(443,128))
	b.save_path="user://missing-munde-arrival/fail.json"
	if integrated:
		var opened: Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
		var denied: Dictionary=b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"submit","text":"在卡坦有梦德"})
		check(not denied.ok,"real original keyword transaction fails persistence")
	else:
		check(not b.save(),"real failed persistence provides no committed gate receipt")
		observed(b,a,11101,Vector2i(33,29),"script")
	check(not a.has_arrival(b,11101,Vector2i(33,29)),"source landing without saved gate receipt fails closed")
	b.automation.position_changed(100,Vector2i(443,128))
	b.save_path=""
	if integrated:
		var opened: Dictionary=b.handle({"type":"quest_talk","npc_id":gate.id})
		check(b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"submit","text":"在卡坦有梦德"}).ok,"real original keyword transaction retries")
	else:
		check(b.save(),"gate contract persistence succeeds")
		a.action_committed(b,gate,gate.branches[0],"KEYWORD")
		observed(b,a,11101,Vector2i(33,29),"script")
	check(a.has_arrival(b,11101,Vector2i(33,29)),"matching committed original keyword Warp starts Munde route")
	var path: Array=RouteDriver.path(b,11107,Vector2i(22,42),range(11101,11108))
	check(not path.is_empty(),"actual seven-map portal graph reaches guard front")
	for step in path:
		if integrated:
			check(b.handle({"type":"report_position","map_id":step.map_id,"cell":step.cell}).ok,"production original route report")
		else:observed(b,a,int(step.map_id),Vector2i(int(step.cell[0]),int(step.cell[1])))
		check(a.has_arrival(b,int(step.map_id),Vector2i(int(step.cell[0]),int(step.cell[1]))),"Munde original consecutive step")
	check(not a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"seven floors without the final battle cannot reward")
	var guard: Dictionary=b.original_quests.npc_by_id("100/sb_go.arg@11107:22:41")
	var opened: Dictionary=b.handle({"type":"quest_talk","npc_id":guard.id})
	check(opened.ok and choose(b,opened,"yes").ok,"actual Munde final guard starts")
	var pending: Dictionary=b.session._pending.quest_guard.duplicate(true)
	if not integrated:
		pending.arrival=a.battle_context(b,guard,guard.branches[0])
	fight(b)
	check(bool(b.battle_state.get("settled",false)),"actual Munde battle saves its result")
	if not integrated:a.battle_committed(b,pending)
	var old: Vector2i=b.automation.position_cell
	b.close_battle()
	if not integrated:a.observe_move(b,11107,old,11107,b.automation.position_cell,"script")
	check(a.check_action(b,sage,sage.branches[0],"reward").is_empty(),"real Munde victory arrival permits the shared original reward")
	# The public source NPC tile reached by the genuine wind return is not
	# constrained by a protected movement scope, and no scope is restored.
	observed(b,a,100,Vector2i(278,325),"script")
	observed(b,a,100,Vector2i(278,326))
	check(Policy.scope(b.automation.position_map).is_empty(),"walking off public original return NPC cell remains unrestricted")
	b.free()
	print("QUEST ARRIVAL MUNDE WIND: %d failures"%failures)
	quit(1 if failures else 0)
