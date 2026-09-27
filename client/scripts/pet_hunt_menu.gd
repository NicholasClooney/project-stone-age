extends Control
## Optional single-player data inspection. Rolls real local troops; never grants rewards.
const Rules = preload("res://scripts/pet_hunt_rules.gd")
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
var running := false
var rolls := 0
var inspected := 0
var best := -9
var elapsed := 0.0
var credit := 0.0
var region_map := -1
var region_cell := Vector2i.ZERO
var filter: Dictionary = {}
var last_hit: Dictionary = {}
var candidates: Array = []
var applying := false
var started_usec := 0
var hunt_catalog: RefCounted
const FRAME_BUDGET_USEC := 4000
const MAX_BACKLOG_SECONDS := 0.1

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
	label("轻松助手 · 自动刷极品",Vector2(24,18),24)
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
	label("每秒遇敌",Vector2(24,433),17);rate=number(Vector2(140,423),1,100000,3000)
	rate.tooltip_text="目标速度；实际速度取决于敌群复杂度和设备性能，每帧约 4 毫秒工作预算。"
	label("本轮上限",Vector2(340,433),17);limit=number(Vector2(460,423),1,1000000,100000)
	label("组；到上限暂停，可再次开始。",Vector2(610,433),16)
	status=label("",Vector2(24,478),16);status.size=Vector2(1040,65);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	start_button=world.button("开始筛选",start_hunt);start_button.name="StartPetHunt";start_button.position=Vector2(24,560);panel.add_child(start_button)
	stop_button=world.button("停止",func():stop_hunt("已停止，可调整条件后重新开始。"));stop_button.name="StopPetHunt";stop_button.position=Vector2(220,560);panel.add_child(stop_button)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(900,560);panel.add_child(close)
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
	status.text="这里没有可用的目标。可到萨姆吉尔西门外筛选 Lv.1 昆依，或关闭 Lv.1 限制。" if start_button.disabled else "准备就绪。达标后自动停止并进入原版战斗，由你手动捕捉。"
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
	show();refresh_candidates();stop_button.disabled=true
func close_menu() -> void:
	if not visible:return
	running=false;set_controls(false);hide();world.paused_input=false;world.clear_input()
func set_controls(locked: bool) -> void:
	for control in controls:
		if control is SpinBox:control.editable=not locked
		elif control is BaseButton:control.disabled=locked
	start_button.disabled=locked
	stop_button.disabled=not locked
func start_hunt() -> void:
	if running or not visible or world.battle_view.visible or world.area_transition_busy:return
	if not world.world_catalog.field(int(world.data.map_id)):return
	if world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
		status.text="宠物栏已满，请先腾出位置再寻找新伙伴。";return
	if Rules.tail_probability(int(total.value),min_offsets())<=0:
		status.text="这些条件无法同时满足，请降低门槛。";return
	if Rules.candidates(world.encounter_catalog,int(world.data.map_id),world.cell,level_one.button_pressed).is_empty():
		status.text="当前区域不会出现符合种类／等级条件的宠物。";return
	var usable:=[]
	for index in range(1,species.item_count):
		if not species.is_item_disabled(index):usable.append(species.get_item_id(index))
	if usable.is_empty() or (species.get_selected_id()>=0 and not species.get_selected_id() in usable):
		status.text="当前没有素材齐全的目标宠物。";return
	filter={"usable":usable,"template":species.get_selected_id(),"level_one":level_one.button_pressed,"total":int(total.value),"offsets":min_offsets(),"rate":int(rate.value),"limit":int(limit.value)}
	region_map=int(world.data.map_id);region_cell=world.cell
	# Freeze the validated location for this run. Only trim the spatial lookup;
	# retain original groups/enemies/templates and all roll checks/RNG calls.
	var hunt_data: Dictionary=world.encounter_catalog.data.duplicate()
	hunt_data.areas=[world.encounter_catalog.area_at(region_map,region_cell)]
	hunt_catalog=preload("res://server/encounter_catalog.gd").new(hunt_data)
	rolls=0;inspected=0;best=-9;elapsed=0;credit=0;last_hit={}
	started_usec=Time.get_ticks_usec()
	running=true;set_controls(true);update_status()
