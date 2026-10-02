extends SceneTree
const Controls = preload("res://scripts/golden_bui_controls.gd")
const Service = preload("res://server/golden_bui_service.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Service.CATALOG_PATH))
	var npcs: Array = []
	for script in catalog.services:
		npcs.append({"service_id":script,"name":"原道场"})
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var context := {"catalog":catalog,"rng":rng}
	var profile := {"player":{"level":30,"gold":2000},"original_items":[2752,2751,2755]}
	for npc in npcs:
		var rule: Dictionary = catalog.services[npc.service_id]
		if rule.kind != "quiz": continue
		var before := profile.duplicate(true)
		var start := Service.open(npc,profile,context)
		check(start.ok,"quiz opens")
		var plan := Service.reply(npc,profile,start.state,"yes","",context)
		check(plan.ok and plan.actions=={"DelItem":"2752*1"},"one entry ticket per series")
		var seen := {}
		for index in range(int(rule.count)):
			check(not plan.dialogue.has("answer_choice") and not plan.dialogue.has("state"),"public question excludes secret state")
			var state: Dictionary = plan.state
			var question_index := int(state.order[index])
			check(not seen.has(question_index),"series never repeats a question")
			seen[question_index] = true
			var answer := str(state.get("answer_choice","submit")) if int(state.answer_type)!=4 else "submit"
			var text := "前缀"+str(state.get("answer_text",""))+"后缀"
			plan = Service.reply(npc,profile,state,answer,text,context)
			check(plan.ok,"answer accepted")
			if index+1<int(rule.count):check(plan.actions.is_empty(),"subsequent questions don't charge another ticket")
		check(plan.close and plan.actions.has("Warp"),"all-correct series advances")
		check(plan.result.correct==rule.count,"original text contains matching is preserved")
		check(profile==before,"plan never mutates profile")
		plan = Service.reply(npc,profile,start.state,"yes","",context)
		for index in range(int(rule.count)):
			var state: Dictionary = plan.state
			var answer := "submit" if int(state.answer_type)==4 else ("2" if str(state.answer_choice)=="1" else "1")
			plan = Service.reply(npc,profile,state,answer,"this is not any Chinese answer",context)
		check(plan.close and not plan.actions.has("GetItem"),"wrong answers give no coupon")
		var expected: Array = []
		for threshold in rule.warps:
			if int(threshold.min_correct)==0:expected=threshold.value;break
		check(plan.actions.get("Warp","")==Service._warp(expected) if not expected.is_empty() else not plan.actions.has("Warp"),"failure follows original retreat or stays")
	for npc in npcs:
		var rule: Dictionary = catalog.services[npc.service_id]
		if rule.kind != "janken": continue
		var start := Service.open(npc,profile,context)
		var hands := Service.reply(npc,profile,start.state,"yes","",context)
		check(hands.actions=={"DelItem":"2751*1"},"janken consumes one entry ticket")
		var no_ticket := profile.duplicate(true)
		no_ticket.original_items = []
		var free_hands := Service.reply(npc,no_ticket,start.state,"yes","",context)
		check(free_hands.ok and free_hands.actions.is_empty(),"approved original missing-ticket behavior opens hands without inventing a fee")
		check(start.dialogue.text.contains("原版行为"),"source exception is disclosed")
		var outcomes := {}
		for attempt in range(80):
			var plan := Service.reply(npc,profile if attempt%2 else no_ticket,hands.state if attempt%2 else free_hands.state,"rock","",context)
			if plan.get("close",false):
				outcomes[str(plan.result.win)]=true
				check(not plan.actions.has("DelItem"),"resolved hand never charges again")
				check(plan.actions.Warp==Service._warp(rule.win_warp if plan.result.win else rule.lose_warp),"original win/lose warp")
			else:
				outcomes["draw"]=true
				check(plan.actions.is_empty(),"draw retries without entry fee")
		check(outcomes.size()==3,"all three hand outcomes covered")
	var gates := {"genout/wpm_811_30_20":[30,49,2755],"genout/wpm_811_28_20":[50,69,2756],"genout/wpm_851_29_20":[70,140,2757]}
	for npc in npcs:
		if not gates.has(npc.service_id):continue
		var limits: Array = gates[npc.service_id]
		for level in [29,30,49,50,69,70,140]:
			var candidate := {"player":{"level":level},"original_items":[limits[2]]}
			var accepted := Service.open(npc,candidate,context)
			check(accepted.ok==(level>=limits[0] and level<=limits[1]),"gate original level bounds")
			if accepted.ok:
				candidate.original_items=[]
				check(not Service.reply(npc,candidate,accepted.state,"yes","",context).ok,"entry ticket is rechecked at confirm")
	print("golden_bui_service_test: %d failures" % failures)
	quit(1 if failures else 0)
