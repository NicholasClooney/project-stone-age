extends RefCounted
## How rare a full-grade (满档) Lv.120 blue dragon's stats are, for 展示模式's
## cards. "1 in N" is the share of full-grade blue dragons (original 92,
## caught at Lv.1 and raised to 120) with at least that value, from the
## simulations in docs/game-systems/pet-quality.md: tools/pet_quality_tail.c
## with 400 million pets for 三围合, 100 million for the single stats. Other
## species have no table yet.

const TEMPLATE := 92
## value -> N, for "at least value".
const SUM := {620:14, 621:47, 622:204, 623:1170, 624:8950, 625:91722, 626:1302932}
const STATS := {
	"attack":{290:4, 291:16, 292:142, 293:2619, 294:101523, 295:7142857},
	"defence":{179:6, 180:57, 181:1388, 182:95511, 183:16666667},
	"speed":{152:9, 153:82, 154:1971, 155:124378, 156:33333333},
	"max_hp":{1310:18, 1311:29, 1312:50, 1313:91, 1314:173, 1315:346, 1316:724, 1317:1592, 1318:3705, 1319:8909, 1320:22894, 1321:63573, 1322:176678, 1323:497512, 1324:1612903, 1325:4347826},
}
const NAMES := {"attack":"攻击", "defence":"防御", "speed":"敏捷", "max_hp":"血"}

## N for "at least value" in a table, 0 below the table, -1 above it.
static func one_in(table: Dictionary, value: int) -> int:
	var keys: Array = table.keys()
	keys.sort()
	if value < int(keys[0]):return 0
	if value > int(keys.back()):return -1
	return int(table[value])

static func amount(n: int) -> String:
	if n >= 10000:return "%s 万" % String.num(n/10000.0, 1 if n < 100000 else 0)
	return str(n)

## Lines for a card: 三围合 always, then any single stat rarer than 1 in 1000.
static func describe(template_id: int, stats: Dictionary, full: bool) -> Array:
	if template_id != TEMPLATE or not full:return ["（稀有度只统计满档蓝人龙）"]
	var total := int(stats.get("attack", 0)) + int(stats.get("defence", 0)) + int(stats.get("speed", 0))
	var lines: Array = []
	var n := one_in(SUM, total)
	if n > 0:lines.append("三围合 %d：满档中约 1/%s" % [total, amount(n)])
	elif n < 0:lines.append("三围合 %d：4 亿次模拟也极少出现" % total)
	else:lines.append("三围合 %d：满档中很常见" % total)
	for key in ["attack", "defence", "speed", "max_hp"]:
		var m := one_in(STATS[key], int(stats.get(key, 0)))
		if m < 0:lines.append("%s %d：1 亿次模拟也极少出现" % [NAMES[key], int(stats.get(key, 0))])
		elif m >= 1000:lines.append("%s %d：约 1/%s" % [NAMES[key], int(stats.get(key, 0)), amount(m)])
	return lines
