extends RefCounted
## UNRUN, test-owned, exact-source adapter. Never registered in Policy/Registry.
## It calls the original one-page/one-token/one-choose KEYWORD transaction.
const Answers = preload("res://server/quest_auto_source_answers.gd")
const Plan = preload("res://server/quest_auto_munde_plan.gd")
const Request10 = preload("res://server/quest_auto_munde_request10_candidate.gd")
const Session = preload("res://server/game_session.gd")
const Rules = preload("res://server/original_quests.gd")

const LOCK_PATH := "res://tests/fixtures/quest_auto_munde_keyword_source_lock.json"
const LOCK_SHA256 := "644ed61e8d211895b06d6adca005a904ee2ab9620d2ee6c427bee443c6b5ce13"
const SOURCE := "genout/wpm_100_443_127"
const NPC_ID := "genout/wpm_100_443_127@100:443:127"
const SOURCE_SHA := "ab24fd28d53a0230943ff27ed0c852b4cde5d4b2d1ad22de4fccafadba700da5"
const ANSWER_TABLE_SHA := "34d7013e2e67d2bca606993d7b32915f135ef04cc1d8cf5045424e637c16faef"
const CATALOG_SHA := "c5679bb2e23d0e00eb47ccba0fd581b161cf66df35fabe461ca52c95d9a9ff92"
const ANSWER := "在卡坦有梦德"
const TARGET_MAP := 11101
const TARGET_CELL := Vector2i(33, 29)
const KEYWORD_STEP := "munde:keyword:genout/wpm_100_443_127"
const BOSS_STEP := "munde:first-boss:100/sb_go.arg"

static func hold(stage: String, reason: String) -> Dictionary:
	return {"status":"manual","stage":stage,"reason":reason}

## Keep the base selector authoritative while distinguishing the one original
## KEYWORD step from the post-commit route to the original Boss page.
static func continuation_intent(stage: String, keyword_committed: bool) -> String:
	if stage == "keyword_route":return "keyword" if not keyword_committed else "boss_travel"
	if stage == "boss_and_stones" and keyword_committed:return "boss_page"
	return ""

static func _same_run_keyword_commit_observed(b) -> bool:
	var runner_value: Variant = b.quest_auto
	if runner_value == null:return false
	var committed_value: Variant = runner_value.keyword_committed_this_run
	var observation_value: Variant = runner_value.keyword_observation
	if not committed_value is bool or not committed_value or not observation_value is Dictionary:return false
	var observation: Dictionary = observation_value
	var result_value: Variant = observation.get("result")
	var resolver_value: Variant = observation.get("resolver")
	var branch_value: Variant = observation.get("branch")
	var token_value: Variant = observation.get("token")
	if not observation.get("ok") is bool or not observation.get("ok") or not result_value is Dictionary or not resolver_value is Dictionary or not branch_value is Dictionary or not token_value is String or token_value.is_empty():return false
	var result: Dictionary = result_value
	var resolver: Dictionary = resolver_value
	var evidence_value: Variant = resolver.get("evidence")
	if not evidence_value is Dictionary:return false
	var evidence: Dictionary = evidence_value
	var locked_keyword: Dictionary = _locked_branch("wpm")
	if locked_keyword.is_empty() or not Plan.same_source(branch_value,locked_keyword):return false
	if resolver.get("status") != "answer" or resolver.get("choice") != "submit" or resolver.get("text") != ANSWER:return false
	if evidence.get("source") != "gmsv/data/npc/" + SOURCE or evidence.get("source_sha") != SOURCE_SHA or evidence.get("table_sha") != ANSWER_TABLE_SHA:return false
	return result.get("ok") is bool and result.get("ok") and result.get("closed") is bool and result.get("closed")

static func _lock() -> Dictionary:
	if not FileAccess.file_exists(LOCK_PATH):return {}
	var file := FileAccess.open(LOCK_PATH, FileAccess.READ)
	if file == null:return {}
	var raw: String = file.get_as_text()
	file.close()
	if raw.sha256_text() != LOCK_SHA256:return {}
	var parsed: Variant = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

static func _valid_lock_npc(lock: Dictionary, key: String) -> Dictionary:
	var npcs_value: Variant = lock.get("npcs")
	if not npcs_value is Dictionary:return {}
	var npc_value: Variant = npcs_value.get(key)
	return npc_value if npc_value is Dictionary else {}

