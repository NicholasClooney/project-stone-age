extends RefCounted
## Automation settings for 自动练级 / 自动抓极品, shared by the backend and
## clients. Defaults live in res://data/automation_defaults.json; the character
## profile keeps only the player's overrides (`automation_settings`), so an
## improved default reaches everyone who has not changed that value.
##
## Overrides shape (every part optional):
##   training     {xp, compact, spirit (用精灵补血: a healing 精灵 before a
##                 回复药 at the 停机线), side_heal (全体补血: 恩惠 when
##                 anyone on the side is below this percent, 0 off), hp, level, level_explicit, limit, preset}
##   capture      {hp, pet, pet_id, pet_max_level, fallback_attempts (1–30),
##                 fallback_rate (0–98), fallback_hp (1–99)}
##   party        {auto (组队自动战斗: a party member's slot commands itself
##                 from its 自动练级 preset each turn), compact (快速战斗 for
##                 that: the device shows a status line, not the battle view)}
##                 (LAN phase 4c, docs/development/lan-profiles.md)
##   hunt         {template, level_one, auto_capture, train_after_capture, total, offsets, rate, limit, fast, showcase, queue,
##                 resume (重启后自动恢复), stat_species (属性条件 shows it; -1 follows the target),
##                 stop_after (找到N只后停止, one for the whole find-pet run:
##                 pets it keeps, qualifiers or with no 属性条件 every Lv.120
##                 pet, before it stops; 0 never stops, 1 stops to compare),
##                 clean_only (只进无其他敌人的遇敌: a Lv.1 hunt skips troops with
##                 any enemy above Lv.1, pet_hunt_rules.gd clean_troop),
##                 mixed_if_stats (still take such a troop in a find-pet cycle
##                 when the pet meets its enabled 属性条件, after a battle
##                 forecast: server/battle_forecast.gd)}
##   stat_filters {"<template id>": {mode, threshold_mode, keep_rule, conditions: {sum|attack|defence|speed: {enabled, minus, value, keep}}}}
##     threshold_mode "relative" (default): a condition asks for 最高 − minus,
##     the best Lv120 value of that metric among the player's own pets of the
##     species less `minus`; "absolute": at least `value`
##     (pet_stat_filter.gd resolve). Both numbers are kept, so switching loses
##     neither. An old fixed threshold saved with strict (>) becomes value + 1.
##     keep_rule: 保留规则 (scripts/keep_rule.gd) {tiers, per_tier, order,
##     champions, champion_stats, auto}: order is 1 to 5 distinct keys of sum,
##     attack, defence, speed, max_hp (pet_stat_filter.gd RANK_KEYS);
##     champion_stats any of attack, defence, speed, max_hp; auto tidies the
##     whole species after each pet the find-pet cycle stores. It replaced
##     keep_qualified/rank (达标只保留前 N 只); a stored rank becomes the order.
##     A per-species stop_after (older saves and clients) is accepted and
##     dropped; an old save's becomes hunt.stop_after (_migrate_stop_after).
## Per-device choices (battle playback speed, minimized windows) are not here.
const PATH := "res://data/automation_defaults.json"
## What players call hunt.showcase: keep searching in the background while
## watching the capture and 自动练级. The one place the name is written; the
## switch, the info block and the server's lines use it.
const SHOWCASE_NAME := "后台搜宠"
## 摸底: how long the find-pet cycle scans a species with no pet of its own
## (so no 最高 to count from) before choosing what to catch, in seconds.
const SURVEY_SECONDS := 120
const METRICS := ["sum","attack","defence","speed"]
const CONDITION_SPEC := {"enabled":["bool"],"minus":["int",-100,1000],"value":["int",0,3000],"keep":["int",0,1000]}
const KEEP_RULE_SPEC := {"tiers":["int",0,20],"per_tier":["int",0,1000],"order":["rank"],"champions":["int",0,1000],"champion_stats":["stats"],"auto":["bool"]}
const FILTER_SPEC := {"mode":["enum",["all","any"]],"threshold_mode":["enum",["relative","absolute"]],"keep_rule":KEEP_RULE_SPEC,
	"conditions":{"sum":CONDITION_SPEC,"attack":CONDITION_SPEC,"defence":CONDITION_SPEC,"speed":CONDITION_SPEC}}
