extends Control
## Opt-in single-player automation; uses the same battle authority and settlement.
const Policy=preload("res://scripts/battle_auto_policy.gd")
var preset: OptionButton
var capture_hp: SpinBox
var capture_pet: OptionButton
var capture_pet_max_level: SpinBox
var single_battle:=false
var capture_target:=-1
var training_pet_id:=""
var training_pet_level:=120
var finish_after_capture:=false
var clone_override_active:=false
var previous_clone_enabled:=false
var world: Node
var panel: Panel
var progress: Panel
var status: Label
var result: Label
var speed: OptionButton
var multiplier: OptionButton
var compact: CheckBox
var hp_floor: SpinBox
var target_level: SpinBox
var level_explicit:=false
var battle_limit: SpinBox
var running:=false
var compact_active:=false
var battles:=0
var skipped:=0
var unavailable_streak:=0
var earned_xp:=0
var earned_pet_xp:=0
var turns:=0
var cooldown:=0.0
const COMPACT_BUDGET_USEC := 12000
var settings: Dictionary={"speed":8.0,"xp":10,"compact":true,"hp":10,"level":120,"limit":1000,"preset":"attack","capture_hp":100,"capture_pet":-1,"capture_pet_max_level":10}
var origin_map: int
var origin_cell: Vector2i
var initial_level:=1
var stop_reason:=""
var starting_ride:=-1
var start_button: Button
var target_note: Label
var stop_button: Button

func configure(owner: Node) -> void:world=owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=500
	panel=Panel.new();panel.position=Vector2(180,70);panel.size=Vector2(920,640)
	panel.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")));add_child(panel)
	label_at(panel,"轻松助手 · 自动战斗 / 练级",Vector2(24,18),24)
	label_at(panel,"普通攻击 / 抓宠 / 带宠升级；使用原战斗规则，不保证抓宠攻击不会击倒目标。",Vector2(24,60),16)
	label_at(panel,"战斗播放速度",Vector2(24,116),17)
	speed=options(["1×","2×","4×","8×"],Vector2(180,106))
	label_at(panel,"经验倍率",Vector2(420,116),17)
	multiplier=options(["1× 原版","2×","10×","100×"],Vector2(555,106))
	compact=CheckBox.new();compact.text="地图内简略战斗（不切换画面，只显示战况）";compact.position=Vector2(24,164);panel.add_child(compact)
	label_at(panel,"低于此血量停机 %",Vector2(24,223),17);hp_floor=number(Vector2(230,213),1,100,10)
	label_at(panel,"角色等级（0不限）",Vector2(430,223),16);target_level=number(Vector2(610,213),0,120,120)
	label_at(panel,"最多战斗场次",Vector2(24,273),17);battle_limit=number(Vector2(230,263),1,100000,1000)
	label_at(panel,"保护玩家、出战宠与坐骑；不会自动补血。中途停止可接手战斗。",Vector2(24,318),16)
	start_button=world.button("原地连续遇敌",start_training);start_button.position=Vector2(24,570);panel.add_child(start_button)
	var apply: Button=world.button("应用设置并关闭",func():apply_settings();close_menu());apply.position=Vector2(260,570);panel.add_child(apply)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(730,570);panel.add_child(close)
	label_at(panel,"战斗预设",Vector2(24,366),17)
	preset=options(["普通攻击","抓宠（分身全防御）","带宠升级（镜像助战）"],Vector2(180,356))
	capture_hp=number(Vector2(610,356),1,100,100)
	capture_pet=options(["自动最低等级"],Vector2(180,406));capture_pet.set_item_id(0,-1)
	capture_pet_max_level=number(Vector2(610,406),1,120,10)
	label_at(panel,"抓宠血量线与削血宠设置统一在「自动抓极品 → 抓宠设置」。",Vector2(24,416),16)
	target_note=label_at(panel,"抓宠锁定目标；带宠升级需遇敌前启用。攻击或反击仍可能击倒目标。",Vector2(24,490),16)
	progress=Panel.new();progress.position=Vector2(100,600);progress.size=Vector2(1080,145)
	progress.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")));add_child(progress)
	status=label_at(progress,"",Vector2(18,12),18);status.size=Vector2(840,42);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result=label_at(progress,"",Vector2(18,60),16);result.size=Vector2(840,76);result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	stop_button=world.button("停止 / 接手",func():stop_training("已手动停止"));stop_button.position=Vector2(900,20);progress.add_child(stop_button)
	# Fresh UI defaults are opt-in; only Apply / Start changes live multipliers.
	settings.merge(world.training_settings,true)
	level_explicit=bool(world.training_settings.get("level_explicit",world.training_settings.has("level") and int(world.training_settings.level)!=120))
	speed.select([1.0,2.0,4.0,8.0].find(float(settings.speed)))
	multiplier.select([1,2,10,100].find(int(settings.xp)))
	compact.button_pressed=settings.compact;hp_floor.value=settings.hp;target_level.value=settings.level;battle_limit.value=settings.limit
	preset.select(["attack","capture","train_pet"].find(str(settings.preset)))
	capture_hp.value=settings.capture_hp;capture_pet_max_level.value=settings.capture_pet_max_level
	_refresh_pet_choices()
	_sync_default_level()
	target_level.value_changed.connect(func(_value):level_explicit=true)
	target_level.get_line_edit().text_submitted.connect(func(_text):level_explicit=true)
	world.pet_hunt_menu.install_capture_controls(capture_hp,capture_pet,capture_pet_max_level)
	capture_hp.value_changed.connect(func(_value):save_capture_settings())
	capture_pet.item_selected.connect(func(_index):save_capture_settings())
	capture_pet_max_level.value_changed.connect(func(_value):save_capture_settings())
	progress.hide();hide()
