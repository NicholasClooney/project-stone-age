extends RefCounted
## Quest 44 plans only. OriginalQuests owns tokens, transactions and publication.
const CATALOG_PATH := "res://assets/legacy/server/golden-bui.json"
const HANDS := ["石头", "剪刀", "布"]

static func _rule(npc: Dictionary, context: Dictionary) -> Dictionary:
	var catalog: Dictionary = context.get("catalog", {})
	return catalog.get("services", catalog).get(str(npc.get("service_id", "")), {})

static func _dialogue(npc: Dictionary, state: Dictionary, text: String, choices: Array, input := "choice") -> Dictionary:
	return {"ok":true,"state":state,"dialogue":{"name":str(npc.name),"text":text.replace("\\n","\n"),"choices":choices,"input":input},"actions":{},"event":-1}

static func _confirm(npc: Dictionary, text: String) -> Dictionary:
	return _dialogue(npc,{"phase":"confirm"},text,[{"id":"yes","text":"是"},{"id":"no","text":"否"}])

static func _failure(text: String) -> Dictionary:
	return {"ok":false,"reason":text.replace("\\n","\n")}

static func _condition(profile: Dictionary, condition: String) -> bool:
	# Explicit reviewed gate subset, never interpret arbitrary source scripts.
	for clause in condition.split(","):
		var accepted := true
		for predicate in clause.split("&"):
			var regex := RegEx.new()
			regex.compile("^(LV|ITEM)([<>=])([0-9]+)$")
			var found := regex.search(predicate)
			if found == null:
				accepted = false
				break
			var value := int(found.get_string(3))
			var actual := int(profile.player.level)
			var result := false
			if found.get_string(1) == "ITEM":
				result = value in profile.original_items
			elif found.get_string(2) == ">": result = actual > value
			elif found.get_string(2) == "<": result = actual < value
			else: result = actual == value
			if not result:
				accepted = false
				break
		if accepted: return true
	return false

static func open(npc: Dictionary, profile: Dictionary, context: Dictionary) -> Dictionary:
	var rule := _rule(npc,context)
	if rule.is_empty(): return _failure("原道场资料尚未导入。")
	var fields: Dictionary = rule.original_fields
	if bool(context.get("in_party",false)):
		return _failure(str(fields.get("Party",fields.get("PartyMsg","请先退出团队再挑战。"))))
	match str(rule.kind):
		"warpman":
			if not _condition(profile,str(rule.condition)): return _failure(str(fields.get("PayMsg","尚未符合入场条件。")))
			return _confirm(npc,str(fields.FreeMsg).replace("%4d","—"))
		"quiz": return _confirm(npc,str(fields.StartMsg))
		"janken": return _confirm(npc,str(fields.MainMsg)+"\n原版行为：无猜拳参加券也可挑战；有券时消耗一张，平局不再扣券。")
	return _failure("尚未开放的原道场类型。")

static func _warp(cell: Array) -> String:
	return "%d,%d,%d" % [int(cell[0]),int(cell[1]),int(cell[2])]

static func _threshold(entries: Array, correct: int, fallback: Variant) -> Variant:
	for entry in entries:
		if correct >= int(entry.min_correct): return entry.value
	return fallback

static func _question(npc: Dictionary, rule: Dictionary, state: Dictionary, context: Dictionary) -> Dictionary:
	var question: Dictionary = rule.questions[int(state.order[int(state.index)])]
	state = state.duplicate(true)
	state.phase = "question"
	state.answer_type = int(question.answer_type)
	var prompt := "猜谜 第 %d / %d 题\n%s" % [int(state.index)+1,int(rule.count),str(question.text)]
	if int(question.answer_type) == 4:
		state.answer_text = str(question.options[0])
		return _dialogue(npc,state,prompt,[{"id":"submit","text":"回答"},{"id":"cancel","text":"取消"}],"text")
	var options := [0,1] if int(question.answer_type) == 1 else [0,1,2]
	var rng: RandomNumberGenerator = context.rng
	for index in range(options.size()-1,0,-1):
		var other := rng.randi_range(0,index)
		var temp: int = options[index]
		options[index] = options[other]
		options[other] = temp
	var choices := []
	for index in range(options.size()):
		choices.append({"id":str(index+1),"text":str(question.options[options[index]])})
		if options[index] == int(question.answer): state.answer_choice = str(index+1)
	choices.append({"id":"cancel","text":"取消"})
	return _dialogue(npc,state,prompt,choices)