const SPEC := {
	"training":{"xp":["enum",[1,2,10,100]],"compact":["bool"],"spirit":["bool"],"side_heal":["int",0,100],"hp":["int",1,100],"level":["int",0,120],"level_explicit":["bool"],"limit":["int",1,100000],"preset":["enum",["attack","capture","train_pet"]]},
	"party":{"auto":["bool"],"compact":["bool"]},
	"capture":{"hp":["int",1,100],"pet":["int",-2,29],"pet_id":["string",32],"pet_max_level":["int",1,120],"fallback_attempts":["int",1,30],"fallback_rate":["int",0,98],"fallback_hp":["int",1,99]},
	"hunt":{"template":["int",-1,1000000],"level_one":["bool"],"auto_capture":["bool"],"train_after_capture":["bool"],"total":["int",-8,8],"offsets":["offsets"],"rate":["int",0,100000],"limit":["int",0,1000000],"fast":["bool"],"showcase":["bool"],"queue":["int",1,50],"resume":["bool"],"clean_only":["bool"],"mixed_if_stats":["bool"],"stat_species":["int",-1,1000000],"stop_after":["int",0,100000]},
}
static var _defaults: Dictionary = {}

static func defaults() -> Dictionary:
	if _defaults.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_defaults = _clean(parsed) if parsed is Dictionary else {}
	return _defaults

## Effective training, capture and hunt settings: defaults merged with overrides.
static func effective(overrides: Dictionary) -> Dictionary:
	var result := {}
	for section in SPEC:result[section] = merged(defaults().get(section,{}),_dict(overrides.get(section,{})))
	# A stored level without a flag is a player's own target (older clients).
	var training := _dict(overrides.get("training",{}))
	if training.has("level") and not training.has("level_explicit"):result.training.level_explicit = true
	return result

static func default_stat_filter(template_id: int) -> Dictionary:
	var species: Dictionary = defaults().get("species",{}).get(str(template_id),{})
	return merged(defaults().get("stat_filter",{}),species.get("stat_filter",{}))

## Effective 120-level stat filter for one species.
static func stat_filter(overrides: Dictionary, template_id: int) -> Dictionary:
	return merged(default_stat_filter(template_id),_dict(_dict(overrides.get("stat_filters",{})).get(str(template_id),{})))

## Effective filters (int template id -> filter) for every species that has a
## default of its own or an override; others use default_stat_filter().
static func stat_filters(overrides: Dictionary) -> Dictionary:
	var result := {}
	for id in defaults().get("species",{}):result[int(id)] = stat_filter(overrides,int(id))
	for id in _dict(overrides.get("stat_filters",{})):result[int(id)] = stat_filter(overrides,int(id))
	return result

## Flat settings the battle runner and capture policy read (the former
## auto_start `settings` shape). An automatic level target follows the player.
static func runner_settings(overrides: Dictionary, player_level: int) -> Dictionary:
	var all := effective(overrides)
	var training: Dictionary = all.training
	var capture: Dictionary = all.capture
	var level := int(training.level) if bool(training.level_explicit) else (0 if player_level>=120 else 120)
	return {"xp":int(training.xp),"compact":bool(training.compact),"hp":int(training.hp),"level":level,"level_explicit":bool(training.level_explicit),
		"limit":int(training.limit),"preset":str(training.preset),"spirit":bool(training.get("spirit",true)),"side_heal":int(training.get("side_heal",50)),"capture_hp":int(capture.hp),"capture_pet":int(capture.pet),
		"capture_pet_id":str(capture.pet_id),"capture_pet_max_level":int(capture.pet_max_level),"capture_fallback_attempts":int(capture.fallback_attempts),"capture_fallback_rate":int(capture.fallback_rate),"capture_fallback_hp":int(capture.fallback_hp)}

## Hunt scan filter without the location-dependent `usable` list.
static func hunt_filter(overrides: Dictionary) -> Dictionary:
	var hunt: Dictionary = effective(overrides).hunt
	return {"template":int(hunt.template),"level_one":bool(hunt.level_one),"total":int(hunt.total),"offsets":hunt.offsets.duplicate(),
		"rate":int(hunt.rate),"limit":int(hunt.limit),"auto_capture":bool(hunt.auto_capture),"fast":bool(hunt.fast),"showcase":bool(hunt.showcase),"queue":int(hunt.queue),
		"clean_only":bool(hunt.clean_only),"mixed_if_stats":bool(hunt.mixed_if_stats)}

static func device_default(key: String, fallback: Variant) -> Variant:
	return defaults().get("device",{}).get(key,fallback)

