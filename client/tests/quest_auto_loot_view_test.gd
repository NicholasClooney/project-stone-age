extends SceneTree
## UNRUN/UNREGISTERED: synthetic complete projection, no service/WS proof.
const View=preload("res://scripts/quest_auto_loot_view.gd")
func sample()->Dictionary:
	return {"run_id":"synthetic","budget":{"enabled":false,"reason":"内部测试仍未开放","default_limit_minutes":30,"activity":"battle","finish_current_battle":true,"recovery_blocked":false,"can_start":false,"can_stop":false,"can_adjust_limit":false,"can_reset":false,"entry":{"step_id":"jewels:hunt:2760","budget_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":0,"revision":1,"target_item_id":2760,"target_count":1,"limit_ms":1000,"saved_used_ms":500,"used_ms":1200,"limit_reached":true,"existing_items":2,"new_items":1,"saved_battles":3}}}
func _initialize()->void:
	var view=View.new()
	assert(view.lines().has("限时刷物尚未开放。"))
	var one=sample()
	view.replace_snapshot(one,true)
	assert(view.lines().has("本步已用 1200 ms / 上限 1000 ms"))
	assert(view.lines().has("限时刷物尚未开放。"))
	one.budget.entry.used_ms=1300 # Same revision, newer cached sample accepted.
	view.replace_snapshot(one,true)
	assert(view.lines().has("本步已用 1300 ms / 上限 1000 ms"))
	one.budget.entry.used_ms=9999 # Caller mutation must not alter stored snapshot.
	view.disconnected()
	view.replace_snapshot(one,false)
	assert(view.stale and view.lines().has("本步已用 1300 ms / 上限 1000 ms"))
	one.budget.entry=null;one.budget.recovery_blocked=true
	one.budget.activity="recovery_locked"
	view.replace_snapshot(one,true)
	assert(not view.stale and view.lines().has("中断时段用时不确定，需确认预算；恢复锁定，不自动开战。"))
	assert(not "本步已用" in "\n".join(view.lines()))
	one=sample();one.budget.activity="completed";one.budget.finish_current_battle=false
	view.replace_snapshot(one,true)
	assert(view.lines().has("目标已完成，保留预算历史。"))
	assert(not view.lines().has("预算已到限，停止新尝试。"))
	view.replace_snapshot({},true)
	assert(not "本步已用" in "\n".join(view.lines()))
	assert(View.duration(1.5)=="—" and View.duration(true)=="—")
	quit(0)
