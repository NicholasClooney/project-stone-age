extends Control
## Optional single-player data inspection. Rolls real local troops; never grants rewards.
## Scanning runs in the backend (res://server/automation.gd); this menu chooses
## the filter and presents progress.
const StatFilter=preload("res://scripts/pet_stat_filter.gd")
var stat_page: Control
var stat_species: OptionButton
var stat_mode: OptionButton
var stat_checks: Dictionary = {}
var stat_numbers: Dictionary = {}
var stat_stop_after: SpinBox
var stat_keeps: Dictionary = {}
var loading_stat_settings := false
const CapturePolicy=preload("res://scripts/battle_auto_policy.gd")
const Rules = preload("res://scripts/pet_hunt_rules.gd")
var filter_nodes: Array[Control] = []
var capture_page: Control
var train_after_capture: CheckBox
var world: Node
var panel: Panel
var species: OptionButton
var auto_capture: CheckBox
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
	level_one.toggled.connect(func(_value):refresh_candidates())
	auto_capture=CheckBox.new();auto_capture.text="达标后自动抓宠";auto_capture.position=Vector2(760,132)
	panel.add_child(auto_capture);controls.append(auto_capture)
	label("成长档预设",Vector2(24,194),17)
	preset=OptionButton.new();preset.position=Vector2(140,184);preset.size=Vector2(480,38)
	for title in ["不限品质 · 快速试用","优秀：总成长档 +4 或更高","极品：总成长档 +6 或更高","满档：四项成长档均 +2","自定义"]:preset.add_item(title)
	preset.select(3);preset.item_selected.connect(apply_preset)
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
	label("每秒遇敌",Vector2(24,433),17);rate=number(Vector2(140,423),0,100000,0)
	rate.tooltip_text="0为不限速：每帧用满约12毫秒工作预算。填正数则按该目标限速。"
	label("本轮上限",Vector2(340,433),17);limit=number(Vector2(460,423),0,1000000,0)
	label("组；0为不限，到上限暂停。",Vector2(610,433),16)
	status=label("",Vector2(24,478),14);status.size=Vector2(1040,80);status.clip_text=true;status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	start_button=world.button("开始筛选",start_requested);start_button.name="StartPetHunt";start_button.position=Vector2(24,560);panel.add_child(start_button)
	stop_button=world.button("停止",func():stop_hunt("已停止，可调整条件后重新开始。"));stop_button.name="StopPetHunt";stop_button.position=Vector2(220,560);panel.add_child(stop_button)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(900,560);panel.add_child(close)
	for child in panel.get_children():
		if child is Control and child.position.y>=129 and child.position.y<=460:filter_nodes.append(child)
	capture_page=Control.new();capture_page.name="CaptureSettingsPage";capture_page.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(capture_page)
	var filters_tab:Button=world.button("筛选条件",func():show_capture_settings(false));filters_tab.name="HuntFilterTab";filters_tab.position=Vector2(585,18);panel.add_child(filters_tab)
	var capture_tab:Button=world.button("抓宠设置",func():show_capture_settings(true));capture_tab.name="HuntCaptureTab";capture_tab.position=Vector2(740,18);panel.add_child(capture_tab)
	train_after_capture=CheckBox.new();train_after_capture.text="抓到后直接升至120级 · 按属性条件留存 · 无动画抓宠";train_after_capture.tooltip_text="成长按宠物种子逐级固定，直接升级与战斗练级结果相同。有属性条件：达标则停止比较，未达标存仓并继续；无条件则升完一只停止。";train_after_capture.name="TrainCapturedPetTo120";train_after_capture.position=Vector2(24,430);capture_page.add_child(train_after_capture);controls.append(train_after_capture)
	train_after_capture.toggled.connect(func(enabled):
		start_button.text="开始抓宠并练至120" if enabled else "开始筛选"
		if enabled:auto_capture.button_pressed=true
		refresh_ready_status())
	auto_capture.toggled.connect(func(enabled):
		if not enabled:train_after_capture.button_pressed=false
		refresh_ready_status())
	train_after_capture.button_pressed=true
	build_stat_page()
	show_capture_settings(false)
	update_explanation()
	hide()

func label(text: String, at: Vector2, size: int) -> Label:
	var result: Label=world.text(text,size)
	result.position=at;result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	panel.add_child(result);return result
