extends RefCounted
## Unwired v1 projection draft. Input is ONE complete quest_auto snapshot,
## not a ledger, delta, permission token or command. Caller owns connection
## isolation. Budget revision is NOT a clock sample sequence.
var _snapshot:Dictionary={}
var stale:bool=true

func replace_snapshot(quest_auto_snapshot:Dictionary,connection_current:bool)->void:
	if not connection_current:
		stale=true
		return
	_snapshot=quest_auto_snapshot.duplicate(true)
	stale=false

func disconnected()->void:
	stale=true # Keep last received values; never extrapolate them.

static func duration(value)->String:
	if not (value is int or value is float):return "—"
	if not is_finite(float(value)) or value<0 or floor(value)!=value:return "—"
	return "%s ms"%str(value) # Exact server sample, including over-limit values.

func lines()->Array[String]:
	var result:Array[String]=[]
	var budget:Dictionary=_snapshot.get("budget",{})
	if budget.get("enabled",false)!=true:
		result.append("限时刷物尚未开放。")
	if stale:result.append("连接状态已过期；仅显示最后收到的记录，不推算当前用时。")
	var reason:String=str(budget.get("reason",""))
	if not reason.is_empty():result.append(reason)
	if budget.get("recovery_blocked",false)==true:
		result.append("中断时段用时不确定，需确认预算；恢复锁定，不自动开战。")
	var entry=budget.get("entry",null)
	if entry is Dictionary and not entry.is_empty():
		result.append("本步已用 %s / 上限 %s"%[duration(entry.get("used_ms")),duration(entry.get("limit_ms"))])
		result.append("可信已存用时 %s（恢复锁定时仅为已知下界）"%duration(entry.get("saved_used_ms")))
		result.append("已保存战数 %s · 本步累计实际获得 %s · 初始已有 %s（非当前库存）"%[str(entry.get("saved_battles","—")),str(entry.get("new_items","—")),str(entry.get("existing_items","—"))])
		if budget.get("finish_current_battle",false)==true:
			result.append("本场安全结算后停止；不再开始下一场。")
	var activity:String=str(budget.get("activity","unavailable"))
	var labels:Dictionary={"inactive":"尚无本步预算。","running":"按原规则推进刷物。","battle":"当前战斗计入活跃用时。","settling":"结果结算计算计入活跃用时。","storage_paused":"写盘／保存失败修复等待中，预算暂停计时；原因以上述服务端说明为准。","limit_reached":"预算已到限，停止新尝试。","stopped":"本步已停止，保留预算历史。","completed":"目标已完成，保留预算历史。","recovery_locked":"恢复不确定锁定，需确认预算。"}
	# Core selects priority: root OR entry lock; then storage/live battle;
	# otherwise completed before limit. Never infer it from counters here.
	if labels.has(activity):result.append(labels[activity])
	result.append("新步骤默认时限：%s 分钟；已有预算不变。"%str(budget.get("default_limit_minutes","—")))
	result.append("调限、重置及刷物控制尚无公开命令。")
	return result
