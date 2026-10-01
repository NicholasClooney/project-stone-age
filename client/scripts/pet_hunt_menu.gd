extends Control
## Optional single-player data inspection. Rolls real local troops; never grants rewards.
## Scanning runs in the backend (res://server/automation.gd); this menu edits
## the character's hunt settings (profile automation_settings: hunt, capture,
## stat_filters) and presents progress. Changes are saved as the player makes
## them and other devices' changes show up here.
const StatFilter=preload("res://scripts/pet_stat_filter.gd")
const KeepRule=preload("res://scripts/keep_rule.gd")
const AutomationSettings=preload("res://scripts/automation_settings.gd")
## Profile hunt settings last shown; only values that change are rewritten.
var _loaded: Dictionary = {}
var _loading := false
## The saved target species is not available here, so the list shows 任何.
var _template_fallback := false
## Species whose stat conditions the 属性条件 page shows.
var _stat_species_shown := -1
## The saved 属性条件 species (hunt.stat_species) is not in the list here.
var _stat_species_fallback := false
## Which page the window shows (筛选条件 / 抓宠设置 / 属性条件), remembered on
## this device (viewer pref hunt_page).
var page := "filters"
var _built := false
var _stat_loaded: Dictionary = {}
var stat_page: Control
var stat_species: OptionButton
var stat_mode: OptionButton
## 相对：最高 − x / 绝对：≥ 数值 (the species' threshold_mode).
var stat_threshold_mode: OptionButton
var stat_heading: Label
var stat_checks: Dictionary = {}
## Relative: 三围合 ≥ 最高 N − [x] = T: stat_numbers are the x (minus),
## stat_results show T (or 摸底 without a pet of the species). Absolute:
## 三围合 ≥ [v]（现有最高 N）: stat_values are v, stat_results the best.
var stat_numbers: Dictionary = {}
var stat_values: Dictionary = {}
var stat_results: Dictionary = {}
var _thresholds_key := ""
var _thresholds_msec := -100000
var stat_keeps: Dictionary = {}
## 保留规则 (scripts/keep_rule.gd): tiers, pets per tier, the tier order
## (第一/第二/第三), single-stat champions and 找宠时自动整理.
var rule_tiers: SpinBox
var rule_per_tier: SpinBox
var stat_rank: Array[OptionButton] = []
var rule_champions: SpinBox
var rule_stats: Dictionary = {}
var rule_auto: CheckBox
var loading_stat_settings := false
const CapturePolicy=preload("res://scripts/battle_auto_policy.gd")
const Rules = preload("res://scripts/pet_hunt_rules.gd")
var filter_nodes: Array[Control] = []
var capture_page: Control
## 找到N只后停止 (hunt.stop_after) on 抓宠设置: one count for the whole find-pet run.
var stop_after: SpinBox
var train_after_capture: CheckBox
var world: Node
var panel: Panel
var species: OptionButton
var auto_capture: CheckBox
## 本机极速模式 (hunt.fast): the backend scans with the native helper on every
## CPU core; the same rolls as the ordinary scan, which runs when it cannot.
var fast: CheckBox
## 后台搜宠 (hunt.showcase; the name is AutomationSettings.SHOWCASE_NAME): the
## search goes on in the background while the player watches each found pet's
## capture and 自动练级 to 120 (server/automation.gd). On 抓宠设置 with its
## 排队上限 (hunt.queue) and the 自动练级 settings it uses: 经验倍率 (the
## character's training.xp) and 战斗速度 (this device's battle speed).
var showcase: CheckBox
var queue_size: SpinBox
var showcase_xp: OptionButton
var showcase_speed: OptionButton
## 重启后自动恢复 (hunt.resume): a run the server was doing when it shut down
## goes on after the restart (server/automation.gd try_resume).
var resume_after_restart: CheckBox
## 只进无其他敌人的遇敌 (hunt.clean_only): a Lv.1 hunt skips troops with an
## enemy above Lv.1. 属性达标仍进混合遇敌 (hunt.mixed_if_stats): a find-pet
## cycle still takes such a pet when it meets its enabled 属性条件, after a
## battle forecast (server/battle_forecast.gd) says the fight can be won.
var clean_only: CheckBox
var mixed_if_stats: CheckBox
## 线程数 of the server's helper (0 = auto): the computer's setting, not the
## character's, so it is sent as its own command and stays editable mid-hunt.
var thread_count: SpinBox
var cores_label: Label
var level_one: CheckBox
var preset: OptionButton
var total: SpinBox
var offsets: Array[SpinBox] = []
var rate: SpinBox
var limit: SpinBox
var status: Label
var location_label: Label
var explanation: Label
var start_button: Button
var stop_button: Button
var minimize_button: Button
## Collapsed to a progress bar while the scan or find-pet cycle continues.
var minimized := false
var minimized_flow := false
var chip: Panel
var controls: Array[Control] = []
var candidates: Array = []
var applying := false

func _hunt() -> Dictionary:
	return world.state.automation.get("hunt",{}) if is_instance_valid(world) else {}

var running: bool:
	get:return bool(_hunt().get("running",false))
var rolls: int:
	get:return int(_hunt().get("rolls",0))
var inspected: int:
	get:return int(_hunt().get("inspected",0))
var best: int:
	get:return int(_hunt().get("best",-9))
var elapsed: float:
	get:return float(_hunt().get("elapsed",0.0))
var credit: float:
	get:return float(_hunt().get("credit",0.0))
var last_hit: Dictionary:
	get:return _hunt().get("last_hit",{})
var region_map: int:
	get:return int(_hunt().get("map_id",-1))
var region_cell: Vector2i:
	get:
		var cell: Array=_hunt().get("cell",[0,0])
		return Vector2i(int(cell[0]),int(cell[1]))
## The live backend filter in-process, so tests may tighten it mid-run.
var filter: Dictionary:
	get:return world.backend.automation.hunt_filter if world.link.is_local() else _hunt().get("filter",{})
## In-process test seam: the prepared encounter source for this run.
var hunt_catalog:
	get:return world.backend.automation.hunt_catalog
	set(value):world.backend.automation.hunt_catalog = value