static func _locked_branch(source_key: String, branch_index: int = 0) -> Dictionary:
	var lock: Dictionary = _lock()
	var npc: Dictionary = _valid_lock_npc(lock,source_key)
	var branches_value: Variant = npc.get("branches")
	if not branches_value is Array or branch_index < 0 or branch_index >= branches_value.size():return {}
	var branch_value: Variant = branches_value[branch_index]
	return branch_value if branch_value is Dictionary else {}

static func _project_enabled(raw_npc: Dictionary, enabled_events: Array) -> Dictionary:
	var projected: Dictionary = raw_npc.duplicate(true)
	var branches_value: Variant = raw_npc.get("branches")
	if not branches_value is Array:return {}
	var active_branches: Array = []
	for branch_value in branches_value:
		if not branch_value is Dictionary:return {}
		var branch: Dictionary = branch_value
		var branch_events_value: Variant = branch.get("events")
		if not branch_events_value is Array:return {}
		if branch.get("enabled") is bool and branch.enabled and branch_events_value.any(func(event): return _contains_exact_event(enabled_events, event)):
			active_branches.append(branch.duplicate(true))
	projected.branches = active_branches
	return projected

static func _contains_exact_event(events: Array, candidate: Variant) -> bool:
	for value in events:
		if Plan.same_source(value,candidate):return true
	return false

static func _npc_source_ok(b, source_key: String, id: String, raw_source_sha: String) -> Dictionary:
	var lock: Dictionary = _lock()
	if lock.is_empty() or not Plan.same_source(lock.get("catalog_sha256"), CATALOG_SHA):return {}
	var raw_npc: Dictionary = _valid_lock_npc(lock, source_key)
	if raw_npc.is_empty() or not Plan.same_source(raw_npc.get("id"), id):return {}
	var raw_sources_value: Variant = lock.get("raw_source_sha256")
	if not raw_sources_value is Dictionary or not Plan.same_source(raw_sources_value.get(source_key), raw_source_sha):return {}
	var count: int = 0
	for catalog_value in b.quest_catalog.npcs:
		if not catalog_value is Dictionary:return {}
		var npc: Dictionary = catalog_value
		if Plan.same_source(npc.get("id"), id):
			count += 1
			if not Plan.same_source(npc, raw_npc):return {}
	if count != 1:return {}
	var active_value: Variant = b.quest_catalog.active_npc(id)
	if not active_value is Dictionary:return {}
	var active: Dictionary = active_value
	var expected_active: Dictionary = _project_enabled(raw_npc, b.quest_catalog.enabled_events)
	if expected_active.is_empty() or not Plan.same_source(active, expected_active):return {}
	return active

static func _branch_from_active(b, active: Dictionary, expected_branch: Dictionary) -> Dictionary:
	var snapshot_value: Variant = b.session.snapshot()
	if not snapshot_value is Dictionary:return {}
	var branch_value: Variant = b.original_quests.branch_for(active, snapshot_value)
	if not branch_value is Dictionary:return {}
	var branch: Dictionary = branch_value
	return branch if Plan.same_source(branch, expected_branch) else {}