func stop_hunt(reason: String) -> void:
	running=false;set_controls(false);status.text=reason+"\n"+summary()
func summary() -> String:
	var actual:=rolls / maxf(elapsed,0.001)
	return "已遇敌 %d 组 · 检查目标 %d 只 · 最好总档 %s · %.1f 秒\n目标 %d 组/秒 · 实际 %.0f 组/秒" % [rolls,inspected,"暂无" if best< -8 else "%+d" % best,elapsed,int(filter.get("rate",rate.value)),actual]
func update_status() -> void:status.text=summary()+"\n筛选中；停止或 Esc 可随时结束。"
func _process(delta: float) -> void:
	if not running:return
	if not visible or not world.paused_input or world.battle_view.visible or world.area_transition_busy or int(world.data.map_id)!=region_map or world.cell!=region_cell:
		stop_hunt("场景状态变化，筛选已停止。");return
	elapsed=(Time.get_ticks_usec()-started_usec)/1000000.0
	# Discard old backlog after a stall; never catch up with an unbounded burst.
	credit=minf(credit+delta*float(filter.rate),maxf(1.0,float(filter.rate)*MAX_BACKLOG_SECONDS))
	var until:=Time.get_ticks_usec()+FRAME_BUDGET_USEC
	while running and credit>=1 and Time.get_ticks_usec()<until:
		credit-=1;scan_once()
	elapsed=(Time.get_ticks_usec()-started_usec)/1000000.0
	if running:update_status()
func scan_once() -> void:
	if not running:return
	rolls+=1
	var troop: Dictionary=hunt_catalog.roll(region_map,region_cell,world.encounter_rng)
	if troop.is_empty():
		stop_hunt("原版遇敌数据或条件不完整，已停止；没有替换敌群。");return
	for i in range(troop.enemies.size()):
		var actor: Dictionary=troop.enemies[i]
		if not actor.get("can_capture",false):continue
		if not int(actor.template_id) in filter.usable:continue
		if int(filter.template)>=0 and int(actor.template_id)!=int(filter.template):continue
		if filter.level_one and int(actor.level)!=1:continue
		inspected+=1
		var quality: Dictionary=Rules.quality(actor,world.encounter_catalog.data)
		if quality.valid:best=maxi(best,int(quality.total_offset))
		if Rules.matches(actor,int(filter.template),bool(filter.level_one),int(filter.total),filter.offsets,world.encounter_catalog.data):
			last_hit={"actor":actor.duplicate(true),"index":i,"quality":quality,"troop":troop.duplicate(true)}
			stop_hunt("找到达标个体：%s Lv.%d，总成长档 %+d。" % [actor.name,actor.level,quality.total_offset])
			if not world.battle_view.can_render_troop(troop.enemies):
				status.text+="\n敌群原版素材不可用，保留本次结果并停止，未进入战斗。";return
			var config: Dictionary=world.session.start_wild_battle_config(troop)
			if config.is_empty():status.text+="\n战斗校验未通过，已停止。";return
			hide();world.paused_input=false
			world.open_battle_config(config)
			world.battle_view.player_target=i
			world.battle_view.mark_hunt_target(i)
			world.battle_view.report.text="发现 %s Lv.%d · 成长档 %+d · 请手动捕捉" % [actor.name,actor.level,quality.total_offset]
			world.message.text="极品筛选：%s，总成长档 %+d，已遇敌 %d 组。" % [actor.name,quality.total_offset,rolls]
			if is_instance_valid(world.pet_workflow) and world.pet_workflow.phase=="hunt":world.pet_workflow.matched(i,actor)
			elif auto_capture.button_pressed:world.training_helper.start_capture_battle(i)
			return
	if rolls>=int(filter.limit):stop_hunt("达到本轮遇敌上限，已暂停；可以再次开始。")