func configure(owner: Node) -> void:world=owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=250
	panel=Panel.new()
	panel.position=Vector2(90,110)
	panel.size=Vector2(1100,620)
	panel.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")))
	add_child(panel)
	label("轻松助手 · 自动抓极品",Vector2(24,18),24)
	label("直接检查隐藏成长档。按当地原表遇敌；未达标跳过，不战斗、不捕获、不发奖励。",Vector2(24,58),16)
	location_label=label("",Vector2(24,92),16)
	label("目标宠物",Vector2(24,139),17)
	species=OptionButton.new()
	species.position=Vector2(140,129);species.size=Vector2(380,38)
	panel.add_child(species);controls.append(species)
	level_one=CheckBox.new();level_one.text="只找 Lv.1";level_one.button_pressed=true
	level_one.position=Vector2(555,132);panel.add_child(level_one);controls.append(level_one)
	level_one.toggled.connect(func(_value):
		refresh_candidates()
		_settings_changed(true))
	auto_capture=CheckBox.new();auto_capture.text="达标后自动抓宠";auto_capture.position=Vector2(760,132)
	panel.add_child(auto_capture);controls.append(auto_capture)
	label("成长档预设",Vector2(24,194),17)
	preset=OptionButton.new();preset.position=Vector2(140,184);preset.size=Vector2(480,38)
	for title in ["不限品质 · 快速试用","优秀：总成长档 +4 或更高","极品：总成长档 +6 或更高","满档：四项成长档均 +2","自定义"]:preset.add_item(title)
	preset.select(3);preset.item_selected.connect(func(index):
		apply_preset(index)
		_settings_changed(true))
	panel.add_child(preset);controls.append(preset)
	label("总档下限",Vector2(24,249),17)
	total=number(Vector2(140,239),-8,8,8)
	total.value_changed.connect(filters_changed)
	label("各项最低偏移（相对同种基础档）",Vector2(320,249),16)
	for i in range(4):
		label(["体力档","腕力档","耐力档","速度档"][i],Vector2(24+i*258,305),17)
		var input:=number(Vector2(115+i*258,295),-2,2,2)
		input.value_changed.connect(filters_changed);offsets.append(input)
	explanation=label("",Vector2(24,351),15);explanation.size=Vector2(1040,67);explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label("每秒遇敌",Vector2(24,433),17);rate=number(Vector2(140,423),0,100000,0);rate.value_changed.connect(func(_value):_settings_changed(false))
	rate.tooltip_text="0为不限速：每帧用满约12毫秒工作预算。填正数则按该目标限速。填了限速时不使用本机极速模式。"
	label("本轮上限",Vector2(340,433),17);limit=number(Vector2(460,423),0,1000000,0);limit.value_changed.connect(func(_value):_settings_changed(false))
	label("组；0为不限，到上限暂停。",Vector2(610,433),16)
	fast=CheckBox.new();fast.name="FastHunt";fast.text="本机极速模式";fast.button_pressed=true;fast.position=Vector2(860,428)
	fast.tooltip_text="服务器所在电脑用全部 CPU 核心筛选，遇到的敌群和结果与普通筛选完全相同，只是快得多；「每秒遇敌」填了限速时按限速用普通筛选；无法使用时也自动改用普通筛选。"
	panel.add_child(fast);controls.append(fast)
	fast.toggled.connect(func(_value):_settings_changed(true))
	label("线程数",Vector2(852,470),15)
	thread_count=SpinBox.new();thread_count.name="FastHuntThreads";thread_count.position=Vector2(905,462);thread_count.size=Vector2(100,34)
	thread_count.min_value=0;thread_count.max_value=64;thread_count.step=1;thread_count.value=0
	thread_count.value_changed.connect(func(value):world.link.request({"type":"set_fast_hunt_threads","threads":int(value)}))
	panel.add_child(thread_count)
	cores_label=label("",Vector2(1012,470),14)
	status=label("",Vector2(24,478),14);status.size=Vector2(830,80);status.clip_text=true;status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	start_button=world.button("开始筛选",start_requested);start_button.name="StartPetHunt";start_button.position=Vector2(24,560);panel.add_child(start_button)
	stop_button=world.button("停止",func():stop_all("已停止，可调整条件后重新开始。"));stop_button.name="StopPetHunt";stop_button.position=Vector2(220,560);panel.add_child(stop_button)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(900,560);panel.add_child(close)
	minimize_button=world.button("最小化",minimize);minimize_button.name="MinimizePetHunt";minimize_button.position=Vector2(760,560);minimize_button.disabled=true
	minimize_button.tooltip_text="收起为右下角进度条；筛选或找宠流程继续，可同时整理宠物与仓库";panel.add_child(minimize_button)
	var records: Button=world.button("宠物记录",open_records);records.name="PetHuntRecords";records.position=Vector2(600,560)
	records.tooltip_text="抓到、放生和停止记录。筛选或找宠流程进行中会先收起本窗口，流程继续。";panel.add_child(records)
	for child in panel.get_children():
		if child is Control and child.position.y>=129 and child.position.y<=460:filter_nodes.append(child)
	capture_page=Control.new();capture_page.name="CaptureSettingsPage";capture_page.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(capture_page)
	var filters_tab:Button=world.button("筛选条件",func():show_capture_settings(false));filters_tab.name="HuntFilterTab";filters_tab.position=Vector2(585,18);panel.add_child(filters_tab)
	var capture_tab:Button=world.button("抓宠设置",func():show_capture_settings(true));capture_tab.name="HuntCaptureTab";capture_tab.position=Vector2(740,18);panel.add_child(capture_tab)
	showcase_controls()
	stop_after_controls()
	train_after_capture=CheckBox.new();train_after_capture.text="抓到后直接升至120级 · 按属性条件留存 · 无动画抓宠";train_after_capture.tooltip_text="成长按宠物种子逐级固定，直接升级与战斗练级结果相同。达标（无属性条件时每只升满的）按「找到N只后停止」存仓或停下比较，未达标存仓并继续。";train_after_capture.name="TrainCapturedPetTo120";train_after_capture.position=Vector2(24,430);capture_page.add_child(train_after_capture);controls.append(train_after_capture)
	train_after_capture.toggled.connect(func(enabled):
		start_button.text="开始抓宠并练至120" if enabled else "开始筛选"
		if enabled:auto_capture.button_pressed=true
		refresh_ready_status()
		_settings_changed(true))
	auto_capture.toggled.connect(func(enabled):
		if not enabled:train_after_capture.button_pressed=false
		refresh_ready_status()
		_settings_changed(true))
	species.item_selected.connect(func(_index):
		_template_fallback=false
		_follow_target(species.get_selected_id())
		_settings_changed(true))
	build_stat_page()
	show_capture_settings(false)
	load_settings()
	hide()
	_built=true

func label(text: String, at: Vector2, size: int) -> Label:
	var result: Label=world.text(text,size)
	result.position=at;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(result);return result
func number(at: Vector2, minimum: int, maximum: int, value: int) -> SpinBox:
	var result:=SpinBox.new();result.position=at;result.size=Vector2(130,38)
	result.min_value=minimum;result.max_value=maximum;result.step=1;result.value=value
	# Once the player stops typing, show any update that waited for them.
	result.get_line_edit().focus_exited.connect(func():call_deferred("load_settings"))
	panel.add_child(result);controls.append(result);return result
func min_offsets() -> Array:
	var values:=[]
	for input in offsets:values.append(int(input.value))
	return values
func apply_preset(index: int) -> void:
	if index>=4:return
	applying=true
	total.value=[-8,4,6,8][index]
	for input in offsets:input.value=2 if index==3 else -2
	applying=false
	update_explanation()
func filters_changed(_value: float) -> void:
	if not applying and is_instance_valid(preset):preset.select(4)
	update_explanation()
	if not applying:_settings_changed(false)

## Preset matching the thresholds; 4 is 自定义.
func _preset_index() -> int:
	var values:=min_offsets()
	for index in range(4):
		if int(total.value)==[-8,4,6,8][index] and values==([2,2,2,2] if index==3 else [-2,-2,-2,-2]):return index
	return 4

## A control changed: save now (a choice) or once the player pauses (numbers).
func _settings_changed(now: bool) -> void:
	if _loading or not is_instance_valid(world):return
	world.mark_settings_dirty(self)
	if now:world.flush_automation_settings()

## Saves the controls before a run starts.
func commit_settings() -> void:
	for control in controls:
		if control is SpinBox and control.get_line_edit().has_focus():control.apply()
	world.mark_settings_dirty(self)
	world.flush_automation_settings()

## Run-only filter fields a start command carries: 任何 shown only because the
## saved species does not live here hunts any species now, while the profile
## keeps the species the player last chose for next time.
func start_filter() -> Dictionary:
	return {"template":-1} if _template_fallback else {}

## Picks the target species (瞬移去抓, a comparison's 找这种): it is saved, and
## 属性条件 shows the same species. False when it is not available here.
func choose_target(template_id: int) -> bool:
	var index:=species.get_item_index(template_id)
	if index<0 or species.is_item_disabled(index):return false
	species.select(index)
	_template_fallback=false
	_follow_target(template_id)
	return true

## 属性条件 shows the target species when the player picks one.
func _follow_target(template_id: int) -> void:
	if template_id<0 or not is_instance_valid(stat_species):return
	var index:=stat_species.get_item_index(template_id)
	if index<0 or stat_species.get_selected_id()==template_id:return
	world.flush_automation_settings()
	stat_species.select(index)
	_stat_species_fallback=false
	load_stat_settings()

## What these controls change in the profile (see game.flush_automation_settings).
func settings_patch() -> Dictionary:
	var patch := {}
	var wanted:={"level_one":level_one.button_pressed,"auto_capture":auto_capture.button_pressed,"train_after_capture":train_after_capture.button_pressed,
		"total":int(total.value),"offsets":min_offsets(),"rate":int(rate.value),"limit":int(limit.value),"fast":fast.button_pressed,"showcase":showcase.button_pressed,"queue":int(queue_size.value),
		"resume":resume_after_restart.button_pressed,"clean_only":clean_only.button_pressed,"mixed_if_stats":mixed_if_stats.button_pressed,"stop_after":int(stop_after.value)}
	# 任何 shown only because the saved species is not found here keeps the saved one.
	if species.item_count>0 and not _template_fallback:wanted.template=species.get_selected_id()
	# Likewise 属性条件's species: a fallback shown here keeps the saved choice.
	if is_instance_valid(stat_species) and stat_species.item_count>0 and not _stat_species_fallback:wanted.stat_species=stat_species.get_selected_id()
	var hunt:=AutomationSettings.diff(world.automation_settings().hunt,wanted)
	if not hunt.is_empty():patch.hunt=hunt
	var training:=AutomationSettings.diff(world.automation_settings().training,{"xp":[1,2,10,100][maxi(0,showcase_xp.selected)]})
	if not training.is_empty():patch.training=training
	if _stat_species_shown>=0:
		var conditions:={}
		for metric in StatFilter.METRICS:
			conditions[metric]={"enabled":stat_checks[metric].button_pressed,"minus":int(stat_numbers[metric].value),"value":int(stat_values[metric].value),"keep":int(stat_keeps[metric].value)}
		var chosen_stats:=KeepRule.STATS.filter(func(stat):return rule_stats[stat].button_pressed)
		var keep_rule:={"tiers":int(rule_tiers.value),"per_tier":int(rule_per_tier.value),"order":rank_choice(),"champions":int(rule_champions.value),"champion_stats":chosen_stats,"auto":rule_auto.button_pressed}
		var wanted_filter:={"mode":"any" if stat_mode.selected==1 else "all","threshold_mode":_threshold_mode_shown(),"keep_rule":keep_rule,"conditions":conditions}
		var changed:=AutomationSettings.diff(world.stat_filter(_stat_species_shown),wanted_filter)
		if not changed.is_empty():patch.stat_filters={str(_stat_species_shown):changed}
	return patch