func number(at: Vector2, minimum: int, maximum: int, value: int) -> SpinBox:
	var result:=SpinBox.new();result.position=at;result.size=Vector2(130,38)
	result.min_value=minimum;result.max_value=maximum;result.step=1;result.value=value
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
func update_explanation() -> void:
	if not is_instance_valid(explanation) or offsets.size()!=4:return
	var probability: float=Rules.tail_probability(int(total.value),min_offsets())
	explanation.text="同种自然出生个体中，约 %.2f%% 的成长档符合此条件（不是每次遇敌的命中率）。\n+2 是该项出生档上限；四项均 +2 为满档，可真实出现，不保证未来每级都长到最大值。" % (probability*100.0)
func refresh_candidates() -> void:
	var selected:=species.get_selected_id() if species.item_count else -1
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
	start_button.disabled=available==0 or not world.world_catalog.field(int(world.data.map_id))
	location_label.text="当前位置：%s (%d, %d) · 只使用此处原版敌群，不改种类、等级或成长随机值。" % [world.data.name,world.cell.x,world.cell.y]
	status.text="这里没有可用的目标。可到萨姆吉尔西门外筛选 Lv.1 昆依，或关闭 Lv.1 限制。" if start_button.disabled else ready_description()
func open_menu() -> void:
	if visible:close_menu();return
	if world.paused_input or world.area_transition_busy or world.battle_view.visible:return
	if is_instance_valid(world.travel_router):world.travel_router.cancel("已打开极品筛选，停止自动寻路。")
	world.clear_input()
	if world.moving:
		world.moving=false;world.logical_position=Vector2(world.cell);world.player.position=world.project(world.logical_position)
	world.player.set_action(3)
	world.paused_input=true
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show();refresh_candidates();refresh_stat_species();world.training_helper._refresh_pet_choices();stop_button.disabled=true
func close_menu() -> void:
	if not visible:return
	if running:world.link.request({"type":"auto","name":"stop_hunt","reason":"已关闭筛选。"})
	set_controls(false);hide();world.paused_input=false;world.clear_input()
func set_controls(locked: bool) -> void:
	for control in controls:
		if control is SpinBox:control.editable=not locked
		elif control is BaseButton:control.disabled=locked
	start_button.disabled=locked
	stop_button.disabled=not locked