## Deep-merges a partial update into overrides after validating all of it.
## A null value removes that override (back to the default); a null section
## resets the section. Returns {ok, overrides} or {ok:false, reason}.
static func apply_patch(overrides: Dictionary, patch: Variant) -> Dictionary:
	if not patch is Dictionary:return _fail("settings must be an object")
	var result: Dictionary = overrides.duplicate(true)
	for key in patch:
		var section := str(key)
		var value = patch[key]
		if section=="stat_filters":
			if value==null:result.erase(section);continue
			if not value is Dictionary:return _fail("invalid stat_filters")
			var filters: Dictionary = _dict(result.get("stat_filters",{})).duplicate(true)
			for template in value:
				var id := str(template)
				if not id.is_valid_int() or int(id)<0:return _fail("invalid stat_filters key "+id)
				id = str(int(id))
				var given = value[template]
				# Older clients still send the per-species 找到N只后停止: ignored.
				if given is Dictionary and given.has("stop_after"):
					given = given.duplicate();given.erase("stop_after")
				var reply := _merge(_dict(filters.get(id,{})),given,FILTER_SPEC,"stat_filters."+id)
				if not reply.ok:return reply
				filters[id] = reply.value
			result.stat_filters = filters
		elif SPEC.has(section):
			if value==null:result.erase(section);continue
			var reply := _merge(_dict(result.get(section,{})),value,SPEC[section],section)
			if not reply.ok:return reply
			result[section] = reply.value
		else:return _fail("unknown setting "+section)
	return {"ok":true,"overrides":prune(result)}

## Drops overrides equal to their default and empty groups.
static func prune(overrides: Dictionary) -> Dictionary:
	var result := {}
	for section in overrides:
		if section=="stat_filters":
			var filters := {}
			for id in overrides.stat_filters:
				var kept := _prune_node(overrides.stat_filters[id],default_stat_filter(int(id)))
				if not kept.is_empty():filters[id] = kept
			if not filters.is_empty():result.stat_filters = filters
		else:
			var kept := _prune_node(overrides[section],defaults().get(section,{}))
			if not kept.is_empty():result[section] = kept
	return result

## Keeps the valid parts of stored overrides (an older or hand-edited save).
static func sanitize(stored: Variant) -> Dictionary:
	if not stored is Dictionary:return {}
	var result := {}
	for section in SPEC:
		var kept := _valid_part(stored.get(section),SPEC[section])
		if not kept.is_empty():result[section] = kept
	_migrate_stop_after(stored,result)
	var filters := {}
	for id in _dict(stored.get("stat_filters",{})):
		if not str(id).is_valid_int() or int(str(id))<0:continue
		var kept := _valid_part(_migrate_filter(stored.stat_filters[id]),FILTER_SPEC)
		if not kept.is_empty():filters[str(int(str(id)))] = kept
	if not filters.is_empty():result.stat_filters = filters
	return prune(result)

## 找到N只后停止 was per species (stat_filters.<id>.stop_after); now it is
## hunt.stop_after for the whole run. An old save takes the value of the
## species the player last edited (hunt.stat_species, or the hunt target when
## it follows the target) if that one had its own, else the default (0).
static func _migrate_stop_after(stored: Dictionary, result: Dictionary) -> void:
	var filters := _dict(stored.get("stat_filters",{}))
	var old := false
	for id in filters:old = old or (filters[id] is Dictionary and filters[id].has("stop_after"))
	if not old or _dict(result.get("hunt",{})).has("stop_after"):return
	var hunt: Dictionary = merged(defaults().get("hunt",{}),_dict(result.get("hunt",{})))
	var species := int(hunt.get("stat_species",-1))
	if species<0:species = int(hunt.get("template",-1))
	var checked := _leaf(SPEC.hunt.stop_after,_dict(filters.get(str(species),{})).get("stop_after"))
	var section := _dict(result.get("hunt",{}))
	section.stop_after = checked[0] if not checked.is_empty() else int(defaults().get("hunt",{}).get("stop_after",0))
	result.hunt = section

## 达标只保留前 N 只 (keep_qualified, rank) became keep_rule: a rank the player
## chose becomes the tier order (三围合 is what tiers group by, so it is dropped).
## An old fixed threshold saved with strict (>) becomes the same ≥ value + 1.
static func _migrate_filter(value: Variant) -> Variant:
	if not value is Dictionary:return value
	var result: Dictionary = value.duplicate(true)
	if result.get("conditions") is Dictionary:
		for metric in result.conditions:
			var condition = result.conditions[metric]
			if not condition is Dictionary or not condition.has("strict"):continue
			if condition.strict is bool and condition.strict and _int(condition.get("value"))!=null:condition.value = int(_int(condition.value))+1
			condition.erase("strict")
	if not result.has("rank"):return result
	var order := []
	var checked := _leaf(["rank"],result.rank)
	if not checked.is_empty():
		for key in checked[0]:
			if key!="sum":order.append(key)
	var rule := _dict(result.get("keep_rule",{})).duplicate(true)
	if not order.is_empty() and not rule.has("order"):rule.order = order
	if not rule.is_empty():result.keep_rule = rule
	return result