## Shows the profile's hunt settings. Only values that changed since the last
## load are rewritten, and never a number the player is typing.
func load_settings() -> void:
	var hunt: Dictionary=world.automation_settings().hunt
	var old:=_loaded
	_loading=true;applying=true
	var refresh:=false
	if _changed(old,hunt,"level_one"):level_one.set_pressed_no_signal(bool(hunt.level_one));refresh=true
	if _changed(old,hunt,"auto_capture"):auto_capture.set_pressed_no_signal(bool(hunt.auto_capture))
	if _changed(old,hunt,"train_after_capture"):train_after_capture.set_pressed_no_signal(bool(hunt.train_after_capture))
	if _changed(old,hunt,"fast"):fast.set_pressed_no_signal(bool(hunt.fast))
	if _changed(old,hunt,"showcase"):showcase.set_pressed_no_signal(bool(hunt.showcase))
	if _changed(old,hunt,"resume"):resume_after_restart.set_pressed_no_signal(bool(hunt.resume))
	if _changed(old,hunt,"clean_only"):clean_only.set_pressed_no_signal(bool(hunt.clean_only))
	if _changed(old,hunt,"mixed_if_stats"):mixed_if_stats.set_pressed_no_signal(bool(hunt.mixed_if_stats))
	_show_mixed_option()
	if not queue_size.get_line_edit().has_focus():queue_size.set_value_no_signal(int(hunt.queue))
	showcase_xp.select(maxi(0,[1,2,10,100].find(int(world.automation_settings().training.xp))))
	showcase_speed.select(maxi(0,[1.0,2.0,4.0,8.0].find(world.playback_speed())))
	start_button.text="开始抓宠并练至120" if train_after_capture.button_pressed else "开始筛选"
	var shown:=hunt.duplicate(true)
	var numbers:={"total":total,"rate":rate,"limit":limit,"stop_after":stop_after}
	for key in numbers:
		if not _sync_spin(numbers[key],old.get(key),hunt[key]):shown[key]=old[key]
	var old_offsets: Array=old.get("offsets",[null,null,null,null])
	for i in range(4):
		if not _sync_spin(offsets[i],old_offsets[i],hunt.offsets[i]):shown.offsets[i]=old_offsets[i]
	preset.select(_preset_index())
	if _changed(old,hunt,"template"):refresh=true
	_loaded=shown
	if refresh and visible:refresh_candidates()
	applying=false;_loading=false
	update_explanation()
	if is_instance_valid(stat_species) and stat_species.item_count>0:
		# Another device chose a different 属性条件 species: show it here too.
		if _changed(old,hunt,"stat_species") and old.has("stat_species"):refresh_stat_species()
		else:load_stat_settings()
	if visible:refresh_ready_status()

static func _changed(old: Dictionary, now: Dictionary, key: String) -> bool:
	return not old.has(key) or str(old[key])!=str(now[key])

static func _typing(input: SpinBox) -> bool:
	return input.get_line_edit().has_focus()

## Shows a profile value in a number field, unless the player is typing there
## or has an unsent change of their own (it is saved shortly and wins).
## Returns false when the field keeps its value; a later load retries.
static func _sync_spin(input: SpinBox, old_value: Variant, new_value: Variant, force: bool = false) -> bool:
	if not force and old_value!=null and str(old_value)==str(new_value):return true
	if not force and input.get_line_edit().has_focus():return false
	if not force and old_value!=null and int(input.value)!=int(old_value) and int(input.value)!=int(new_value):return false
	input.value=new_value
	return true
func update_explanation() -> void:
	if not is_instance_valid(explanation) or offsets.size()!=4:return
	var probability: float=Rules.tail_probability(int(total.value),min_offsets())
	explanation.text="同种自然出生个体中，约 %.2f%% 的成长档符合此条件（不是每次遇敌的命中率）。\n+2 是该项出生档上限；四项均 +2 为满档，可真实出现，不保证未来每级都长到最大值。" % (probability*100.0)
func refresh_candidates() -> void:
	var selected:=int(world.automation_settings().hunt.template)
	species.clear();species.add_item("任何本地可用宠物",-1)
	# OptionButton uses -1 for auto IDs; set it explicitly for the wildcard.
	species.set_item_id(0,-1)
	candidates=Rules.candidates(world.encounter_catalog,int(world.data.map_id),world.cell,level_one.button_pressed)
	var available:=0
	for item in candidates:
		var definition: Dictionary=world.encounter_catalog.data.templates[str(item.id)]
		var renderable: bool=world.battle_view.can_render_troop([{"sprite":int(definition.sprite)}])
		species.add_item("%s · Lv.%d–%d%s" % [item.name,item.level_min,item.level_max,"" if renderable else "（素材不可用）"],int(item.id))
		species.set_item_disabled(species.item_count-1,not renderable)
		if renderable:
			available+=1
			if int(item.id)==selected:species.select(species.item_count-1)
	_template_fallback=selected>=0 and species.get_selected_id()!=selected
	start_button.disabled=available==0 or not world.world_catalog.field(int(world.data.map_id))
	location_label.text="当前位置：%s (%d, %d) · 只使用此处原版敌群，不改种类、等级或成长随机值。" % [world.data.name,world.cell.x,world.cell.y]
	status.text="这里没有可用的目标。可到萨姆吉尔西门外筛选 Lv.1 昆依，或关闭 Lv.1 限制。" if start_button.disabled else ready_description()
func open_menu() -> void:
	if minimized:restore();return
	if visible:close_menu();return
	if world.paused_input or world.area_transition_busy or world.battle_view.visible:return
	if is_instance_valid(world.travel_router):world.travel_router.cancel("已打开极品筛选，停止自动寻路。")
	world.clear_input()
	if world.moving:
		world.moving=false;world.logical_position=Vector2(world.cell);world.player.position=world.project(world.logical_position)
	world.player.set_action(3)
	world.paused_input=true
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show();refresh_candidates();refresh_stat_species();world.training_helper._refresh_pet_choices();stop_button.disabled=true;_show_fast_availability()
	show_page(str(world.viewer_pref("hunt_page",page)))
func close_menu() -> void:
	if not visible:return
	world.flush_automation_settings()
	if world.pet_workflow.active() and world.pet_workflow.stop_pending().is_empty():world.pet_workflow.stop_cycle("已关闭筛选。",false)
	elif running:world.link.request({"type":"auto","name":"stop_hunt","reason":"已关闭筛选。"})
	set_controls(false);hide();world.release_input();world.clear_input()
## 宠物记录 on 抓到 (本轮找宠 while a cycle runs). A running scan or cycle
## keeps going with this window folded to its progress bar; otherwise it closes.
func open_records() -> void:
	if running or _automation_active(world.state.automation):minimize()
	else:close_menu()
	world.adventure_menu.open_pet_records("caught",-1)

func set_controls(locked: bool) -> void:
	for control in controls:
		# 属性条件 and 找到N只后停止 stay editable: a running cycle follows them at once.
		var held:=locked and control!=stop_after and not (is_instance_valid(stat_page) and stat_page.is_ancestor_of(control))
		if control is SpinBox:control.editable=not held
		elif control is BaseButton:control.disabled=held
	_show_mixed_option()
	start_button.disabled=locked
	stop_button.disabled=not locked
	minimize_button.disabled=not locked
	_show_fast_availability()

## Greys 本机极速模式 with the reason when the backend's computer cannot run the
## helper (the hunt then scans the ordinary way).
func _show_fast_availability() -> void:
	_show_threads(world.state.automation)
	var reason:=fast_unavailable()
	if reason.is_empty():
		fast.text="本机极速模式"
		return
	fast.disabled=true
	fast.text="本机极速模式（不可用）"
	fast.tooltip_text=reason+"\n将使用普通筛选。"

## The server's 线程数 and core count from the automation status; the box is
## left alone while the player is typing in it.
func _show_threads(automation: Dictionary) -> void:
	if not is_instance_valid(thread_count):return
	var hunt: Dictionary = automation.get("hunt",{})
	var cores := int(hunt.get("cores",0))
	thread_count.visible = cores > 0
	cores_label.visible = cores > 0
	if cores <= 0:return
	thread_count.max_value = cores
	thread_count.editable = fast_unavailable().is_empty() and (not world.has_method("is_admin") or world.is_admin())
	if not thread_count.get_line_edit().has_focus():thread_count.set_value_no_signal(int(hunt.get("threads",0)))
	cores_label.text = "本机%d核" % cores
	thread_count.tooltip_text = "本机极速模式同时用几个线程（服务器所在电脑的设置，所有设备共用）。0 为自动：用 %d 个（核心数减 1）。现在用 %d 个；修改后正在进行的筛选立即换用新值。调小可以给其他程序留出 CPU，速度会相应变慢。" % [cores-1 if cores > 2 else 1,int(hunt.get("threads_used",0))]

func fast_unavailable() -> String:
	return str(world.state.automation.get("hunt",{}).get("fast_unavailable","")) if is_instance_valid(world) else ""
