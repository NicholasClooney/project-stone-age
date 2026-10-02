extends RefCounted
## Pure numerical filter. Callers explicitly supply current or projected stats.
## Disabled conditions pass; defaults live in res://data/automation_defaults.json.
##
## A saved filter picks its threshold_mode per species:
##   relative (default), 最高 − x: a condition {enabled, minus, value, keep}
##     asks for the best Lv120 value of that metric among the player's own pets
##     of the species (carried and warehouse; pets under Lv120 by their exact
##     Lv120 projection) minus x, so it rolls upward as better pets arrive.
##     With no pet of the species there is no maximum: the find-pet cycle
##     surveys first (摸底, needs_survey()).
##   absolute, ≥ 数值: the condition asks for its fixed `value`; no 摸底 and
##     better pets do not move it.
## Each condition keeps both minus and value, so switching loses neither.
## resolve() turns saved conditions into resolved ones ({value, strict}, no
## minus) that evaluate() and the native helper read.
const METRICS := ["sum", "attack", "defence", "speed"]
const METRIC_NAMES := {"sum":"三围合", "attack":"攻击", "defence":"防御", "speed":"敏捷"}
## Keys a player can rank qualifying pets by (达标只保留前 N 只), in the fixed
## order that breaks ties after the player's own order.
const THRESHOLD_MODES := ["relative", "absolute"]
const THRESHOLD_MODE_NAMES := {"relative":"相对：最高 − x", "absolute":"绝对：≥ 数值"}
const RANK_KEYS := ["sum", "attack", "defence", "speed", "max_hp"]
const RANK_NAMES := {"sum":"三围合", "attack":"攻击", "defence":"防御", "speed":"敏捷", "max_hp":"体力"}

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
		# A relative condition that was never resolved cannot pass.
		var minimum := INF if relative(condition, settings) else float(condition.get("value", INF))
		var passes := available and (value > minimum if bool(condition.get("strict", false)) else value >= minimum)
		any_match = any_match or passes
		all_match = all_match and passes
	return count == 0 or (any_match if settings.get("mode", "all") == "any" else all_match)

## The best value of each metric (sum, attack, defence, speed) among `stats`
## (the Lv120 stats of the species' pets), {} when there are none; `base` is an
## earlier result to raise.
static func maxima(stats: Array, base: Dictionary = {}) -> Dictionary:
	var result := base.duplicate()
	for item in stats:
		for metric in METRICS:
			var value := rank_value(item, metric)
			if not result.has(metric) or value > int(result[metric]):result[metric] = value
	return result

## Whether a filter uses fixed values (≥ 数值) rather than 最高 − x.
static func absolute(settings: Dictionary) -> bool:
	return str(settings.get("threshold_mode", "relative")) == "absolute"

## Whether a condition of a `settings` filter is 最高 − x (saved form) rather
## than a fixed or already resolved value.
static func relative(condition: Dictionary, settings: Dictionary = {}) -> bool:
	return condition.has("minus") and not absolute(settings)

## The filter with every condition resolved: in relative mode value = best − x
## against `best` (maxima()); in absolute mode the saved value. Compared with
## ≥. Without a maximum a relative condition stays unresolved (no value) and
## fails; the cycle surveys first (needs_survey).
static func resolve(settings: Dictionary, best: Dictionary) -> Dictionary:
	var result := settings.duplicate(true)
	var fixed := absolute(settings)
	var conditions: Dictionary = result.get("conditions", {})
	for metric in conditions:
		var condition: Dictionary = conditions[metric]
		if not condition.has("minus"):continue
		var minus := int(condition.minus)
		condition.erase("minus")
		if fixed:
			if condition.has("value"):condition["strict"] = false
			continue
		condition.erase("value")
		condition.erase("strict")
		# Without a baseline admit the first candidate; absolute gates are unchanged.
		condition["value"] = int(best[metric]) - minus if best.has(metric) else 0
		condition["strict"] = false
	return result

## True when an enabled relative condition has no maximum to count from (the
## player has no pet of the species): the cycle surveys (摸底) first. Never in
## absolute mode: its thresholds are known.
static func needs_survey(settings: Dictionary, best: Dictionary) -> bool:
	if absolute(settings):return false
	for metric in METRICS:
		var condition: Dictionary = settings.get("conditions", {}).get(metric, {})
		if bool(condition.get("enabled", false)) and relative(condition, settings) and not best.has(metric):return true
	return false

## The values an absolute switch starts from, so what is hunted does not jump:
## each metric's current 最高 − x when the player has a pet of the species,
## else the saved (default) value. Metrics in `own` keep the player's value.
static func absolute_values(settings: Dictionary, best: Dictionary, own: Array = []) -> Dictionary:
	var result := {}
	for metric in METRICS:
		var condition: Dictionary = settings.get("conditions", {}).get(metric, {})
		var value := int(condition.get("value", 0))
		if not metric in own and best.has(metric):value = int(best[metric]) - int(condition.get("minus", 0))
		result[metric] = clampi(value, 0, 3000)
	return result