func label_at(parent: Control,value: String,point: Vector2,font_size: int) -> Label:
	var node: Label=world.text(value,font_size);node.position=point;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(node);return node
func options(values: Array,point: Vector2) -> OptionButton:
	var node:=OptionButton.new();node.position=point;node.size=Vector2(180,38)
	for value in values:node.add_item(value)
	panel.add_child(node);return node
func number(point: Vector2,lo: int,hi: int,value: int) -> SpinBox:
	var node:=SpinBox.new();node.position=point;node.size=Vector2(135,36);node.min_value=lo;node.max_value=hi;node.value=value;panel.add_child(node);return node
func _sync_default_level() -> void:
	if level_explicit:return
	settings.level=0 if int(world.session.snapshot().player.level)>=120 else 120
	target_level.set_value_no_signal(settings.level)

func _refresh_pet_choices() -> void:
	capture_pet.clear();capture_pet.add_item("自动最低等级");capture_pet.set_item_id(0,-1);capture_pet.set_item_metadata(0,"")
	var pets: Array=world.session.snapshot().pets
	for i in range(pets.size()):
		capture_pet.add_item("%d. %s Lv.%d"%[i+1,pets[i].name,pets[i].level],i)
		capture_pet.set_item_metadata(i+1,str(pets[i].get("pet_id","")))
	var selected:=capture_pet.get_item_index(int(settings.get("capture_pet",-1)))
	if not str(settings.get("capture_pet_id","")).is_empty():
		selected=-1
		for i in range(pets.size()):
			if str(pets[i].get("pet_id",""))==str(settings.capture_pet_id):selected=capture_pet.get_item_index(i)
	if selected<0:
		capture_pet.add_item("指定宠物不在随身队伍",-2)
		capture_pet.set_item_metadata(capture_pet.item_count-1,str(settings.get("capture_pet_id","")))
		selected=capture_pet.item_count-1
	capture_pet.select(selected)
func open_battle_menu() -> void:
	if visible or not world.battle_view.visible or world.battle_view.is_animating() or not world.battle_session.snapshot().active:return
	capture_target=int(world.battle_view.player_target)
	start_button.text="本场自动战斗"
	var enemies: Array=world.battle_session.snapshot().enemies
	target_note.text="抓宠锁定：%s（敌人 %d）；攻击或反击仍可能击倒目标。"%[enemies[capture_target].name,capture_target+1] if capture_target>=0 and capture_target<enemies.size() else "请先在战斗中选择捕捉目标。"
	_refresh_pet_choices()
	world.paused_input=true;get_parent().move_child(self,get_parent().get_child_count()-1)
	show();panel.show();progress.hide()