## Validated hunt filter from these controls, or {} with the reason shown.
func build_filter(for_workflow: bool = false) -> Dictionary:
	for control in controls:
		if control is SpinBox and control.get_line_edit().has_focus():control.apply()
	if running or not visible or world.battle_view.visible or world.area_transition_busy:return {}
	if not world.world_catalog.field(int(world.data.map_id)):return {}
	if world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
		status.text="宠物栏已满，请先腾出位置再寻找新伙伴。";return {}
	if int(world.training_helper.capture_hp.value)<100 and level_one.button_pressed and (auto_capture.button_pressed or for_workflow):
		world.training_helper.save_capture_settings()
		var profile:Dictionary=world.session.snapshot()
		var choice:Dictionary=CapturePolicy.capture_pet_choice(profile,world.training_helper.settings,1)
		if choice.has("stop"):
			status.text=str(choice.stop)
			if int(world.training_helper.settings.capture_pet)<0 and str(world.training_helper.settings.get("capture_pet_id","")).is_empty():status.text="缺少可用削血宠：请从仓库取出存活、非骑乘的Lv.1宠物，或手选符合等级上限的削血宠。"
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
	var reply: Dictionary=world.link.request({"type":"auto_start","kind":"hunt","filter":chosen,"map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]})
	if not reply.ok and not reply.get("pending",false):
		if not str(reply.reason).is_empty():status.text=str(reply.reason)
		return
	set_controls(true);update_status()
func stop_hunt(reason: String) -> void:
	if running:world.link.request({"type":"auto","name":"stop_hunt","reason":reason})
	else:on_event({"kind":"hunt_stopped","reason":reason})
func summary() -> String:
	var actual:=rolls / maxf(elapsed,0.001)
	return workflow_summary()+"已遇敌 %d 组 · 检查目标 %d 只 · 最好总档 %s · 本轮 %.1f 秒\n目标 %s · 实际 %.0f 组/秒 · 流程总用时 %s" % [rolls,inspected,"暂无" if best< -8 else "%+d" % best,elapsed,rate_text(int(filter.get("rate",rate.value))),actual,world.pet_workflow.elapsed_text()]
func rate_text(value: int) -> String:return "不限速" if value<=0 else "%d 组/秒"%value
func update_status() -> void:status.text=summary()+"\n筛选中；停止或 Esc 可随时结束。"
func _process(delta: float) -> void:
	if not running:return
	if not visible or not world.paused_input or world.battle_view.visible or world.area_transition_busy or int(world.data.map_id)!=region_map or world.cell!=region_cell:
		stop_hunt("场景状态变化，筛选已停止。");return
	# In-process, this frame drives the backend scan with the same budget.
	if world.link.is_local():world.link.request({"type":"auto","name":"hunt_process","delta":delta})
	if running:update_status()
## Test seam: one backend scan now.
func scan_once() -> void:
	world.link.request({"type":"auto","name":"hunt_scan"})

func on_status(automation: Dictionary) -> void:
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
	pet.position=Vector2(230,209);pet.size=Vector2(470,38);pet.name="CapturePet"
	max_level.position=Vector2(230,279);max_level.size=Vector2(150,38);max_level.name="CapturePetMaxLevel"
	for entry in [["抓宠血量线 %",Vector2(24,149)],["削血宠物",Vector2(24,219)],["削血宠等级上限",Vector2(24,289)],["自动选择最低等级存活宠，且等级不高于目标；手选宠受等级上限限制。",Vector2(24,349)],["默认100%时即可尝试捕捉，满血不保证成功；低于100%才需要削血宠。两种抓宠流程共用设置。",Vector2(24,389)]]:
		var caption:Label=world.text(str(entry[0]),16);caption.position=entry[1];capture_page.add_child(caption)

func show_capture_settings(enabled:bool)->void:
	if is_instance_valid(stat_page):stat_page.hide()
	for node in filter_nodes:node.visible=not enabled
	capture_page.visible=enabled

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
	if is_instance_valid(world.pet_workflow) and (world.pet_workflow.predicted_rejects>0 or world.pet_workflow.kept_count>0):
		var flow=world.pet_workflow
		var best_seen:Dictionary=flow.best_predicted
		var best_text:String="暂无" if best_seen.is_empty() else "三围合%d 攻%d"%[int(best_seen.sum),int(best_seen.attack)]
		return "本轮达标存仓 %d/%s 只 · 滚动淘汰 %d 只 · 预测未达标跳过 %d 只 · 最好预测 %s\n" % [flow.collected_count,flow.collect_target_text(),flow.pruned_count,flow.predicted_rejects,best_text]
	if is_instance_valid(world.pet_workflow) and world.pet_workflow.stored_count>0:
		status.tooltip_text=world.pet_workflow.last_result
		return "未达标 %d 只（滚动淘汰 %d 只）· 最近 %s 三围合%d，继续找宠\n" % [world.pet_workflow.stored_count,world.pet_workflow.pruned_count,world.pet_workflow.last_stored_id,world.pet_workflow.last_stored_total]
	return ""

func build_stat_page()->void:
	stat_page=Control.new();stat_page.name="PetStatConditionsPage";stat_page.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(stat_page)
	var tab:Button=world.button("属性条件",show_stat_settings);tab.position=Vector2(895,18);panel.add_child(tab)
	var heading:Label=world.text("120级属性筛选 · 找宠时按成长种子精确计算",19);heading.position=Vector2(24,130);stat_page.add_child(heading)
	stat_species=OptionButton.new();stat_species.name="StatFilterSpecies";stat_species.position=Vector2(24,170);stat_species.size=Vector2(370,38);stat_page.add_child(stat_species);controls.append(stat_species)
	stat_species.item_selected.connect(func(_i):load_stat_settings())
	stat_mode=OptionButton.new();stat_mode.name="StatFilterMode";stat_mode.position=Vector2(430,170)
	stat_mode.add_item("全部满足（AND）");stat_mode.add_item("任一满足（OR）");stat_page.add_child(stat_mode);controls.append(stat_mode);stat_mode.item_selected.connect(func(_i):save_stat_settings())
	for i in range(4):
		var metric:String=StatFilter.METRICS[i]
		var check:=CheckBox.new();check.name="StatEnabled_"+metric;check.text=["三围合 ≥","攻击 >","防御 >","敏捷 >"][i];check.position=Vector2(24+(i%2)*470,228+(i/2)*55);stat_page.add_child(check);controls.append(check);stat_checks[metric]=check
		var input:=number(Vector2(200+(i%2)*470,228+(i/2)*55),0,1000000,0);input.name="StatMinimum_"+metric;input.size.x=110;input.reparent(stat_page);stat_numbers[metric]=input
		var keep_label:Label=world.text("留前",16);keep_label.position=Vector2(318+(i%2)*470,238+(i/2)*55);stat_page.add_child(keep_label)
		var keep:=number(Vector2(360+(i%2)*470,228+(i/2)*55),0,1000,0);keep.name="StatKeep_"+metric;keep.size.x=100;keep.tooltip_text="仓库滚动保留：按此项排名保留前N只自动找宠存入的宠物，其余删除。0＝此项不保留名额；四项全0＝不删除。";keep.reparent(stat_page);stat_keeps[metric]=keep
		check.toggled.connect(func(_on):save_stat_settings());input.value_changed.connect(func(_value):save_stat_settings());keep.value_changed.connect(func(_value):save_stat_settings())
	var stop_label:Label=world.text("找到",17);stop_label.position=Vector2(24,348);stat_page.add_child(stop_label)
	stat_stop_after=number(Vector2(80,338),0,100000,10);stat_stop_after.name="StatStopAfter";stat_stop_after.reparent(stat_page)
	stat_stop_after.value_changed.connect(func(_value):save_stat_settings())
	var stop_note:Label=world.text("只达标宠物后停止（0＝不停止，1＝找到即停并比较）",17);stop_note.position=Vector2(230,348);stat_page.add_child(stop_note)
	var note:Label=world.text("仅在「抓到后直接升至120级」时生效；每个品种独立设置，本次游戏内保留。\n预测不达标：直接跳过不抓。达标：抓到、升至120并存仓，数量到上限停止并打开比较。\n未启用任何条件：升完一只即停止。低血量、缺少削血宠或存仓失败仍会暂停。",16);note.position=Vector2(24,395);stat_page.add_child(note)
	refresh_stat_species()

func refresh_stat_species()->void:
	var selected:int=stat_species.get_selected_id() if stat_species.item_count else 92
	stat_species.clear();stat_species.add_item("扬奇洛斯（蓝人龙）",92)
	for item in candidates:
		if int(item.id)!=92:stat_species.add_item(str(item.name),int(item.id))
	var index:=stat_species.get_item_index(selected);stat_species.select(maxi(0,index));load_stat_settings()

func show_stat_settings()->void:
	show_capture_settings(false)
	for node in filter_nodes:node.hide()
	stat_page.show()

func load_stat_settings()->void:
	loading_stat_settings=true
	var settings:Dictionary=world.pet_stat_filters.get(stat_species.get_selected_id(),StatFilter.defaults(stat_species.get_selected_id()))
	stat_mode.select(1 if settings.get("mode","all")=="any" else 0)
	for metric in StatFilter.METRICS:
		var condition:Dictionary=settings.conditions[metric]
		stat_checks[metric].button_pressed=condition.enabled;stat_numbers[metric].value=condition.value;stat_keeps[metric].value=int(condition.get("keep",0))
	stat_stop_after.value=int(settings.get("stop_after",StatFilter.defaults(stat_species.get_selected_id()).stop_after))
	loading_stat_settings=false

func save_stat_settings()->void:
	if loading_stat_settings:return
	var settings:=StatFilter.defaults(stat_species.get_selected_id());settings.mode="any" if stat_mode.selected==1 else "all"
	for metric in StatFilter.METRICS:
		settings.conditions[metric].enabled=stat_checks[metric].button_pressed;settings.conditions[metric].value=int(stat_numbers[metric].value);settings.conditions[metric].keep=int(stat_keeps[metric].value)
	settings.stop_after=int(stat_stop_after.value)
	world.pet_stat_filters[stat_species.get_selected_id()]=settings

func commit_stat_settings()->void:
	for input in stat_numbers.values()+stat_keeps.values()+[stat_stop_after]:
		if input.get_line_edit().has_focus():input.apply()
	save_stat_settings()