## One condition as the player reads it. Relative: 「三围合 ≥ 最高 627 − 1 =
## 626」, or 「三围合 ≥ 最高 − 1（无基线，首个合格候选建立最高）」 without a maximum.
## Absolute (`fixed`): 「三围合 ≥ 624（现有最高 627）」, or 「三围合 ≥ 624」.
static func describe_condition(metric: String, condition: Dictionary, best: Dictionary, fixed: bool = false) -> String:
	var name: String = METRIC_NAMES.get(metric, metric)
	if fixed:
		var text := "%s ≥ %d" % [name, int(condition.get("value", 0))]
		return text + ("（现有最高 %d）" % int(best[metric]) if best.has(metric) else "")
	if not condition.has("minus"):return "%s %s %d" % [name, ">" if bool(condition.get("strict", false)) else "≥", int(condition.get("value", 0))]
	# A negative x asks for more than the best: 最高 + n.
	var minus := int(condition.get("minus", 0))
	var offset := ("− %d" % minus) if minus >= 0 else ("+ %d" % -minus)
	if not best.has(metric):return "%s ≥ 最高 %s（无基线，首个合格候选建立最高）" % [name, offset]
	return "%s ≥ 最高 %d %s = %d" % [name, int(best[metric]), offset, int(best[metric]) - minus]

## Every enabled condition, joined by 或 / 且 as the mode says; "" when none.
static func describe_thresholds(settings: Dictionary, best: Dictionary) -> String:
	var parts: PackedStringArray = []
	var fixed := absolute(settings)
	for metric in METRICS:
		var condition: Dictionary = settings.get("conditions", {}).get(metric, {})
		if bool(condition.get("enabled", false)):parts.append(describe_condition(metric, condition, best, fixed))
	return ("，或 " if settings.get("mode", "all") == "any" else "，且 ").join(parts)

static func defaults(template_id: int) -> Dictionary:
	# Values (and per-species overrides) come from res://data/automation_defaults.json.
	return preload("res://scripts/automation_settings.gd").default_stat_filter(template_id)

# Rolling warehouse keep per metric (top N by that metric), independent of enabled.
static func keep_counts(settings: Dictionary) -> Dictionary:
	var result := {}
	for metric in METRICS:result[metric] = int(settings.get("conditions", {}).get(metric, {}).get("keep", 0))
	return result

static func rank_value(pet: Dictionary, key: String) -> int:
	if key == "sum":return int(pet.get("attack", 0)) + int(pet.get("defence", 0)) + int(pet.get("speed", 0))
	return int(pet.get(key, 0))

## The full comparison order: the player's keys, then the remaining RANK_KEYS.
static func rank_order(order: Array) -> Array:
	var result: Array = []
	for key in order + RANK_KEYS:
		if str(key) in RANK_KEYS and not result.has(str(key)):result.append(str(key))
	return result

## Pets best first: each key descending in rank_order(order), then the older
## pet (smaller pet id number) first, so the result never depends on list order.
static func ranked(pets: Array, order: Array) -> Array:
	var keys := rank_order(order)
	var result := pets.duplicate()
	result.sort_custom(func(a, b):
		for key in keys:
			var va := rank_value(a, key)
			var vb := rank_value(b, key)
			if va != vb:return va > vb
		return _id_number(a) < _id_number(b))
	return result

static func _id_number(pet: Dictionary) -> int:
	var suffix := str(pet.get("pet_id", "")).trim_prefix("pet-")
	return int(suffix) if suffix.is_valid_int() else 0

static func describe_order(order: Array) -> String:
	var names: PackedStringArray = []
	for key in order:
		if RANK_NAMES.has(str(key)):names.append(RANK_NAMES[str(key)])
	return " → ".join(names)

static func enabled(settings: Dictionary) -> bool:
	for condition in settings.get("conditions", {}).values():
		if condition.get("enabled", false):return true
	return false

static func describe(stats: Dictionary, settings: Dictionary) -> String:
	var parts: PackedStringArray = []
	for metric in METRICS:
		var condition: Dictionary = settings.get("conditions", {}).get(metric, {})
		if not condition.get("enabled", false) or not condition.has("value"):continue
		var value := int(stats.get(metric, 0))
		if metric == "sum":value = int(stats.get("attack",0)) + int(stats.get("defence",0)) + int(stats.get("speed",0))
		var passes:bool=value>int(condition.value) if condition.get("strict",false) else value>=int(condition.value)
		parts.append("%s%d（要求%s%d，%s）" % [{"sum":"三围合","attack":"攻","defence":"防","speed":"敏"}[metric],value,">" if condition.get("strict",false) else "≥",int(condition.value),"满足" if passes else "未满足"])
	return ("任一满足：" if settings.get("mode","all") == "any" else "全部满足：") + "；".join(parts)