func start_capture_battle(target: int, finish_battle: bool = false) -> void:
	if not world.battle_session.snapshot().active:return
	capture_target=target;preset.select(1)
	show();start_training()
	finish_after_capture=finish_battle
func open_menu() -> void:
	if visible:return
	if world.paused_input or world.moving or world.area_transition_busy:return
	_sync_default_level()
	start_button.text="原地连续遇敌"
	target_note.text="抓宠锁定目标；带宠升级需遇敌前启用。攻击或反击仍可能击倒目标。"
	_refresh_pet_choices()
	world.clear_input();world.paused_input=true
	if is_instance_valid(world.travel_router):world.travel_router.cancel("打开自动练级设置。")
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show();panel.show();progress.hide()
func close_menu() -> void:
	if running:stop_training("已手动停止");return
	hide();world.paused_input=world.battle_view.visible;world.clear_input()
func apply_settings() -> void:
	for input in [capture_hp,capture_pet_max_level,hp_floor,target_level,battle_limit]:
		if input.get_line_edit().has_focus():input.apply()
	settings={"speed":[1.0,2.0,4.0,8.0][speed.selected],"xp":[1,2,10,100][multiplier.selected],"compact":compact.button_pressed,"hp":int(hp_floor.value),"level":int(target_level.value),"limit":int(battle_limit.value),"level_explicit":level_explicit,"preset":["attack","capture","train_pet"][preset.selected],"capture_hp":int(capture_hp.value),"capture_pet":capture_pet.get_selected_id(),"capture_pet_max_level":int(capture_pet_max_level.value)}
	settings.capture_pet_id=str(capture_pet.get_item_metadata(capture_pet.selected)) if capture_pet.selected>=0 and capture_pet.get_item_metadata(capture_pet.selected)!=null else ""
	world.training_settings=settings.duplicate(true)
	world.battle_view.playback_speed=float(settings.speed)
	world.session.experience_multiplier=int(settings.xp)
func start_training() -> void:
	training_pet_id="";finish_after_capture=false
	apply_settings()
	single_battle=bool(world.battle_session.snapshot().active)
	if not single_battle and not world.world_catalog.field(int(world.data.map_id)):
		world.message.text="请先到野外再开始自动练级。";panel.hide();progress.show();result.text="请先到野外再开始自动练级。";return
	origin_map=int(world.data.map_id);origin_cell=world.cell
	initial_level=int(world.session.snapshot().player.level)
	battles=0;skipped=0;unavailable_streak=0;earned_xp=0;earned_pet_xp=0;turns=0;cooldown=0;stop_reason="";starting_ride=-1
	if str(settings.preset)=="train_pet":
		if single_battle and world.battle_session.snapshot().get("allies",[]).is_empty():
			world.message.text="带宠升级请在遇敌前开启，以生成完整镜像队。";close_menu();return
		acquire_clone_override()
	if single_battle and str(settings.preset)=="capture" and capture_target<0:capture_target=int(world.battle_view.player_target)
	world.battle_session.set_capture_assist(str(settings.preset)=="capture")
	panel.hide();progress.show();running=true
	update_status()
func start_pet_training(pet_id: String, target_level_value: int = 120) -> bool:
	if running or world.battle_session.snapshot().active:return false
	var profile: Dictionary=world.session.snapshot()
	var chosen:=-1
	for i in range(profile.pets.size()):
		if str(profile.pets[i].get("pet_id",""))==pet_id:chosen=i;break
	if chosen<0:stop_reason="目标宠物不在随身队伍";return false
	if int(profile.get("ride_pet",-1))==chosen:stop_reason="目标宠物正在骑乘，请先下骑";return false
	if not world.session.select_pet(chosen):stop_reason="无法让目标宠物出战";return false
	preset.select(2);speed.select(3);multiplier.select(2);compact.button_pressed=true
	target_level.value=0;level_explicit=true
	show();start_training()
	if not running:return false
	training_pet_id=pet_id;training_pet_level=clampi(target_level_value,1,120)
	return true

