extends RefCounted
## UNRUN test-only selector addition. The existing Request10 selector remains
## authoritative for [9,11,10]; this adds only one WPM keyword and one Boss page.
const Prefix = preload("res://server/quest_auto_munde_request10_candidate.gd")
const Adapter = preload("res://server/quest_auto_munde_keyword_adapter_candidate.gd")

static func select(b, job_id: int = 8, keyword_committed: bool = false) -> Dictionary:
	return Adapter.select(b, job_id, keyword_committed)

static func continuation_intent(stage: String, keyword_committed: bool) -> String:
	return Adapter.continuation_intent(stage, keyword_committed)

static func exact_travel_step(step: Dictionary, keyword_committed: bool) -> bool:
	return Adapter.exact_travel_step(step, keyword_committed)

static func submit_original_keyword(b, reply: Variant) -> Dictionary:
	return Adapter.submit_original_keyword(b, reply)

static func observe_boss_page(b, reply: Variant) -> Dictionary:
	return Adapter.observe_boss_page(b, reply)