## Validated hunt filter from these controls, or {} with the reason shown.
func build_filter(for_workflow: bool = false) -> Dictionary:
	for control in controls:
		if control is SpinBox and control.get_line_edit().has_focus():control.apply()
	if running or not visible or world.battle_view.visible or world.area_transition_busy:return {}
	if not world.world_catalog.field(int(world.data.map_id)):return {}
	if world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
		status.text="宠物栏已满，请先腾出位置再寻找新伙伴。";return {}
	if int(world.training_helper.capture_hp.value)<100 and level_one.button_pressed and (auto_capture.button_pressed or for_workflow):
		var profile:Dictionary=world.session.snapshot()
		var chosen:Dictionary=world.training_helper.current_settings()
		var choice:Dictionary=CapturePolicy.capture_pet_choice(profile,chosen,1)
		if choice.has("stop"):
			status.text=str(choice.stop)
			if int(chosen.capture_pet)<0 and str(chosen.get("capture_pet_id","")).is_empty():status.text="缺少可用削血宠：请从仓库取出存活、非骑乘的Lv.1宠物，或手选符合等级上限的削血宠。"
			world.message.text=status.text
			return {}
	if Rules.tail_probability(int(total.value),min_offsets())<=0:
		status.text="这些条件无法同时满足，请降低门槛。";return {}
	if Rules.candidates(world.encounter_catalog,int(world.data.map_id),world.cell,level_one.button_pressed).is_empty():
		status.text="当前区域不会出现符合种类／等级条件的宠物。";return {}
	var usable:=[]
	for index in range(1,species.item_count):
		if not species.is_item_disabled(index):usable.append(species.get_item_id(index))
	if usable.is_empty() or (species.get_selected_id()>=0 and not species.get_selected_id() in usable):
		status.text="当前没有素材齐全的目标宠物。";return {}
	return {"usable":usable,"template":species.get_selected_id(),"level_one":level_one.button_pressed,"total":int(total.value),"offsets":min_offsets(),"rate":int(rate.value),"limit":int(limit.value),"auto_capture":auto_capture.button_pressed}