func health_reason(state: Dictionary) -> String:
	if float(state.player_hp)/maxf(1,float(state.player_max_hp))*100<=int(settings.hp):return "玩家体力达到停机线"
	for index in [int(state.get("active_pet",-1)),int(state.get("ride_pet",-1)),starting_ride]:
		if index>=0 and index<state.get("pets",[]).size():
			var pet: Dictionary=state.pets[index]
			if float(pet.hp)/maxf(1,float(pet.max_hp))*100<=int(settings.hp):return "%s 体力达到停机线"%str(pet.get("name","宠物"))
	return ""
func profile_health_reason() -> String:
	var p: Dictionary=world.session.snapshot()
	return health_reason({"player_hp":p.player.hp,"player_max_hp":p.player.max_hp,"pets":p.pets,"active_pet":p.active_pet,"ride_pet":p.get("ride_pet",-1)})
func stop_training(reason: String) -> void:
	release_clone_override()
	running=false;stop_reason=reason
	world.battle_session.set_capture_assist(false)
	if compact_active and not world.battle_session.snapshot().active:
		battles+=1
		world.return_from_battle()
		if is_queued_for_deletion():return
	if compact_active:
		compact_active=false
		world.battle_view.open_battle(world.battle_session.snapshot())
		world.set_music(load("res://assets/legacy/battle/audio/sabgm_b0.wav"))
	world.paused_input=world.battle_view.visible
	world.clear_input();hide()
	world.last_adventure_message="自动练级：%s · 已完成 %d 场。"%[reason,battles]
	world.message.text=world.last_adventure_message
	if not is_queued_for_deletion() and is_instance_valid(world.battle_view) and world.battle_view.visible and world.battle_session.snapshot().active:
		world.battle_view.report.text="自动抓宠／战斗已暂停："+reason+"；可手动接手。"
func record_result(state: Dictionary) -> void:
	earned_xp+=int(state.get("xp",0))
	for amount in state.get("pet_reward_xp",[]):earned_pet_xp+=int(amount)
func update_status() -> void:
	var profile: Dictionary=world.session.snapshot()
	status.text="自动练级 · %d 场 · Lv.%d → %d · 经验 %d× · 播放 %d×"%[battles,initial_level,profile.player.level,settings.xp,settings.speed]
	var workflow=world.get("pet_workflow")
	if is_instance_valid(workflow) and workflow.active():status.text="找宠流程 · "+("抓宠 · " if str(settings.preset)=="capture" else "练宠 · ")+status.text
	if world.session.clone_squad_enabled:status.text+=" · 五人镜像队"
	status.text+=" · 获得经验 %d（宠物 %d） · 缺素材跳过 %d 组"%[earned_xp,earned_pet_xp,skipped]
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_menu();get_viewport().set_input_as_handled()
func _process(delta: float) -> void:
	if not running:return
	# Compact battles have nothing to watch: run steps back to back within a frame budget.
	if bool(settings.compact) and not world.battle_view.visible:
		var until:=Time.get_ticks_usec()+COMPACT_BUDGET_USEC
		while running and not is_queued_for_deletion() and not world.battle_view.visible and Time.get_ticks_usec()<until:advance()
		return
	cooldown-=delta
	if cooldown>0:return
	cooldown=0.25/float(settings.speed)
	advance()