static func _hands(npc: Dictionary, text: String) -> Dictionary:
	return _dialogue(npc,{"phase":"hands"},text,[{"id":"rock","text":"石头"},{"id":"scissors","text":"剪刀"},{"id":"paper","text":"布"}])

static func reply(npc: Dictionary, profile: Dictionary, state: Dictionary, choice: String, text: String, context: Dictionary) -> Dictionary:
	var rule := _rule(npc,context)
	if rule.is_empty(): return _failure("原道场资料尚未导入。")
	var fields: Dictionary = rule.original_fields
	if str(state.get("phase","")) == "confirm":
		if choice == "no": return {"ok":true,"close":true}
		if choice != "yes": return _failure("无效选择。")
		if bool(context.get("in_party",false)): return _failure(str(fields.get("Party",fields.get("PartyMsg","请先退出团队再挑战。"))))
		if str(rule.kind) == "warpman":
			if not _condition(profile,str(rule.condition)): return _failure(str(fields.get("PayMsg","入场条件已经改变。")))
			return {"ok":true,"close":true,"actions":{"DelItem":str(rule.del_items),"Warp":_warp(rule.warp)}}
		var enough: bool = profile.original_items.count(int(rule.entry_item)) >= int(rule.entry_count)
		if not enough and str(rule.kind) != "janken":
			# Quiz really returns on missing entry; janken intentionally does not.
			return _failure(str(fields.get("NoEntryMsg",fields.get("NoItem","没有参加券。"))))
		var plan: Dictionary
		if str(rule.kind) == "janken":
			plan = _hands(npc,"剪刀石头布！！")
		else:
			var order := range(rule.questions.size())
			var rng: RandomNumberGenerator = context.rng
			for index in range(order.size()-1,0,-1):
				var other := rng.randi_range(0,index)
				var temp: int = order[index]
				order[index] = order[other]
				order[other] = temp
			plan = _question(npc,rule,{"order":order.slice(0,int(rule.count)),"index":0,"correct":0},context)
		plan.actions = {"DelItem":"%d*%d" % [int(rule.entry_item),int(rule.entry_count)]} if enough else {}
		return plan
	if str(state.get("phase","")) == "hands":
		var player := ["rock","scissors","paper"].find(choice)
		if player < 0: return _failure("无效选择。")
		var rng: RandomNumberGenerator = context.rng
		var opponent := rng.randi_range(0,2)
		if player == opponent: return _hands(npc,"平手再来！！")
		var win := (player+1)%3 == opponent
		return {"ok":true,"close":true,"actions":{"Warp":_warp(rule.win_warp if win else rule.lose_warp)},"result":{"player":HANDS[player],"opponent":HANDS[opponent],"win":win}}
	if str(state.get("phase","")) == "question":
		if choice == "cancel": return {"ok":true,"close":true}
		var next := state.duplicate(true)
		var correct := false
		if int(state.answer_type) == 4:
			if choice != "submit": return _failure("无效选择。")
			# npc_quiz.c:521 deliberately uses substring matching, not equality.
			correct = text.contains(str(state.answer_text))
		else:
			if choice not in (["1","2"] if int(state.answer_type)==1 else ["1","2","3"]): return _failure("无效选择。")
			correct = choice == str(state.answer_choice)
		next.correct = int(state.correct)+(1 if correct else 0)
		next.index = int(state.index)+1
		if int(next.index) < int(rule.count): return _question(npc,rule,next,context)
		var actions := {}
		var reward := int(_threshold(rule.rewards,int(next.correct),0))
		if reward > 0: actions.GetItem = str(reward)
		var warp: Array = _threshold(rule.warps,int(next.correct),[])
		if not warp.is_empty(): actions.Warp = _warp(warp)
		return {"ok":true,"close":true,"actions":actions,"result":{"text":str(_threshold(rule.borders,int(next.correct),fields.get("FailureMsg",""))).replace("\\n","\n"),"correct":int(next.correct),"total":int(rule.count)}}
	return _failure("对话状态已经改变。")