static func select(b, job_id: int = 8, keyword_committed: bool = false) -> Dictionary:
	if job_id != 8:return hold("unsupported_job", "仅梦德job8。")
	var prefix: Dictionary = Request10.select(b, job_id)
	if prefix.get("status") == "done":return prefix
	if prefix.get("status") != "manual":return prefix
	var stage_value: Variant = prefix.get("stage")
	if not stage_value is String:return prefix
	var intent: String = continuation_intent(stage_value, keyword_committed)
	if intent.is_empty():return prefix
	var profile_value: Variant = b.session._profile
	if not profile_value is Dictionary:return hold("profile_shape", "profile不是字典。")
	var profile: Dictionary = profile_value
	if not Rules.flag(profile, "now", 9) or not Rules.flag(profile, "now", 11) or not Rules.flag(profile, "now", 10):return hold("request_prefix_required", "必须由真实REQUEST9/11/10事务推进。")
	if Rules.flag(profile, "ended", 9) or Rules.flag(profile, "ended", 10) or Rules.flag(profile, "ended", 11) or Rules.flag(profile, "ended", 12):return hold("event_boundary", "END边界不符合口令/首Boss页面路线。")
	var items_value: Variant = profile.get("original_items")
	if not items_value is Array:return hold("profile_shape", "original_items不是数组。")
	if _contains_exact_event(items_value,2420) or _contains_exact_event(items_value,2419):return hold("stone_boundary", "已有原石时停止，不重复处理后续支线。")
	if intent == "keyword":
		var active: Dictionary = _npc_source_ok(b, "wpm", NPC_ID, SOURCE_SHA)
		if active.is_empty():return hold("source_or_projection", "WPM原源或启用投影不匹配。")
		var branches_value: Variant = active.get("branches")
		if not branches_value is Array or branches_value.size() != 1 or not branches_value[0] is Dictionary:return hold("branch_shape", "WPM当前分支列表形状改变。")
		var expected_branch_value: Variant = branches_value[0]
		if not expected_branch_value is Dictionary:return hold("branch_shape", "WPM分支不是字典。")
		var branch: Dictionary = expected_branch_value
		if not Rules.matches(profile, "LV>0") or not Plan.same_source(branch.get("event"), -1) or branch.get("type") != "KEYWORD" or branch.get("condition") != "LV>0" or branch.get("keyword") != ANSWER:return hold("branch_contract", "WPM分支不再是锁定KEYWORD源。")
		var selected: Dictionary = _branch_from_active(b, active, branch)
		if selected.is_empty():return hold("branch_priority", "原branch_for未选择唯一锁定KEYWORD。")
		if not b.quest_arrival.has_arrival(b, b.automation.position_map, b.automation.position_cell):return hold("arrival_required", "必须保留当前位置原arrival。")
		return {"status":"step","step":{"id":KEYWORD_STEP,"npc_id":NPC_ID,"map_id":100,"cell":[443,127],"current":true,"done":false,"actionable":true,"auto_choices":[],"source":{"npc_id":NPC_ID,"type":"KEYWORD","branch_data":branch.duplicate(true),"source_sha":SOURCE_SHA,"audit_policy":"munde_single_source_keyword_v1"}}}
	if not _same_run_keyword_commit_observed(b):return hold("keyword_commit_not_observed", "只有本次run已记录的原KEYWORD成功事务才能继续前往首Boss人工页。")
	var boss_id: String = "100/sb_go.arg@11107:22:41"
	var boss_source_sha: String = "79018dc8414c352eb90c5f388459b01d4985ba7eceb434d6e514639ad35127e0"
	var boss: Dictionary = _npc_source_ok(b, "first_boss", boss_id, boss_source_sha)
	if boss.is_empty():return hold("boss_source_or_projection", "首Boss原源或启用投影不匹配。")
	var boss_branches_value: Variant = boss.get("branches")
	if not boss_branches_value is Array or boss_branches_value.size() != 1 or not boss_branches_value[0] is Dictionary:return hold("boss_branch_shape", "首Boss原分支列表形状改变。")
	var boss_branch_value: Variant = boss_branches_value[0]
	if not boss_branch_value is Dictionary:return hold("boss_branch_shape", "首Boss分支不是字典。")
	var boss_branch: Dictionary = boss_branch_value
	var locked_boss_branch: Dictionary = _locked_branch("first_boss")
	if locked_boss_branch.is_empty() or not Plan.same_source(boss_branch,locked_boss_branch):return hold("boss_branch_source", "首Boss完整分支与冻结原分支不一致。")
	if boss_branch.get("type") != "BATTLE" or not Plan.same_source(boss_branch.get("event"), -1) or not Plan.same_source(boss_branch.get("actions"), {"Battle":"527,526,528,529","Warp":"11107,23,35"}):return hold("boss_branch_contract", "目标不是锁定首Boss原BATTLE/Warp分支。")
	if _branch_from_active(b, boss, boss_branch).is_empty():return hold("boss_branch_priority", "原branch_for未选择首Boss原BATTLE页。")
	if not b.quest_arrival.has_arrival(b, b.automation.position_map, b.automation.position_cell):return hold("arrival_required", "必须保留当前位置原arrival。")
	return {"status":"step","step":{"id":BOSS_STEP,"npc_id":boss_id,"map_id":11107,"cell":[22,41],"current":true,"done":false,"actionable":true,"auto_choices":[],"source":{"npc_id":boss_id,"type":"BATTLE","branch_data":boss_branch.duplicate(true),"source_sha":boss_source_sha,"audit_policy":"munde_first_boss_page_manual_v1"}}}

