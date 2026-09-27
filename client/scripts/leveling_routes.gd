extends RefCounted
## Ranking is level matching, not an unsupported claim of best XP/minute.
static func recommend(spots: Array, level: int, squad: bool = false) -> Array:
	var target:=clampi(level+(8 if squad else 0),1,120)
	var rows: Array=spots.duplicate(true)
	rows.sort_custom(func(a,b):
		var left:=absf(float(a.mean_level)-target)
		var right:=absf(float(b.mean_level)-target)
		if not is_equal_approx(left,right):return left<right
		if int(a.map_id)!=int(b.map_id):return int(a.map_id)<int(b.map_id)
		return int(a.area_id)<int(b.area_id))
	var chosen:=[]
	var signatures:={}
	for row in rows:
		var key:="%d/%d/%d"%[row.map_id,row.level_min,row.level_max]
		if signatures.has(key):continue
		signatures[key]=true;chosen.append(row)
		if chosen.size()==4:break
	return chosen
static func classic_guide(level: int) -> String:
	if level<10:return "经典路线 Lv.1–9：出生村外就近练级。"
	if level<15:return "经典路线 Lv.10–14：柯奥山小洞窟。当前原表没有普通遇敌记录，下面改荐可用野外。"
	if level<20:return "经典路线 Lv.15–19：阿布洞窟。当前原表敌人多为 Lv.20–30，低级独行需谨慎。"
	if level<40:return "经典路线 Lv.20–39：海底洞窟／海主人。当前导入海底通道的普通遇敌为另一等级段，以列表为准。"
	if level<80:return "经典路线 Lv.40–79：穿山甲洞或五兄弟洞。当前五兄弟普通遇敌可用，穿山甲路线尚未确认。"
	return "经典路线 Lv.80–120：英雄岛海边水雷。水雷有圣石条件且相关动画缺失；目前改荐可用的英雄岛或漆黑洞普通敌群。"
