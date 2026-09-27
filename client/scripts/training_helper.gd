extends Control
## Opt-in single-player automation; uses the same battle authority and settlement.
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
var settings: Dictionary={"speed":8.0,"xp":10,"compact":true,"hp":10,"level":120,"limit":1000}
var origin_map: int
var origin_cell: Vector2i
var initial_level:=1
var stop_reason:=""
var starting_ride:=-1
var stop_button: Button

func configure(owner: Node) -> void:world=owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=500
	panel=Panel.new();panel.position=Vector2(180,180);panel.size=Vector2(920,430)
	panel.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")));add_child(panel)
	label_at(panel,"轻松助手 · 自动练级",Vector2(24,18),24)
	label_at(panel,"原地遇敌 → 人宠自动攻击 → 正常结算 → 下一场。按原表生成，不赠送额外物品。",Vector2(24,60),16)
	label_at(panel,"战斗播放速度",Vector2(24,116),17)
	speed=options(["1×","2×","4×","8×"],Vector2(180,106))
	label_at(panel,"经验倍率",Vector2(420,116),17)
	multiplier=options(["1× 原版","2×","10×","100×"],Vector2(555,106))
	compact=CheckBox.new();compact.text="地图内简略战斗（不切换画面，只显示战况）";compact.position=Vector2(24,164);panel.add_child(compact)
	label_at(panel,"低于此血量停机 %",Vector2(24,223),17);hp_floor=number(Vector2(230,213),1,100,10)
	label_at(panel,"角色等级（0不限）",Vector2(430,223),16);target_level=number(Vector2(610,213),0,120,120)
	label_at(panel,"最多战斗场次",Vector2(24,273),17);battle_limit=number(Vector2(230,263),1,100000,1000)
	label_at(panel,"保护玩家、出战宠与坐骑；不会自动补血。中途停止可接手战斗。",Vector2(24,318),16)
	var start: Button=world.button("开始自动练级",start_training);start.position=Vector2(24,365);panel.add_child(start)
	var apply: Button=world.button("应用倍率并关闭",func():apply_settings();close_menu());apply.position=Vector2(260,365);panel.add_child(apply)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(730,365);panel.add_child(close)
	progress=Panel.new();progress.position=Vector2(100,600);progress.size=Vector2(1080,145)
	progress.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")));add_child(progress)
	status=label_at(progress,"",Vector2(18,12),18);status.size=Vector2(840,42);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result=label_at(progress,"",Vector2(18,60),16);result.size=Vector2(840,76);result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	stop_button=world.button("停止 / 接手",func():stop_training("已手动停止"));stop_button.position=Vector2(900,20);progress.add_child(stop_button)
	# Fresh UI defaults are opt-in; only Apply / Start changes live multipliers.
	settings.merge(world.training_settings,true)
	speed.select([1.0,2.0,4.0,8.0].find(float(settings.speed)))
	multiplier.select([1,2,10,100].find(int(settings.xp)))
	compact.button_pressed=settings.compact;hp_floor.value=settings.hp;target_level.value=settings.level;battle_limit.value=settings.limit
	progress.hide();hide()
func label_at(parent: Control,value: String,point: Vector2,font_size: int) -> Label:
	var node: Label=world.text(value,font_size);node.position=point;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(node);return node
func options(values: Array,point: Vector2) -> OptionButton:
	var node:=OptionButton.new();node.position=point;node.size=Vector2(180,38)
	for value in values:node.add_item(value)
	panel.add_child(node);return node
func number(point: Vector2,lo: int,hi: int,value: int) -> SpinBox:
	var node:=SpinBox.new();node.position=point;node.size=Vector2(135,36);node.min_value=lo;node.max_value=hi;node.value=value;panel.add_child(node);return node
func open_menu() -> void:
	if visible:return
	if world.paused_input or world.moving or world.area_transition_busy:return
	world.clear_input();world.paused_input=true
	if is_instance_valid(world.travel_router):world.travel_router.cancel("打开自动练级设置。")
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show();panel.show();progress.hide()
func close_menu() -> void:
	if running:stop_training("已手动停止");return
	hide();world.paused_input=false;world.clear_input()
func apply_settings() -> void:
	settings={"speed":[1.0,2.0,4.0,8.0][speed.selected],"xp":[1,2,10,100][multiplier.selected],"compact":compact.button_pressed,"hp":int(hp_floor.value),"level":int(target_level.value),"limit":int(battle_limit.value)}
	world.training_settings=settings.duplicate(true)
	world.battle_view.playback_speed=float(settings.speed)
	world.session.experience_multiplier=int(settings.xp)
func start_training() -> void:
	apply_settings()
	if not world.world_catalog.field(int(world.data.map_id)):
		world.message.text="请先到野外再开始自动练级。";panel.hide();progress.show();result.text="请先到野外再开始自动练级。";return
	origin_map=int(world.data.map_id);origin_cell=world.cell
	initial_level=int(world.session.snapshot().player.level)
	battles=0;skipped=0;unavailable_streak=0;earned_xp=0;earned_pet_xp=0;turns=0;cooldown=0;stop_reason="";starting_ride=-1
	panel.hide();progress.show();running=true
	update_status()
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
	running=false;stop_reason=reason
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
func record_result(state: Dictionary) -> void:
	earned_xp+=int(state.get("xp",0))
	for amount in state.get("pet_reward_xp",[]):earned_pet_xp+=int(amount)
func update_status() -> void:
	var profile: Dictionary=world.session.snapshot()
	status.text="自动练级 · %d 场 · Lv.%d → %d · 经验 %d× · 播放 %d×"%[battles,initial_level,profile.player.level,settings.xp,settings.speed]
	if world.session.clone_squad_enabled:status.text+=" · 五人镜像队"
	status.text+=" · 获得经验 %d（宠物 %d） · 缺素材跳过 %d 组"%[earned_xp,earned_pet_xp,skipped]
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_menu();get_viewport().set_input_as_handled()
func _process(delta: float) -> void:
	if not running:return
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
			return
		var reason:=health_reason(state)
		if not reason.is_empty():stop_training(reason);return
		if turns>=200:stop_training("单场超过200回合，请手动处理");return
		var target:=-1
		for i in range(state.enemies.size()):
			if int(state.enemies[i].hp)>0 and not state.enemies[i].get("captured",false):
				target=i;break
		if target<0:stop_training("找不到可攻击目标");return
		world.battle_view.player_target=target;world.battle_view.pet_target=target
		world.battle_session.set_pet_command("attack")
		world.battle_action("attack")
		turns+=1
		var next: Dictionary=world.battle_session.snapshot()
		result.text="第 %d 回合 · 体力 %d/%d\n%s"%[turns,next.player_hp,next.player_max_hp," / ".join(next.events)]
		update_status();return
	var p: Dictionary=world.session.snapshot()
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
	starting_ride=int(world.battle_session.snapshot().get("ride_pet",-1))
	world.paused_input=true
