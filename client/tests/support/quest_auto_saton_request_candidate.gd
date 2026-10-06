extends RefCounted
## UNRUN test-only selector for the first source-locked Saton REQUEST.
## It never changes profile flags, inventory, authority, arrival or position.
const Plan = preload("res://server/quest_auto_saton_plan.gd")

static func select(b, job_id: int) -> Dictionary:
	if job_id != 10:
		return {"status":"manual","stage":"unsupported_job","reason":"仅萨顿job10。"}
	return Plan.request_proposal(b)