static func exact_travel_step(step_value: Dictionary, keyword_committed: bool) -> bool:
	var expected_source: Dictionary = {}
	var expected_step_id: String = ""
	var expected_npc_id: String = ""
	var expected_map: int = -1
	var expected_cell: Array = []
	var expected_type: String = ""
	var expected_sha: String = ""
	var expected_policy: String = ""
	if step_value.get("id") == KEYWORD_STEP and not keyword_committed:
		var expected_branch: Dictionary = _locked_branch("wpm")
		if expected_branch.is_empty():return false
		expected_step_id = KEYWORD_STEP
		expected_npc_id = NPC_ID
		expected_map = 100
		expected_cell = [443,127]
		expected_type = "KEYWORD"
		expected_sha = SOURCE_SHA
		expected_policy = "munde_single_source_keyword_v1"
		expected_source = {"npc_id":NPC_ID,"type":expected_type,"branch_data":expected_branch,"source_sha":expected_sha,"audit_policy":expected_policy}
	elif step_value.get("id") == BOSS_STEP and keyword_committed:
		var expected_branch: Dictionary = _locked_branch("first_boss")
		if expected_branch.is_empty():return false
		expected_step_id = BOSS_STEP
		expected_npc_id = "100/sb_go.arg@11107:22:41"
		expected_map = 11107
		expected_cell = [22,41]
		expected_type = "BATTLE"
		expected_sha = "79018dc8414c352eb90c5f388459b01d4985ba7eceb434d6e514639ad35127e0"
		expected_policy = "munde_first_boss_page_manual_v1"
		expected_source = {"npc_id":expected_npc_id,"type":expected_type,"branch_data":expected_branch,"source_sha":expected_sha,"audit_policy":expected_policy}
	else:
		return false
	var expected_step: Dictionary = {"id":expected_step_id,"npc_id":expected_npc_id,"map_id":expected_map,"cell":expected_cell,"current":true,"done":false,"actionable":true,"auto_choices":[],"source":expected_source}
	return Plan.same_source(step_value,expected_step)

