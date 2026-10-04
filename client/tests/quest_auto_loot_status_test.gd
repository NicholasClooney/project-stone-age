extends SceneTree
## Proposed pure formatting test, UNRUN; apply auto-status.diff before use.
## No scene, panel, transport, backend, persistence or command execution.
const Travel=preload("res://scripts/quest_helper_travel.gd")
class StubLink extends RefCounted:
	var online:bool=true
	func is_local()->bool:return false
class StubWorld extends Node:
	var state:Dictionary={"derived":{"quest_auto":{}}}
	var link=StubLink.new()
func _initialize()->void:
	var world=StubWorld.new()
	var travel=Travel.new();travel.configure(world)
	var auto:Dictionary={"message":"原任务状态","mode_notice":"原模式说明","phase":"travel"}
	world.state.derived.quest_auto=auto
	assert(travel.auto_status()=="原任务状态\n原模式说明")
	auto.budget={}
	assert(travel.auto_status()=="原任务状态\n原模式说明")
	auto.budget={"enabled":false,"reason":"限时刷物尚未开放。","default_limit_minutes":30,"activity":"unavailable","finish_current_battle":false,"recovery_blocked":false,"can_start":false,"can_stop":false,"can_adjust_limit":false,"can_reset":false,"entry":null}
	var shown:String=travel.auto_status()
	assert(shown.begins_with("原任务状态\n原模式说明\n"))
	assert(shown.contains("限时刷物尚未开放。") and not shown.contains("本步已用") and not shown.contains("0.0 / 0.0"))
	auto.budget.recovery_blocked=true
	assert(travel.auto_status().contains("中断时段用时不确定，需确认预算"))
	auto.budget.recovery_blocked=false
	auto.budget.entry={"step_id":"jewels:hunt:2760","budget_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","generation":0,"revision":1,"target_item_id":2760,"target_count":1,"limit_ms":1800000,"saved_used_ms":1000,"used_ms":1250,"limit_reached":false,"existing_items":2,"new_items":1,"saved_battles":3}
	shown=travel.auto_status()
	assert(shown.contains("本步已用 1250 ms / 上限 1800000 ms") and shown.contains("限时刷物尚未开放。"))
	assert(shown.contains("已保存战数 3") and shown.contains("初始已有 2（非当前库存）"))
	auto.budget.entry.used_ms=1500
	assert(travel.auto_status().contains("本步已用 1500 ms")) # same revision sample
	world.link.online=false
	shown=travel.auto_status()
	assert(shown.contains("连接状态已过期") and shown.contains("本步已用 1500 ms"))
	assert(travel.auto_status()==shown) # repeat formatting does not charge elapsed time
	world.link.online=true
	auto.budget={"used_seconds":99,"limit_seconds":88} # Unknown old placeholder: never convert it.
	shown=travel.auto_status()
	assert(shown.contains("限时刷物尚未开放。") and not shown.contains("本步已用") and not shown.contains("0.0 / 0.0"))
	auto.phase="manual";auto.pause_reason="未支持服务，请人工处理"
	assert(travel.auto_status()=="未支持服务，请人工处理")
	auto.phase="travel";auto.detached=true
	assert(travel.auto_status()=="等待设备确认当前位置 · 原任务状态")
	travel.active=true;travel.phase="auto_download"
	assert(travel.auto_status()=="正在准备任务地图…")
	travel.free();world.free()
	quit(0)
