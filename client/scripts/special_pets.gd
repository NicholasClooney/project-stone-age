extends RefCounted
## Special pets no imported map spawns, offered by GM 调试's 发放宠物 (a
## developer convenience). Original templates; the names players used are in
## docs/reverse-engineering/special-pets.md. Several are later-version (7.x,
## 8.x) designs whose Lv120 stats are far above 2.5-era pets.
const LIST := [
	[304,"机暴 · 帖拉所伊朵"],
	[303,"红暴 · 巴朵兰恩"],
	[302,"蓝暴 · 左迪洛斯"],
	[778,"蓝豹 · 萨格鲁"],
	[812,"金暴 · 斑尼迪克"],
	[968,"机豹 · 艾迪希洛"],
	[901,"地年兽 · 葛雷基欧"],
	[902,"水年兽 · 葛雷洛比"],
	[903,"火年兽 · 葛雷吉鲁"],
	[904,"风年兽 · 葛雷马恩"],
	[5,"黑乌力"],
	[1147,"黑乌力王"],
]

## Why a template cannot be granted here, or "" when it can.
static func unavailable_reason(template: int) -> String:
	var data: Dictionary = preload("res://server/progression.gd").species_definition("original_%d" % template)
	if data.is_empty():return "没有这个原表"
	if not preload("res://server/troop_art.gd").can_render([{"sprite":int(data.sprite)}]):return "战斗图未导入（需要 --with-8.0 的导入）"
	return ""
