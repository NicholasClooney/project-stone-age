extends RefCounted
## Pure numerical filter. Callers explicitly supply current or projected stats.
## Disabled conditions pass; defaults (blue dragons: total >=624 OR attack >292)
## live in res://data/automation_defaults.json.
const METRICS := ["sum", "attack", "defence", "speed"]

static func evaluate(stats: Dictionary, settings: Dictionary) -> bool:
	var conditions: Dictionary = settings.get("conditions", {})
	var any_match := false
	var all_match := true
	var count := 0
	for metric in METRICS:
		var condition: Dictionary = conditions.get(metric, {})
		if not bool(condition.get("enabled", false)):continue
		count += 1
		var available := stats.has(metric)
		var value := float(stats.get(metric, 0))
		if metric == "sum":
			available = stats.has("attack") and stats.has("defence") and stats.has("speed")
			value = float(stats.get("attack", 0)) + float(stats.get("defence", 0)) + float(stats.get("speed", 0))
		var minimum := float(condition.get("value", 0))
		var passes := available and (value > minimum if bool(condition.get("strict", false)) else value >= minimum)
		any_match = any_match or passes
		all_match = all_match and passes
	return count == 0 or (any_match if settings.get("mode", "all") == "any" else all_match)

static func defaults(template_id: int) -> Dictionary:
	# stop_after: matches to keep before the loop stops; 0 never stops, 1 is the classic single stop.
	# Values (and per-species overrides) come from res://data/automation_defaults.json.
	return preload("res://scripts/automation_settings.gd").default_stat_filter(template_id)

# Rolling warehouse keep per metric (top N by that metric), independent of enabled.
static func keep_counts(settings: Dictionary) -> Dictionary:
	var result := {}
	for metric in METRICS:result[metric] = int(settings.get("conditions", {}).get(metric, {}).get("keep", 0))
	return result

static func enabled(settings: Dictionary) -> bool:
	for condition in settings.get("conditions", {}).values():
		if condition.get("enabled", false):return true
	return false

static func describe(stats: Dictionary, settings: Dictionary) -> String:
	var parts: PackedStringArray = []
	for metric in METRICS:
		var condition: Dictionary = settings.get("conditions", {}).get(metric, {})
		if not condition.get("enabled", false):continue
		var value := int(stats.get(metric, 0))
		if metric == "sum":value = int(stats.get("attack",0)) + int(stats.get("defence",0)) + int(stats.get("speed",0))
		var passes:bool=value>int(condition.value) if condition.get("strict",false) else value>=int(condition.value)
		parts.append("%s%d（要求%s%d，%s）" % [{"sum":"三围合","attack":"攻","defence":"防","speed":"敏"}[metric],value,">" if condition.get("strict",false) else "≥",int(condition.value),"满足" if passes else "未满足"])
	return ("任一满足：" if settings.get("mode","all") == "any" else "全部满足：") + "；".join(parts)