static func submit_original_keyword(b, reply_value: Variant) -> Dictionary:
	if not reply_value is Dictionary:return {"ok":false,"reason":"reply不是字典。"}
	var reply: Dictionary = reply_value
	var pending_value: Variant = b.original_quests.pending
	if not pending_value is Dictionary:return {"ok":false,"reason":"pending不是字典。"}
	var pending: Dictionary = pending_value.duplicate(true)
	if pending.is_empty() or pending.get("phase") != "KEYWORD":return {"ok":false,"reason":"原WPM页不是KEYWORD阶段。"}
	var npc_value: Variant = pending.get("npc")
	if not npc_value is Dictionary:return {"ok":false,"reason":"pending.npc形状错误。"}
	var npc: Dictionary = npc_value
	if npc.get("id") != NPC_ID or npc.get("source_script") != SOURCE or not Plan.same_source(npc.get("map_id"),100) or not Plan.same_source(npc.get("cell"),[443,127]) or not Plan.same_source(npc.get("source_create_index"),6):return {"ok":false,"reason":"WPM身份、地图或格不匹配。"}
	var events_value: Variant = npc.get("events")
	if not events_value is Array or not Plan.same_source(events_value,[9,10,11,12]):return {"ok":false,"reason":"WPM事件数组不匹配。"}
	var branches_value: Variant = npc.get("branches")
	if not branches_value is Array or branches_value.size()!=1 or not branches_value[0] is Dictionary:return {"ok":false,"reason":"WPM原分支数组形状不匹配。"}
	var branch_value: Variant = branches_value[0]
	if not branch_value is Dictionary:return {"ok":false,"reason":"WPM原分支不是字典。"}
	var branch: Dictionary = branch_value
	if branch.get("type") != "KEYWORD" or branch.get("keyword") != ANSWER or branch.get("condition") != "LV>0" or not Plan.same_source(branch.get("actions"), {"Warp":"11101,33,29"}):return {"ok":false,"reason":"完整WPM分支不匹配。"}
	var active: Dictionary = _npc_source_ok(b,"wpm",NPC_ID,SOURCE_SHA)
	if active.is_empty() or not Plan.same_source(active,npc):return {"ok":false,"reason":"WPM活动投影/完整raw源与pending人物不完全相等。"}
	var locked_keyword: Dictionary = _locked_branch("wpm")
	if locked_keyword.is_empty() or not Plan.same_source(branch,locked_keyword):return {"ok":false,"reason":"pending所带完整分支与冻结原分支不一致。"}
	var snapshot_value: Variant = b.session.snapshot()
	if not snapshot_value is Dictionary:return {"ok":false,"reason":"当前profile不是字典。"}
	var selected_value: Variant = b.original_quests.branch_for(npc,snapshot_value)
	if not selected_value is Dictionary or not Plan.same_source(selected_value,branch):return {"ok":false,"reason":"原branch_for优先级不再选择完整KEYWORD分支。"}
	var page_value: Variant = reply.get("dialogue")
	if not page_value is Dictionary:return {"ok":false,"reason":"原KEYWORD页面不是字典。"}
	var page: Dictionary = page_value
	if page.get("npc_id") != NPC_ID or page.get("kind") != "original_keyword" or page.get("input") != "text" or page.get("text") != "干么，有什么事吗？,喂，你看什么看。":return {"ok":false,"reason":"原KEYWORD页面身份/提示不匹配。"}
	var token_value: Variant = pending.get("token")
	if not token_value is String or token_value.is_empty() or page.get("token") != token_value:return {"ok":false,"reason":"页面token与原pending不一致。"}
	var choices_value: Variant = page.get("choices")
	var expected_choices: Array = [{"id":"submit","text":"说出口令"},{"id":"no","text":"取消"}]
	if not choices_value is Array or not Plan.same_source(choices_value,expected_choices):return {"ok":false,"reason":"完整口令选项不匹配。"}
	var live_pending_value: Variant = b.original_quests.pending
	if not live_pending_value is Dictionary or not Plan.same_source(live_pending_value,pending):return {"ok":false,"reason":"提交前pending/token已改变。"}
	var resolver: Variant = Answers.new()
	var resolved_value: Variant = resolver.resolve_keyword(SOURCE,page)
	if not resolved_value is Dictionary:return {"ok":false,"reason":"resolver返回类型不是字典。"}
	var resolved: Dictionary = resolved_value
	if resolved.get("status") != "answer" or resolved.get("choice") != "submit" or resolved.get("text") != ANSWER:return {"ok":false,"reason":"公开resolver没有返回锁定单一答案。"}
	var evidence_value: Variant = resolved.get("evidence")
	if not evidence_value is Dictionary:return {"ok":false,"reason":"resolver evidence不是字典。"}
	var evidence: Dictionary = evidence_value
	if evidence.get("source") != "gmsv/data/npc/"+SOURCE or evidence.get("source_sha") != SOURCE_SHA or evidence.get("table_sha") != ANSWER_TABLE_SHA:return {"ok":false,"reason":"resolver原源证据不匹配。"}
	if branch.get("keyword") != resolved.get("text"):return {"ok":false,"reason":"答案与原branch keyword不一致。"}
	var before_value: Variant = b.session.snapshot()
	if not before_value is Dictionary:return {"ok":false,"reason":"事务前profile不是字典。"}
	var before: Dictionary = before_value
	var save_serial_before: int = b.quest_save_serial
	var frame: Dictionary = b.quest_auto.transition_frame(b)
	# Exactly one source submit. No second token/choose and no synthetic Warp.
	var result_value: Variant = b.original_quests.choose(b,token_value,"submit",ANSWER)
	if not result_value is Dictionary:return {"ok":false,"reason":"OriginalQuests.choose返回类型错误。"}
	var result: Dictionary = result_value
	if not result.get("ok",false) or not result.get("closed",false):return {"ok":false,"reason":"原KEYWORD事务未成功关闭："+str(result.get("reason",""))}
	if not b.quest_auto.transition_current(b,frame):return {"ok":false,"reason":"原提交中owner/run身份变化；不对新run补ACK。"}
	var after_value: Variant = b.session.snapshot()
	if not after_value is Dictionary:return {"ok":false,"reason":"事务后profile不是字典。"}
	var expected_profile: Dictionary = before.duplicate(true)
	expected_profile["location"] = {"map_id":TARGET_MAP,"x":TARGET_CELL.x,"y":TARGET_CELL.y}
	var after: Dictionary = after_value
	if not Plan.same_source(after,expected_profile):return {"ok":false,"reason":"原Warp事务除location外改变了profile字段。"}
	var pending_after_value: Variant = b.original_quests.pending
	if not pending_after_value is Dictionary or not pending_after_value.is_empty():return {"ok":false,"reason":"原事务后仍残留pending。"}
	var authority_map: Variant = b.automation.position_map
	var authority_cell: Variant = b.automation.position_cell
	if not Plan.same_source(authority_map,TARGET_MAP) or not authority_cell is Vector2i or authority_cell != TARGET_CELL:return {"ok":false,"reason":"原Warp提交后的live authority不在固定目标。"}
	var arrival: bool = b.quest_arrival.has_arrival(b,TARGET_MAP,TARGET_CELL)
	if not arrival:return {"ok":false,"reason":"原脚本Warp没有留下合法arrival。"}
	return {"ok":true,"token":token_value,"branch":branch.duplicate(true),"resolver":resolved.duplicate(true),"result":result.duplicate(true),"save_serial_before":save_serial_before,"save_serial_after":b.quest_save_serial,"before":before.duplicate(true),"after":after.duplicate(true),"expected":expected_profile,"authority":{"map_id":TARGET_MAP,"cell":[TARGET_CELL.x,TARGET_CELL.y]},"arrival":arrival,"frame":frame.duplicate(true)}