static func _valid_part(value: Variant, spec: Dictionary) -> Dictionary:
	var result := {}
	if not value is Dictionary:return result
	for raw in value:
		var key := str(raw)
		if not spec.has(key):continue
		if spec[key] is Dictionary:
			var inner := _valid_part(value[raw],spec[key])
			if not inner.is_empty():result[key] = inner
		else:
			var checked := _leaf(spec[key],value[raw])
			if not checked.is_empty():result[key] = checked[0]
	return result

## The leaves of wanted that differ from base: the patch that turns base into wanted.
static func diff(base: Dictionary, wanted: Dictionary) -> Dictionary:
	var result := {}
	for key in wanted:
		if wanted[key] is Dictionary and base.get(key) is Dictionary:
			var inner := diff(base[key],wanted[key])
			if not inner.is_empty():result[key] = inner
		elif not _same(base.get(key),wanted[key]):result[key] = wanted[key]
	return result

static func merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for key in over:
		if over[key] is Dictionary and result.get(key) is Dictionary:result[key] = merged(result[key],over[key])
		else:result[key] = over[key].duplicate(true) if (over[key] is Dictionary or over[key] is Array) else over[key]
	return result

static func _merge(current: Dictionary, patch: Variant, spec: Dictionary, path: String) -> Dictionary:
	if not patch is Dictionary:return _fail("invalid "+path)
	var result: Dictionary = current.duplicate(true)
	for raw in patch:
		var key := str(raw)
		if not spec.has(key):return _fail("unknown setting %s.%s" % [path,key])
		var value = patch[raw]
		if value==null:result.erase(key);continue
		if spec[key] is Dictionary:
			var reply := _merge(_dict(result.get(key,{})),value,spec[key],path+"."+key)
			if not reply.ok:return reply
			if reply.value.is_empty():result.erase(key)
			else:result[key] = reply.value
			continue
		var checked := _leaf(spec[key],value)
		if checked.is_empty():return _fail("invalid %s.%s" % [path,key])
		result[key] = checked[0]
	return {"ok":true,"value":result}

## [normalized value] when valid, else [].
static func _leaf(spec: Array, value: Variant) -> Array:
	match str(spec[0]):
		"bool":return [value] if value is bool else []
		"int":
			var number = _int(value)
			return [number] if number!=null and number>=int(spec[1]) and number<=int(spec[2]) else []
		"string":return [value] if value is String and value.length()<=int(spec[1]) else []
		"enum":
			var number = _int(value)
			if number!=null and number in spec[1]:return [number]
			return [value] if value is String and value in spec[1] else []
		"rank":
			if not value is Array or value.is_empty() or value.size()>5:return []
			var keys := []
			for item in value:
				if not item is String or not item in ["sum","attack","defence","speed","max_hp"] or item in keys:return []
				keys.append(item)
			return [keys]
		"stats":
			if not value is Array or value.size()>4:return []
			var chosen := []
			for item in value:
				if not item is String or not item in ["attack","defence","speed","max_hp"] or item in chosen:return []
				chosen.append(item)
			return [chosen]
		"offsets":
			if not value is Array or value.size()!=4:return []
			var result := []
			for item in value:
				var number = _int(item)
				if number==null or number< -2 or number>2:return []
				result.append(number)
			return [result]
	return []

static func _int(value: Variant) -> Variant:
	if value is int:return value
	if value is float and is_finite(value) and value==floorf(value):return int(value)
	return null

static func _prune_node(node: Variant, base: Variant) -> Dictionary:
	var result := {}
	if not node is Dictionary:return result
	for key in node:
		if node[key] is Dictionary:
			var inner := _prune_node(node[key],base.get(key,{}) if base is Dictionary else {})
			if not inner.is_empty():result[key] = inner
		elif not (base is Dictionary and base.has(key) and _same(base[key],node[key])):result[key] = node[key]
	return result

static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):return float(a)==float(b)
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in range(a.size()):
			if not _same(a[i],b[i]):return false
		return true
	return typeof(a)==typeof(b) and a==b

static func _dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}

static func _fail(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason}

## JSON numbers arrive as floats; whole numbers become ints. Notes are dropped.
static func _clean(value: Variant) -> Variant:
	if value is float and value==floorf(value):return int(value)
	if value is Dictionary:
		var result := {}
		for key in value:
			if str(key)!="comment":result[key] = _clean(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(_clean(item))
		return result
	return value