func advance() -> void:
	if not running:return
	if int(world.data.map_id)!=origin_map or world.cell!=origin_cell or world.area_transition_busy:
		stop_training("位置发生变化");return
	var state: Dictionary=world.battle_session.snapshot()
	if compact_active or world.battle_view.visible:
		if not compact_active and world.battle_view.is_animating():return
		if not state.active:
			battles+=1;turns=0
			var outcome: String=state.outcome
			world.return_from_battle()
			if outcome=="defeat":return # return rebuilds the map and this control.
			world.paused_input=true;update_status()
			if outcome not in ["win","captured"]:stop_training("战斗未获胜");return
			if single_battle:stop_training("本场自动战斗已完成");return
			return
		var reason:=health_reason(state)
		if not reason.is_empty():stop_training(reason);return
		if turns>=200:stop_training("单场超过200回合，请手动处理");return
		if str(settings.preset)=="capture" and world.session.snapshot().pets.size()>=world.session.PET_CAPACITY:
			stop_training("宠物栏已满，请先腾出位置");return
		if str(settings.preset)=="capture" and finish_after_capture and capture_target>=0 and capture_target<state.enemies.size() and state.enemies[capture_target].get("captured",false):
			settings.preset="attack"
		var decision: Dictionary=Policy.decide(state,settings,capture_target)
		if decision.has("stop"):stop_training(str(decision.stop));return
		world.battle_session.set_capture_assist(str(settings.preset)=="capture")
		world.battle_view.player_target=int(decision.target);world.battle_view.pet_target=int(decision.target)
		world.battle_view.switch_pet_index=int(decision.get("switch",-2))
		world.battle_session.set_pet_command(str(decision.pet))
		world.battle_action(str(decision.action))
		turns+=1
		var next: Dictionary=world.battle_session.snapshot()
		result.text="第 %d 回合 · 体力 %d/%d\n%s"%[turns,next.player_hp,next.player_max_hp," / ".join(next.events)]
		update_status();return
	if world.session.heal_carried_pets():
		world.checkpoint()
	var p: Dictionary=world.session.snapshot()
	if not training_pet_id.is_empty():
		var selected:=-1
		for i in range(p.pets.size()):
			if str(p.pets[i].get("pet_id",""))==training_pet_id:selected=i;break
		if selected<0:stop_training("目标宠物不在随身队伍");return
		if selected!=int(p.active_pet):stop_training("目标宠物不再出战");return
		if int(p.pets[selected].level)>=training_pet_level:stop_training("目标宠物已达到等级目标");return
	if int(settings.level)>0 and int(p.player.level)>=int(settings.level):stop_training("已达到目标等级");return
	if battles>=int(settings.limit):stop_training("已达到战斗场次上限");return
	var reason:=profile_health_reason()
	if not reason.is_empty():stop_training(reason);return
	world.paused_input=false
	compact_active=bool(settings.compact)
	if not world.begin_wild_battle():
		compact_active=false
		if world.last_encounter_error=="art":
			skipped+=1;unavailable_streak+=1;world.paused_input=true
			result.text="该敌群原版素材不可用，已跳过，无奖励。";update_status()
			if unavailable_streak>=100:stop_training("连续100组缺素材，请更换区域")
			return
		stop_training("当前位置遇敌数据或条件不可用，请换个位置");return
	unavailable_streak=0
	var opened: Dictionary=world.battle_session.snapshot()
	starting_ride=int(opened.get("ride_pet",-1))
	capture_target=-1
	if str(settings.preset)=="capture":
		for i in range(opened.enemies.size()):
			if opened.enemies[i].get("can_capture",false) and int(opened.enemies[i].hp)>0:capture_target=i;break
	world.battle_session.set_capture_assist(str(settings.preset)=="capture")
	world.paused_input=true

func save_capture_settings() -> void:
	settings.capture_hp=int(capture_hp.value)
	settings.capture_pet=capture_pet.get_selected_id()
	settings.capture_pet_max_level=int(capture_pet_max_level.value)
	settings.capture_pet_id=str(capture_pet.get_item_metadata(capture_pet.selected)) if capture_pet.selected>=0 and capture_pet.get_item_metadata(capture_pet.selected)!=null else ""
	for key in ["capture_hp","capture_pet","capture_pet_max_level","capture_pet_id"]:world.training_settings[key]=settings[key]

func acquire_clone_override()->void:
	if not clone_override_active:
		previous_clone_enabled=world.session.clone_squad_enabled
		clone_override_active=true
	world.set_clone_squad_enabled(true)

func release_clone_override()->void:
	if not clone_override_active:return
	clone_override_active=false
	world.set_clone_squad_enabled(previous_clone_enabled)