static func observe_boss_page(b, reply_value: Variant) -> Dictionary:
	if not reply_value is Dictionary:return {"ok":false,"reason":"Boss reply不是字典。"}
	var pending_value: Variant = b.original_quests.pending
	if not pending_value is Dictionary:return {"ok":false,"reason":"Boss pending不是字典。"}
	var pending: Dictionary = pending_value.duplicate(true)
	if pending.get("phase") != "BATTLE":return {"ok":false,"reason":"首Boss没有停在原BATTLE页。"}
	var npc_value: Variant = pending.get("npc")
	var branch_value: Variant = pending.get("branch")
	if not npc_value is Dictionary or not branch_value is Dictionary:return {"ok":false,"reason":"Boss原NPC/branch形状错误。"}
	var active_value: Variant = b.quest_catalog.active_npc("100/sb_go.arg@11107:22:41")
	if not active_value is Dictionary or not Plan.same_source(active_value,npc_value):return {"ok":false,"reason":"Boss active source与pending不相等。"}
	var locked_active: Dictionary = _npc_source_ok(b,"first_boss","100/sb_go.arg@11107:22:41","79018dc8414c352eb90c5f388459b01d4985ba7eceb434d6e514639ad35127e0")
	if locked_active.is_empty() or not Plan.same_source(locked_active,npc_value):return {"ok":false,"reason":"Boss pending未匹配完整锁定catalog人物。"}
	var active: Dictionary = active_value
	var branch: Dictionary = branch_value
	var profile_value: Variant = b.session.snapshot()
	if not profile_value is Dictionary:return {"ok":false,"reason":"Boss选择profile不是字典。"}
	var profile: Dictionary = profile_value
	var branch_for_value: Variant = b.original_quests.branch_for(active,profile)
	if not branch_for_value is Dictionary or not Plan.same_source(branch_for_value,branch):return {"ok":false,"reason":"原branch_for没有选择完整Boss分支。"}
	var locked_branch: Dictionary = _locked_branch("first_boss")
	if locked_branch.is_empty() or not Plan.same_source(branch,locked_branch) or branch.get("type") != "BATTLE" or not Plan.same_source(branch.get("actions"),{"Battle":"527,526,528,529","Warp":"11107,23,35"}):return {"ok":false,"reason":"首Boss源分支/战斗队伍变化。"}
	var dialogue_value: Variant = reply_value.get("dialogue")
	if not dialogue_value is Dictionary:return {"ok":false,"reason":"Boss页面结构错误。"}
	var dialogue: Dictionary = dialogue_value
	var choices_value: Variant = dialogue.get("choices")
	var expected_choices: Array = [{"id":"yes","text":"是"},{"id":"no","text":"否"}]
	var token_value: Variant = pending.get("token")
	if not token_value is String or token_value.is_empty() or dialogue.get("token") != token_value or dialogue.get("npc_id") != "100/sb_go.arg@11107:22:41" or not choices_value is Array or not Plan.same_source(choices_value,expected_choices):return {"ok":false,"reason":"Boss页token/NPC/完整yes-no选项改变。"}
	return {"ok":true,"pending":pending,"dialogue":dialogue.duplicate(true),"npc":npc_value.duplicate(true),"branch":branch.duplicate(true),"profile":profile.duplicate(true),"authority":{"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}}