func start_hunt() -> void:
	var chosen:=build_filter()
	if chosen.is_empty():return
	# The backend hunts with the profile's settings; save these controls first.
	commit_settings()
	var command:={"type":"auto_start","kind":"hunt","map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]}
	if not start_filter().is_empty():command.filter=start_filter()
	var reply: Dictionary=world.link.request(command)
	if not reply.ok and not reply.get("pending",false):
		if not str(reply.reason).is_empty():status.text=str(reply.reason)
		return
	set_controls(true);update_status()
## 停止 and closing: the whole find-pet cycle when one runs (with 后台搜宠 the
## scan runs beside the capture and training, so stopping only the scan would
## leave them going), otherwise the scan. A battle in progress stays open for
## the player to finish by hand.
func stop_all(reason: String) -> void:
	if world.pet_workflow.active():world.pet_workflow.stop_cycle(reason,not world.pet_workflow.stop_pending().is_empty())
	else:stop_hunt(reason)

func stop_hunt(reason: String) -> void:
	if running:world.link.request({"type":"auto","name":"stop_hunt","reason":reason})
	else:on_event({"kind":"hunt_stopped","reason":reason})
func summary() -> String:
	var actual:=rolls / maxf(elapsed,0.001)
	return workflow_summary()+"已遇敌 %s 组 · 检查目标 %s 只%s · 最好总档 %s · 本轮 %s\n%s · 实际 %s · 流程总用时 %s" % [cn_count(rolls),cn_count(inspected),mixed_text(int(_hunt().get("mixed",0))),"暂无" if best< -8 else "%+d" % best,duration_text(elapsed),speed_text(),rolls_text(actual),duration_text(world.pet_workflow.elapsed_seconds())]
## 「 · 混合敌群跳过 3 只」:达标 pets passed over because stronger enemies
## were in their troop (只进无其他敌人的遇敌), or "".
static func mixed_text(count: int) -> String:
	return " · 混合敌群跳过 %s 只" % cn_count(count) if count>0 else ""
## How this run scans: the helper, the ordinary scan and why, or its target rate.
func speed_text() -> String:
	var hunt: Dictionary=_hunt()
	if bool(hunt.get("fast",false)):return "本机极速模式"+share_text(hunt)
	var note:=str(hunt.get("fast_note",""))
	var target:=int(filter.get("rate",rate.value))
	if bool(hunt.get("fast_wanted",false)) and not note.is_empty():return "普通筛选（%s）· 目标 %s" % [note.trim_suffix("。"),rate_text(target)]
	if bool(hunt.get("fast_wanted",false)) and target>0:return "目标 %s（已限速，使用普通筛选）" % rate_text(target)
	return "目标 "+rate_text(target)
## 「（3 人共享）」 when several players' hunts share the computer's helper
## threads (LAN profiles), else "".
static func shared_text(hunters: int) -> String:
	return "（%d 人共享）" % hunters if hunters>1 else ""
## This hunt's share of the threads, 「 · 线程 4/14（3 人共享）」, when shared.
static func share_text(hunt: Dictionary) -> String:
	var hunters:=int(hunt.get("hunters",1))
	if hunters<=1:return ""
	return " · 线程 %d/%d%s" % [int(hunt.get("threads_used",0)),int(hunt.get("budget",0)),shared_text(hunters)]
static func rolls_text(per_second: float) -> String:
	return cn_count(per_second)+" 组/秒"
func rate_text(value: int) -> String:return "不限速" if value<=0 else "%d 组/秒"%value
func update_status() -> void:status.text=summary()+queue_text("\n")+"\n筛选中；停止或 Esc 可随时结束。"
## 展示模式's waiting hits, or "" when none.
func queue_text(prefix: String = "") -> String:
	var size:=int(world.state.automation.get("flow",{}).get("queue_size",0)) if is_instance_valid(world) else 0
	return prefix+"后台已找到 %d 只在排队" % size if size>0 else ""
func _process(delta: float) -> void:
	if visible and is_instance_valid(stat_page) and stat_page.visible:refresh_stat_thresholds()
	if not running:return
	# Minimized, the scan keeps going while other panels come and go. Over a
	# network the backend stops the hunt itself when the character moves or a
	# battle opens; several devices share the run, so one device's window or
	# map load must not stop it.
	# 后台搜宠 searches on behind the battles the player watches.
	var showcase: bool = bool(world.state.automation.get("flow",{}).get("showcase",false)) and world.pet_workflow.active()
	var screen_changed: bool = not showcase and (not (visible or minimized) or (visible and not world.paused_input) or world.battle_view.visible)
	if world.link.is_local() and (screen_changed or world.area_transition_busy or int(world.data.map_id)!=region_map or world.cell!=region_cell):
		stop_hunt("场景状态变化，筛选已停止。");return
	# In-process, this frame drives the backend scan with the same budget.
	if world.link.is_local():world.link.request({"type":"auto","name":"hunt_process","delta":delta})
	if running and Time.get_ticks_msec()-_status_shown_msec>=refresh_msec:
		_status_shown_msec=Time.get_ticks_msec();update_status()
	if _chip_dirty and minimized:_update_chip()
## Test seam: one backend scan now.
func scan_once() -> void:
	world.link.request({"type":"auto","name":"hunt_scan"})

func on_status(automation: Dictionary) -> void:
	if is_instance_valid(stop_button):
		var pending:=str(automation.get("flow",{}).get("stop_pending",""))
		stop_button.text="立即停止" if not pending.is_empty() else "停止"
		stop_button.tooltip_text="本只练完后会停止；再按立即停止，正在打的战斗交给你手动完成" if not pending.is_empty() else "正在抓或练的这一只练完后停止"
	if visible:_show_threads(automation)
	if minimized:
		if _automation_active(automation):_update_chip()
		else:
			_end_minimized()
			var reason: String=str(automation.get("flow",{}).get("reason","")) if minimized_flow else str(automation.get("hunt",{}).get("status",""))
			world.message.text="自动抓极品已结束："+reason.replace("\n"," ")
			world.release_input()
	if visible and bool(automation.get("hunt",{}).get("running",false)):
		set_controls(true);update_status()

func on_event(detail: Dictionary) -> void:
	match str(detail.kind):
		"hunt_stopped":
			set_controls(false);status.text=str(detail.reason)+"\n"+summary()
		"hunt_refused":
			status.text=str(detail.reason)
			world.message.text=status.text
		"hunt_hit":
			var i:=int(detail.index)
			var actor: Dictionary=detail.actor
			hide()
			world.battle_view.player_target=i
			# A workflow capture resolves without animation, like compact training.
			if not bool(detail.get("workflow",false)):world.battle_view.mark_hunt_target(i)
			world.battle_view.report.text="发现 %s Lv.%d · 成长档 %+d · %s" % [actor.name,actor.level,detail.quality.total_offset,"自动捕捉中" if detail.automatic else "请手动捕捉"]
			world.message.text="极品筛选：%s，总成长档 %+d，已遇敌 %d 组。" % [actor.name,detail.quality.total_offset,int(detail.rolls)]

func install_capture_controls(hp:SpinBox,pet:OptionButton,max_level:SpinBox)->void:
	for control in [hp,pet,max_level]:control.reparent(capture_page);controls.append(control)
	hp.position=Vector2(230,139);hp.size=Vector2(150,38);hp.name="CaptureHp"
	pet.position=Vector2(230,189);pet.size=Vector2(470,38);pet.name="CapturePet"
	max_level.position=Vector2(230,239);max_level.size=Vector2(150,38);max_level.name="CapturePetMaxLevel"
	for entry in [["抓宠血量线 %",Vector2(24,149)],["削血宠物",Vector2(24,199)],["削血宠等级上限",Vector2(24,249)]]:
		var caption:Label=world.text(str(entry[0]),16);caption.position=entry[1];capture_page.add_child(caption)

## 抓宠设置: 找到[N]只后停止（0＝不停）, beside the 难抓 rows, above the 抓到后直接升至120级 switch.
func stop_after_controls()->void:
	var tip:="整轮找宠共用，不分品种：本轮留下的宠物数到这个数就停止并打开比较。有属性条件时算达标的（摸底选中的也算）；没有启用条件时每只升到120级的都算。0＝不停，一直找到手动停止；1＝找到第一只就停下比较。未达标存仓的不算。仅在「抓到后直接升至120级」时生效。低血量、缺少削血宠或存仓失败仍会暂停。"
	var before:Label=world.text("找到",17);before.position=Vector2(410,399);before.mouse_filter=Control.MOUSE_FILTER_PASS;before.tooltip_text=tip;capture_page.add_child(before)
	stop_after=SpinBox.new();stop_after.name="HuntStopAfter";stop_after.min_value=0;stop_after.max_value=100000;stop_after.step=1;stop_after.value=1
	stop_after.position=Vector2(455,389);stop_after.size=Vector2(100,38);stop_after.tooltip_text=tip
	stop_after.get_line_edit().focus_exited.connect(func():call_deferred("load_settings"))
	stop_after.value_changed.connect(func(_value):_settings_changed(false))
	capture_page.add_child(stop_after);controls.append(stop_after)
	var after:Label=world.text("只后停止（0＝不停）",17);after.name="HuntStopAfterNote";after.position=Vector2(563,399);after.mouse_filter=Control.MOUSE_FILTER_PASS;after.tooltip_text=tip;capture_page.add_child(after)

## 抓宠设置's right column: the 后台搜宠 switch, 排队上限, and the 自动练级
## 经验倍率 / 战斗速度 its training uses (the same values as 自动练级's own).
func install_fallback_controls(attempts: SpinBox, rate: SpinBox, hp: SpinBox)->void:
	for entry in [[attempts,"CaptureFallbackAttempts","难抓：失败次数",299],[rate,"CaptureFallbackRate","难抓：成功率低于 %",349],[hp,"CaptureFallbackHp","难抓：削血到 %",399]]:
		var input: SpinBox=entry[0]
		# Placed beside its caption: reparent keeps the global position, which
		# put each box one row above its own caption.
		input.reparent(capture_page);input.name=entry[1];input.position=Vector2(230,int(entry[3])-10);input.size=Vector2(150,38);controls.append(input)
		input.tooltip_text="混合敌群先由五人不带出战宠清场，保护全部 Lv.1；难抓时才换随身队伍中存活、非骑乘且符合等级上限的削血宠。血量线取本项与抓宠血量线的较低值。缺少合适宠物会暂停，预演也使用同一策略。"
		var caption:Label=world.text(entry[2],16);caption.position=Vector2(24,int(entry[3]));capture_page.add_child(caption)

func showcase_controls()->void:
	var name_text:=AutomationSettings.SHOWCASE_NAME
	showcase=CheckBox.new();showcase.name="ShowcaseMode";showcase.text=name_text;showcase.button_pressed=true;showcase.position=Vector2(760,139)
	showcase.tooltip_text="找宠流程一边在后台继续找，一边正常播放找到的宠物的捕获战斗和自动练级到120的每一场战斗；找到的先排队。关掉则像以前一样全速捕获、瞬间练满。"
	capture_page.add_child(showcase);controls.append(showcase)
	showcase.toggled.connect(func(_value):_settings_changed(true))
	var queue_label:Label=world.text("排队上限",16);queue_label.position=Vector2(760,199);capture_page.add_child(queue_label)
	queue_size=SpinBox.new();queue_size.name="ShowcaseQueue";queue_size.min_value=1;queue_size.max_value=50;queue_size.step=1;queue_size.value=10
	queue_size.position=Vector2(880,189);queue_size.size=Vector2(130,38);queue_size.tooltip_text="每个品种各自排队，各自最多这么多只。某个品种排满后，新找到的和这个品种排队的一起比较，按它的保留规则排序放弃最差的一只，记入放生记录（未捕获·排队已满）；不影响其他品种。轮流抓：每次抓下一个品种排第一的。"
	queue_size.value_changed.connect(func(_value):_settings_changed(false))
	capture_page.add_child(queue_size);controls.append(queue_size)
	var xp_label:Label=world.text("经验倍率",16);xp_label.position=Vector2(760,259);capture_page.add_child(xp_label)
	showcase_xp=OptionButton.new();showcase_xp.name="ShowcaseXp";showcase_xp.position=Vector2(880,249);showcase_xp.size=Vector2(130,38)
	for title in ["1×","2×","10×","100×"]:showcase_xp.add_item(title)
	showcase_xp.tooltip_text="与自动练级的经验倍率是同一个设置。"
	showcase_xp.item_selected.connect(func(_index):_settings_changed(true))
	capture_page.add_child(showcase_xp)
	var speed_label:Label=world.text("战斗速度",16);speed_label.position=Vector2(760,319);capture_page.add_child(speed_label)
	showcase_speed=OptionButton.new();showcase_speed.name="ShowcaseSpeed";showcase_speed.position=Vector2(880,309);showcase_speed.size=Vector2(130,38)
	for title in ["1×","2×","4×","8×"]:showcase_speed.add_item(title)
	showcase_speed.tooltip_text="与自动练级的战斗速度是同一个设置，由这台设备记住。"
	showcase_speed.item_selected.connect(func(index):world.set_battle_speed([1.0,2.0,4.0,8.0][index]))
	capture_page.add_child(showcase_speed)
	resume_after_restart=CheckBox.new();resume_after_restart.name="ResumeAfterRestart";resume_after_restart.text="重启后自动恢复";resume_after_restart.button_pressed=true;resume_after_restart.position=Vector2(760,369)
	resume_after_restart.tooltip_text="服务器重启时记下正在运行的找宠流程、筛选或自动练级（设置、排队的宠物、已遇敌组数和本轮计数），重启后角色还在原地就自动接着运行，停止记录和信息框写「服务器重启后已恢复」。重启时正在打的捕获或练级战斗按逃跑结束，重启后按原种子重新抓或接着练。摸底要重新开始。"
	capture_page.add_child(resume_after_restart);controls.append(resume_after_restart)
	resume_after_restart.toggled.connect(func(_value):_settings_changed(true))
	clean_only=CheckBox.new();clean_only.name="CleanOnly";clean_only.text="只进无其他敌人的遇敌";clean_only.button_pressed=true;clean_only.position=Vector2(760,399)
	clean_only.tooltip_text="找 Lv.1 时，敌群里只要有高于 Lv.1 的敌人就跳过不进（同组别的 Lv.1 宠物不算，打不过人也伤不了队伍）。抓宠时不打其他敌人，混进高等级敌人容易战败，扣魅力和宠物忠诚。敌群在进战斗前就已算好，跳过只是多找一会儿。"
	capture_page.add_child(clean_only);controls.append(clean_only)
	clean_only.toggled.connect(func(_value):
		_show_mixed_option()
		_settings_changed(true))
	mixed_if_stats=CheckBox.new();mixed_if_stats.name="MixedIfStats";mixed_if_stats.text="属性达标仍进混合遇敌";mixed_if_stats.position=Vector2(760,429)
	mixed_if_stats.tooltip_text="找宠流程里，这只 Lv.1 预测的120级属性达到已启用的属性条件时，即使同组有高等级敌人也去抓。进战斗前用真实战斗核心预演五次：五人先不带出战宠清掉高等级敌人，保护所有 Lv.1，之后主角抓、队友等待；难抓才换合适削血宠。打不赢就暂停并说明。"
	capture_page.add_child(mixed_if_stats);controls.append(mixed_if_stats)
	mixed_if_stats.toggled.connect(func(_value):_settings_changed(true))

## 属性达标仍进混合遇敌 only matters while 只进无其他敌人的遇敌 is on.
func _show_mixed_option()->void:
	if not is_instance_valid(mixed_if_stats):return
	mixed_if_stats.disabled=clean_only.disabled or not clean_only.button_pressed

func show_capture_settings(enabled:bool)->void:
	if is_instance_valid(stat_page):stat_page.hide()
	for node in filter_nodes:node.visible=not enabled
	capture_page.visible=enabled
	_remember_page("capture" if enabled else "filters")

## The page shown is remembered on this device and shown again on opening.
func _remember_page(which: String)->void:
	page=which
	if _built and is_instance_valid(world):world.set_viewer_pref("hunt_page",which)

func show_page(which: String)->void:
	match which:
		"capture":show_capture_settings(true)
		"stats":show_stat_settings()
		_:show_capture_settings(false)

func start_requested()->void:
	if train_after_capture.button_pressed:world.pet_workflow.start_cycle()
	else:start_hunt()

func ready_description()->String:
	if train_after_capture.button_pressed:return "准备就绪：自动找宠→捕捉→练到120；属性达标停止比较，未达标存仓继续（无条件仅一轮）。"
	if auto_capture.button_pressed:return "准备就绪：开始后筛选达标宠物并自动捕捉。"
	return "准备就绪：筛选达标后进入战斗，由你手动捕捉。"

func refresh_ready_status()->void:
	if not running and not start_button.disabled:status.text=ready_description()

func workflow_summary()->String:
	var skipped:=""
	if is_instance_valid(world.pet_workflow) and world.pet_workflow.skipped_count>0:
		skipped="已跳过 %d 只 · 最近 %s\n" % [world.pet_workflow.skipped_count,world.pet_workflow.skip_note]
	var line:=threshold_line()
	return skipped+(line+"\n" if not line.is_empty() else "")+_workflow_counts()

## The cycle's 摸底 (remaining time, candidates) while it runs, else the
## thresholds it hunts with now (the first species), else "".
func threshold_line()->String:
	var flow:Dictionary=world.state.automation.get("flow",{}) if is_instance_valid(world) else {}
	if not world.pet_workflow.active():return ""
	var survey:Dictionary=flow.get("survey",{})
	if bool(survey.get("active",false)):
		return "摸底中（%s）：剩 %s%s · 候选 %d 只 · 不设门槛，结束后按保留规则挑选" % ["、".join(survey.get("names",[])),duration_text(float(survey.get("remaining",0))),shared_text(int(survey.get("hunters",1))),int(survey.get("candidates",0))]
	var text:=str(flow.get("thresholds","")).get_slice("\n",0)
	if int(survey.get("pending",0))>0:text="摸底选中 %d 只待抓 · %s" % [int(survey.pending),text]
	return "门槛 "+text if not text.is_empty() else ""

func _workflow_counts()->String:
	if is_instance_valid(world.pet_workflow) and (world.pet_workflow.predicted_rejects>0 or world.pet_workflow.kept_count>0):
		var flow=world.pet_workflow
		var best_seen:Dictionary=flow.best_predicted
		var best_text:String="暂无" if best_seen.is_empty() else "三围合%d 攻%d"%[int(best_seen.sum),int(best_seen.attack)]
		var kept:String="（保留规则自动整理：同种现有%d只，已放生%d只）"%[flow.held_count,flow.released_count] if flow.keep_auto else ""
		return "本轮达标存仓 %d/%s 只%s · 滚动淘汰 %d 只 · 预测未达标跳过 %s 只 · 最好预测 %s\n" % [flow.collected_count,flow.collect_target_text(),kept,flow.pruned_count,cn_count(flow.predicted_rejects),best_text]
	if is_instance_valid(world.pet_workflow) and world.pet_workflow.stored_count>0:
		status.tooltip_text=world.pet_workflow.last_result
		return "未达标 %d 只（滚动淘汰 %d 只）· 最近 %s 三围合%d，继续找宠\n" % [world.pet_workflow.stored_count,world.pet_workflow.pruned_count,world.pet_workflow.last_stored_id,world.pet_workflow.last_stored_total]
	return ""

func build_stat_page()->void:
	stat_page=Control.new();stat_page.name="PetStatConditionsPage";stat_page.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(stat_page)
	var tab:Button=world.button("属性条件",show_stat_settings);tab.position=Vector2(895,18);panel.add_child(tab)
	stat_heading=world.text("",19);stat_heading.name="StatHeading";stat_heading.position=Vector2(24,130);stat_page.add_child(stat_heading)
	stat_heading.mouse_filter=Control.MOUSE_FILTER_PASS
	stat_species=OptionButton.new();stat_species.name="StatFilterSpecies";stat_species.position=Vector2(24,170);stat_species.size=Vector2(370,38);stat_page.add_child(stat_species);controls.append(stat_species)
	stat_species.item_selected.connect(func(_i):
		# Changes to the species shown until now are saved before switching.
		world.flush_automation_settings()
		_stat_species_fallback=false
		load_stat_settings()
		_settings_changed(true))
	stat_mode=OptionButton.new();stat_mode.name="StatFilterMode";stat_mode.position=Vector2(430,170)
	stat_mode.add_item("全部满足（AND）");stat_mode.add_item("任一满足（OR）");stat_page.add_child(stat_mode);controls.append(stat_mode);stat_mode.item_selected.connect(func(_i):save_stat_settings(true))
	stat_threshold_mode=OptionButton.new();stat_threshold_mode.name="StatThresholdMode";stat_threshold_mode.position=Vector2(640,170)
	for mode in StatFilter.THRESHOLD_MODES:stat_threshold_mode.add_item(StatFilter.THRESHOLD_MODE_NAMES[mode])
	stat_threshold_mode.tooltip_text="相对：门槛＝同种现有最高 − x，抓到更好的宠物后自动提高，适合前期。\n绝对：门槛是固定数值，不随宠物变化、不摸底，已有极品后可放宽。\n两种数值各自保存，来回切换不会丢；第一次切到绝对时按当前门槛填入。"
	stat_page.add_child(stat_threshold_mode);controls.append(stat_threshold_mode);stat_threshold_mode.item_selected.connect(func(_i):switch_threshold_mode())
	for i in range(4):
		var metric:String=StatFilter.METRICS[i]
		var check:=CheckBox.new();check.name="StatEnabled_"+metric;check.text=StatFilter.METRIC_NAMES[metric]+" ≥ 最高 −";check.position=Vector2(24+(i%2)*470,228+(i/2)*55);stat_page.add_child(check);controls.append(check);stat_checks[metric]=check
		var input:=number(Vector2(200+(i%2)*470,228+(i/2)*55),-100,1000,1);input.name="StatMinus_"+metric;input.size.x=80;input.reparent(stat_page);stat_numbers[metric]=input
		var fixed:=number(Vector2(140+(i%2)*470,228+(i/2)*55),0,3000,0);fixed.name="StatValue_"+metric;fixed.size.x=96;fixed.reparent(stat_page);fixed.hide();stat_values[metric]=fixed
		fixed.value_changed.connect(func(_value):save_stat_settings();refresh_stat_thresholds(true))
		var result:Label=world.text("",16);result.name="StatThreshold_"+metric;result.position=Vector2(284+(i%2)*470,238+(i/2)*55);result.mouse_filter=Control.MOUSE_FILTER_PASS;stat_page.add_child(result);stat_results[metric]=result
		var keep_label:Label=world.text("留前",16);keep_label.position=Vector2(344+(i%2)*470,238+(i/2)*55);stat_page.add_child(keep_label)
		var keep:=number(Vector2(384+(i%2)*470,228+(i/2)*55),0,1000,0);keep.name="StatKeep_"+metric;keep.size.x=84;keep.tooltip_text="仓库滚动保留：按此项排名保留前N只自动找宠存入的宠物，其余删除。0＝此项不保留名额；四项全0＝不删除。";keep.reparent(stat_page);stat_keeps[metric]=keep
		check.toggled.connect(func(_on):save_stat_settings(true));input.value_changed.connect(func(_value):save_stat_settings();refresh_stat_thresholds(true));keep.value_changed.connect(func(_value):save_stat_settings())
	# The shared status line starts at y 478, so the page ends above it; the notes
	# are tooltips. 找到N只后停止 is on 抓宠设置, one for the whole run.
	build_keep_rule(340)
	refresh_stat_species()

## 保留规则 rows: 看最高[T]档，每档留[K]只，档内排序[第一][第二][第三];
## 单项各留前[M]名 □攻击 □防御 □敏捷 □血, □找宠时自动整理.
func build_keep_rule(top: float)->void:
	var add_label:=func(text: String, x: float, y: float)->Label:
		var label:Label=world.text(text,17);label.position=Vector2(x,y+10);stat_page.add_child(label)
		return label
	var heading:Label=add_label.call("保留规则：看最高",24,top)
	heading.mouse_filter=Control.MOUSE_FILTER_PASS
	heading.tooltip_text="按现有同种宠物滚动比较：最高几档三围合各留前几只，加上勾选单项的前几名，收藏、出战、骑乘和削血宠永远保留，其余可放生。同种比较里「按保留规则选中」可先预览；勾选「找宠时自动整理」后每存入一只就自动整理。"
	rule_tiers=number(Vector2(168,top),0,20,2);rule_tiers.name="KeepRuleTiers";rule_tiers.size.x=90;rule_tiers.reparent(stat_page)
	rule_tiers.tooltip_text="按三围合分档，只看最高的几档（例如626和625两档）。0＝不按档保留，只留单项前几名。"
	add_label.call("档，每档留",264,top)
	rule_per_tier=number(Vector2(354,top),0,1000,3);rule_per_tier.name="KeepRulePerTier";rule_per_tier.size.x=90;rule_per_tier.reparent(stat_page)
	rule_per_tier.tooltip_text="每档按右边的排序留前几只；同样的属性按较早的编号优先。"
	add_label.call("只，档内",450,top)
	for i in range(3):
		var pick:=OptionButton.new();pick.name="StatRank%d"%(i+1);pick.position=Vector2(530+i*165,top);pick.size=Vector2(155,38)
		pick.tooltip_text=["档内第一排序","同分时第二排序","同分时第三排序"][i]
		if i>0:pick.add_item(["","第二：无","第三：无"][i],0)
		for key in StatFilter.RANK_KEYS:pick.add_item(["第一","第二","第三"][i]+"："+StatFilter.RANK_NAMES[key],StatFilter.RANK_KEYS.find(key)+1)
		stat_page.add_child(pick);controls.append(pick);stat_rank.append(pick)
		pick.item_selected.connect(func(_i):save_stat_settings(true))
	var row:=top+46
	add_label.call("单项各留前",24,row)
	rule_champions=number(Vector2(120,row),0,1000,2);rule_champions.name="KeepRuleChampions";rule_champions.size.x=90;rule_champions.reparent(stat_page)
	rule_champions.tooltip_text="勾选的单项里，全体同种排名前几的也保留（不管三围合是多少）。"
	add_label.call("名：",216,row)
	for i in range(KeepRule.STATS.size()):
		var stat:String=KeepRule.STATS[i]
		var check:=CheckBox.new();check.name="KeepRuleStat_"+stat;check.text=KeepRule.STAT_NAMES[stat];check.position=Vector2(256+i*78,row+2)
		stat_page.add_child(check);controls.append(check);rule_stats[stat]=check
		check.toggled.connect(func(_on):save_stat_settings(true))
	rule_auto=CheckBox.new();rule_auto.name="KeepRuleAuto";rule_auto.text="找宠时自动整理";rule_auto.position=Vector2(590,row+2)
	rule_auto.tooltip_text="每存入一只就按保留规则整理整个同种（随身和仓库），放生规则外的宠物。收藏、出战、骑乘和削血宠不动。默认关：可先在同种比较里用「按保留规则选中」预览。"
	stat_page.add_child(rule_auto);controls.append(rule_auto);rule_auto.toggled.connect(func(_on):save_stat_settings(true))
	for input in [rule_tiers,rule_per_tier,rule_champions]:input.value_changed.connect(func(_value):save_stat_settings())

## 属性条件 lists the species that live here, and 蓝人龙 only when it lives
## here, is the saved choice or nothing else does. `chosen` stands in for the
## saved species while a new choice is on its way to the profile.
func refresh_stat_species(chosen: int = -2)->void:
	var saved:=chosen if chosen>=-1 else int(world.automation_settings().hunt.get("stat_species",-1))
	stat_species.clear()
	if saved==92 or candidates.is_empty() or candidates.any(func(item):return int(item.id)==92):stat_species.add_item("扬奇洛斯（蓝人龙）",92)
	for item in candidates:
		if int(item.id)!=92:stat_species.add_item(str(item.name),int(item.id))
	_select_stat_species(saved)

## Shows the saved 属性条件 species (hunt.stat_species), else the target
## species, else the first. A saved species that does not live here is kept
## for later (_stat_species_fallback) while the page shows the next choice.
func _select_stat_species(saved: int = -2)->void:
	var hunt:Dictionary=world.automation_settings().hunt
	if saved<-1:saved=int(hunt.get("stat_species",-1))
	var index:=stat_species.get_item_index(saved) if saved>=0 else -1
	_stat_species_fallback=saved>=0 and index<0
	if index<0 and int(hunt.template)>=0:index=stat_species.get_item_index(int(hunt.template))
	stat_species.select(maxi(0,index))
	load_stat_settings()

## 瞬移去抓 saved this target, Lv.1 limit and 属性条件 species: show them now,
## since a remote client gets the saved settings back only a round trip later.
func show_target(template_id: int, level_one_only: bool) -> void:
	level_one.set_pressed_no_signal(level_one_only)
	refresh_candidates()
	var index:=species.get_item_index(template_id)
	if index>=0 and not species.is_item_disabled(index):
		species.select(index)
		_template_fallback=false
	refresh_stat_species(template_id)

func show_stat_settings()->void:
	show_capture_settings(false)
	for node in filter_nodes:node.hide()
	stat_page.show()
	_remember_page("stats")

## Shows the selected species' conditions from the profile. Switching species
## rewrites every control; a profile update skips the number being typed.
func load_stat_settings()->void:
	loading_stat_settings=true
	var template_id:=stat_species.get_selected_id()
	var switching:=template_id!=_stat_species_shown
	_stat_species_shown=template_id
	var settings:Dictionary=world.stat_filter(template_id)
	var rule:Dictionary=settings.get("keep_rule",{})
	var flat:={"mode":str(settings.mode),"threshold_mode":str(settings.get("threshold_mode","relative")),"tiers":int(rule.get("tiers",2)),"per_tier":int(rule.get("per_tier",3)),"champions":int(rule.get("champions",2)),
		"rank":rule.get("order",["attack","speed","max_hp"]).duplicate(),"champion_stats":rule.get("champion_stats",KeepRule.STATS).duplicate(),"auto":bool(rule.get("auto",false))}
	for metric in StatFilter.METRICS:
		for field in ["enabled","minus","value","keep"]:flat[metric+"."+field]=settings.conditions[metric].get(field,0)
	var old:Dictionary={} if switching else _stat_loaded
	var shown:=flat.duplicate()
	if _changed(old,flat,"mode"):stat_mode.select(1 if flat.mode=="any" else 0)
	if _changed(old,flat,"threshold_mode"):stat_threshold_mode.select(maxi(0,StatFilter.THRESHOLD_MODES.find(flat.threshold_mode)))
	for metric in StatFilter.METRICS:
		if _changed(old,flat,metric+".enabled"):stat_checks[metric].set_pressed_no_signal(bool(flat[metric+".enabled"]))
		for entry in [[stat_numbers[metric],metric+".minus"],[stat_values[metric],metric+".value"],[stat_keeps[metric],metric+".keep"]]:
			if not _sync_spin(entry[0],old.get(entry[1]),flat[entry[1]],switching):shown[entry[1]]=old[entry[1]]
	for entry in [[rule_tiers,"tiers"],[rule_per_tier,"per_tier"],[rule_champions,"champions"]]:
		if not _sync_spin(entry[0],old.get(entry[1]),flat[entry[1]],switching):shown[entry[1]]=old[entry[1]]
	if switching or not AutomationSettings._same(old.get("rank"),flat.rank):_show_rank(flat.rank)
	if switching or not AutomationSettings._same(old.get("champion_stats"),flat.champion_stats):
		for stat in KeepRule.STATS:rule_stats[stat].set_pressed_no_signal(flat.champion_stats.has(stat))
	if _changed(old,flat,"auto"):rule_auto.set_pressed_no_signal(flat.auto)
	_stat_loaded=shown
	loading_stat_settings=false
	refresh_stat_thresholds(true)

## Shows each condition's threshold for the species shown. Relative: the
## check reads 「三围合 ≥ 最高627 −」, the number is x and the label 「= 626」
## (摸底 with no pet of the species). Absolute: 「三围合 ≥」, the number is the
## value and the label, faint, 「（现有最高627）」. Recomputed when the pets
## change (at most once a second unless `now`), since pets under Lv120 are
## projected.
func refresh_stat_thresholds(now: bool = false) -> void:
	if _stat_species_shown<0 or stat_results.is_empty():return
	if not now and Time.get_ticks_msec()-_thresholds_msec<1000:return
	_thresholds_msec=Time.get_ticks_msec()
	var fixed:=_threshold_mode_shown()=="absolute"
	var best:=shown_maxima()
	var key:="%d|%s|%s|%s" % [_stat_species_shown,JSON.stringify(best),fixed,",".join(StatFilter.METRICS.map(func(metric):return "%d/%d" % [int(stat_numbers[metric].value),int(stat_values[metric].value)]))]
	if key==_thresholds_key and not now:return
	_thresholds_key=key
	stat_heading.text="120级属性筛选 · 门槛＝固定数值，不随宠物变化，不摸底" if fixed else "120级属性筛选 · 门槛＝同种现有最高 − x，随更好的宠物提高"
	stat_heading.tooltip_text=("绝对：每项门槛是填写的固定数值（≥），抓到更好的宠物也不变，也不需要摸底；排队的宠物只按这些数值判断。已有极品后用它放宽门槛。" if fixed else "最高＝随身和仓库里这个品种的宠物中，该项120级属性最高的数值（未满120级按成长种子精确推算）。抓到、存入或放生后门槛随之更新。\n还没有这个品种时先摸底%d秒：不设门槛找，按保留规则挑出最好的几只抓来，之后按新的最高继续。" % AutomationSettings.SURVEY_SECONDS)+"\n每个品种默认勾三围合和攻击（任一满足，最高 − 1）；全部不勾就不按属性判断，每只升满120级的都算留下。\n改动立即用于正在进行的找宠（正在抓或练的这只除外）。"
	for i in range(StatFilter.METRICS.size()):
		var metric:String=StatFilter.METRICS[i]
		var condition:={"enabled":true,"minus":int(stat_numbers[metric].value),"value":int(stat_values[metric].value)}
		var name:String=StatFilter.METRIC_NAMES[metric]
		var result:Label=stat_results[metric]
		stat_numbers[metric].visible=not fixed;stat_values[metric].visible=fixed
		if fixed:
			stat_checks[metric].text="%s ≥" % name
			result.position.x=240+(i%2)*470
			result.text="（现有最高%d）" % int(best[metric]) if best.has(metric) else ""
			result.modulate.a=0.55
		else:
			stat_checks[metric].text="%s ≥ 最高%s −" % [name,str(best[metric]) if best.has(metric) else ""]
			result.position.x=284+(i%2)*470
			result.text="= %d" % (int(best[metric])-int(condition.minus)) if best.has(metric) else "摸底"
			result.modulate.a=1.0
		var sentence:=StatFilter.describe_condition(metric,condition,best,fixed)
		stat_checks[metric].tooltip_text=sentence;result.tooltip_text=sentence

## The best Lv120 values of the species shown among the player's own pets
## (carried and warehouse), as the backend counts them.
func shown_maxima()->Dictionary:
	# The warehouse arrives apart from the profile (client_state.pet_storage).
	var profile:Dictionary={"pets":world.state.profile.get("pets",[]),"pet_storage":world.state.pet_storage}
	return StatFilter.maxima(KeepRule.species_pets(profile,_stat_species_shown).map(KeepRule.stats_of))

func _threshold_mode_shown()->String:
	return StatFilter.THRESHOLD_MODES[clampi(stat_threshold_mode.selected,0,1)] if is_instance_valid(stat_threshold_mode) else "relative"

## 相对 ↔ 绝对. The first switch to 绝对 fills each value with the threshold
## hunted now (最高 − x, or the default without a pet of the species), so what
## is hunted does not jump; a value the player saved is kept.
func switch_threshold_mode()->void:
	if loading_stat_settings:return
	if _threshold_mode_shown()=="absolute":
		var saved:Dictionary=world.automation_overrides().get("stat_filters",{}).get(str(_stat_species_shown),{}).get("conditions",{})
		var own:=StatFilter.METRICS.filter(func(metric):return saved.get(metric,{}).has("value"))
		# The x shown (maybe not saved yet) and the saved or default values.
		var shown:={"conditions":{}}
		for metric in StatFilter.METRICS:shown.conditions[metric]={"minus":int(stat_numbers[metric].value),"value":int(stat_values[metric].value)}
		var values:=StatFilter.absolute_values(shown,shown_maxima(),own)
		loading_stat_settings=true
		for metric in StatFilter.METRICS:stat_values[metric].value=values[metric]
		loading_stat_settings=false
	refresh_stat_thresholds(true)
	save_stat_settings(true)

## The ranking order the three selectors show: 第一, then 第二 and 第三 unless
## 无 or already chosen.
func rank_choice()->Array:
	var order:=[]
	for pick in stat_rank:
		var id:=pick.get_selected_id()
		if id>=1 and not order.has(StatFilter.RANK_KEYS[id-1]):order.append(StatFilter.RANK_KEYS[id-1])
	return order

func _show_rank(order: Array)->void:
	for i in range(stat_rank.size()):
		var key:String=str(order[i]) if i<order.size() else ""
		stat_rank[i].select(stat_rank[i].get_item_index(StatFilter.RANK_KEYS.find(key)+1 if key in StatFilter.RANK_KEYS else 0))

## A condition changed: saved to the profile once the player pauses.
func save_stat_settings(now: bool = false)->void:
	if loading_stat_settings:return
	_settings_changed(now)

## Saves typed numbers and pending changes now (before a find-pet cycle).
func commit_stat_settings()->void:
	for input in stat_numbers.values()+stat_values.values()+stat_keeps.values()+[stop_after,rule_tiers,rule_per_tier,rule_champions]:
		if input.get_line_edit().has_focus():input.apply()
	world.mark_settings_dirty(self)
	world.flush_automation_settings()

static func _automation_active(automation: Dictionary) -> bool:
	return bool(automation.get("hunt",{}).get("running",false)) or str(automation.get("flow",{}).get("phase","idle")) in ["hunt","capture","train","restart"]

## Collapses the window into a small progress bar. The scan or find-pet cycle
## continues and the world, HUD and other panels (pets, warehouse) stay usable.
func minimize() -> void:
	if minimized or not _automation_active(world.state.automation):return
	minimized=true
	minimized_flow=world.pet_workflow.active()
	hide();world.clear_input()
	_chip().pop_up();_update_chip()
	world.release_input()
	world.set_viewer_pref("hunt_minimized",true)

## Brings the full window back with the backend's current progress.
func restore() -> void:
	if not minimized:return
	_end_minimized()
	if world.adventure_menu.visible:world.close_adventure_menu()
	world.set_viewer_pref("hunt_minimized",false)
	world.clear_input();world.paused_input=true
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show()
	var active:=_automation_active(world.state.automation)
	set_controls(active)
	if active:update_status()

func _end_minimized() -> void:
	if not minimized:return
	minimized=false
	if is_instance_valid(chip):chip.hide()

func _chip() -> Panel:
	if not is_instance_valid(chip):
		chip=preload("res://scripts/automation_chip.gd").new()
		chip.name="PetHuntChip"
		chip.setup(world,"自动抓极品",0,restore,3,560.0)
		get_parent().add_child(chip)
	return chip

## Readouts refresh at most this often (10 per second); 0 refreshes at once.
var refresh_msec := 100
var _chip_shown_msec := -100000
var _chip_dirty := false
var _status_shown_msec := -100000

func _update_chip() -> void:
	if not is_instance_valid(chip):return
	var now := Time.get_ticks_msec()
	if now-_chip_shown_msec<refresh_msec:
		_chip_dirty=true;return
	_chip_shown_msec=now;_chip_dirty=false
	var counts:="遇敌 %s 组 · 检查 %s 只 · %s · 本轮 %s" % [cn_count(rolls),cn_count(inspected),rolls_text(rolls/maxf(elapsed,0.001)),duration_text(elapsed)]
	var flow=world.pet_workflow
	if flow.active():
		var step: String={"hunt":"筛选中","capture":"捕捉中","train":"升级中","restart":"准备下一轮"}.get(flow.phase,"")
		var survey:Dictionary=world.state.automation.get("flow",{}).get("survey",{})
		if bool(survey.get("active",false)):step="摸底中 剩%s%s · 候选%d只" % [duration_text(float(survey.get("remaining",0))),shared_text(int(survey.get("hunters",1))),int(survey.get("candidates",0))]
		var kept:String=" · 同种%d/放生%d"%[flow.held_count,flow.released_count] if flow.keep_auto else ""
		var waiting:=int(world.state.automation.get("flow",{}).get("queue_size",0))
		var total: float=flow.elapsed_seconds()
		var found:=int(flow.collected_count)+int(flow.stored_count)
		var average:="平均 %s/只" % duration_text(total/found) if found>0 else "平均 —"
		chip.present("自动抓极品 · 找宠流程 · "+step,
			"%s\n达标 %d/%s%s · 未达标 %d · 跳过 %d · 预测跳过 %s%s\n总用时 %s · %s" % [counts,flow.collected_count,flow.collect_target_text(),kept,flow.stored_count,flow.skipped_count,cn_count(flow.predicted_rejects),(" · 排队 %d" % waiting if waiting>0 else ""),duration_text(total),average])
		if flow.skipped_count>0:chip.tooltip_text=flow.skip_note
	else:
		chip.present("自动抓极品 · 筛选中",counts+"\n最好总档 %s" % ("暂无" if best< -8 else "%+d"%best))

## A count in Chinese units: 9999, 1.23万, 4.56亿, 7.89万亿.
static func cn_count(value: float) -> String:
	if absf(value)>=1e12:return "%.2f万亿" % (value/1e12)
	if absf(value)>=1e8:return "%.2f亿" % (value/1e8)
	if absf(value)>=1e4:return "%.2f万" % (value/1e4)
	return str(int(value))

## 45秒, 3分05秒, 2小时03分.
static func duration_text(seconds: float) -> String:
	var s:=int(seconds)
	if s<60:return "%.1f秒" % seconds if seconds<10 else "%d秒" % s
	if s<3600:return "%d分%02d秒" % [s/60,s%60]
	return "%d小时%02d分" % [s/3600,(s/60)%60]
