extends Control
## Opt-in single-player automation settings and progress. The battle loop runs
## in the backend (res://server/automation.gd). Settings belong to the
## character profile: the controls show world.automation_settings(), Apply /
## Start write them back, and changes from another device update them. Only the
## battle playback speed is this device's own (viewer.cfg).
const AutomationSettings = preload("res://scripts/automation_settings.gd")
var preset: OptionButton
var capture_hp: SpinBox
var capture_pet: OptionButton
var capture_fallback_attempts: SpinBox
var capture_fallback_rate: SpinBox
var capture_fallback_hp: SpinBox
var capture_pet_max_level: SpinBox
var world: Node
var panel: Panel
var progress: Panel
var status: Label
var result: Label
var speed: OptionButton
var multiplier: OptionButton
var compact: CheckBox
## 用精灵补血 (training.spirit).
var spirit: CheckBox
## 练级保护 (training.protect): fallen pets still earn experience in runs.
var protect: CheckBox
## 全体补血 threshold in percent (training.side_heal, 0 off).
var side_heal: SpinBox

var hp_floor: SpinBox
var target_level: SpinBox
var level_explicit:=false
var battle_limit: SpinBox
## The running backend's settings, else the choices in these controls.
var settings: Dictionary:
	get:return _status().get("settings",{}).duplicate(true) if running else current_settings()
## Effective profile settings last shown in the controls; only values that
## change from these are rewritten when the profile changes.
var _loaded: Dictionary = {}
var _loading := false
## Apply was pressed: the training controls go into the next settings patch.
var _training_applied := false
var _capture_choice:=-1
## The locked target: the backend's while running, else this UI's choice.
var capture_target: int:
	get:return int(_status().get("capture_target",-1)) if running else _capture_choice
	set(value):_capture_choice=value
var start_button: Button
var target_note: Label
var stop_button: Button
var minimize_button: Button
## Collapsed to a progress bar while the run continues (see automation_chip.gd).
var minimized := false
var chip: Panel

func _status() -> Dictionary:
	return world.state.automation if is_instance_valid(world) else {}

var running: bool:
	get:return bool(_status().get("running",false))
var compact_active: bool:
	get:return bool(_status().get("compact",false))
var single_battle: bool:
	get:return bool(_status().get("single_battle",false))
var battles: int:
	get:return int(_status().get("battles",0))
var skipped: int:
	get:return int(_status().get("skipped",0))
var earned_xp: int:
	get:return int(_status().get("earned_xp",0))
var earned_pet_xp: int:
	get:return int(_status().get("earned_pet_xp",0))
var stop_reason: String:
	get:return str(_status().get("stop_reason",""))
var clone_override_active: bool:
	get:return bool(_status().get("clone_override",false))

## In-process test seam: write one backend runner field directly.
func _seam(fields: Dictionary) -> void:
	world.link.request({"type":"auto","name":"set","fields":fields})

var starting_ride: int:
	get:return int(world.backend.automation.starting_ride)
	set(value):_seam({"starting_ride":value})

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
	spirit=CheckBox.new();spirit.name="SpiritHeal";spirit.text="用精灵补血";spirit.position=Vector2(560,164);panel.add_child(spirit)
	protect=CheckBox.new();protect.name="TrainingProtect";protect.text="练级保护";protect.position=Vector2(720,164);panel.add_child(protect)
	protect.tooltip_text="非原版助手（默认开）：自动练级、自动抓宠和后台搜宠里，随身宠物倒下也照样分到经验、不掉忠诚，每场之间随身宠物回满血（倒下的也救回）。低等级宠物在高等级区也能练。手动战斗仍按原版。"
	spirit.tooltip_text="到停机线时先用身上装备的补血精灵（治愈／滋润／恩惠，队伍里倒下的队友用复活精灵），气力不够再喝回复药或停机。气力只在村里休息时恢复。"
	label_at(panel,"低于此血量停机 %",Vector2(24,223),17);hp_floor=number(Vector2(230,213),1,100,10)
	label_at(panel,"角色等级（0不限）",Vector2(430,223),16);target_level=number(Vector2(610,213),0,120,120)
	label_at(panel,"最多战斗场次",Vector2(24,273),17);battle_limit=number(Vector2(230,263),1,100000,1000)
	label_at(panel,"全体补血：有人体力低于 %",Vector2(400,273),16);side_heal=number(Vector2(610,263),0,100,50)
	side_heal.name="SideHeal"
	side_heal.tooltip_text="全体补血：我方有人（自己、宠物、坐骑，组队时每个队友和他们的宠物）体力低于这个百分比时，用身上的恩惠的精灵给全体补血；正好等于不算。0 关闭。没穿恩惠时照旧：到停机线再用治愈／滋润或喝药。需要打开「用精灵补血」。"
	label_at(panel,"保护玩家、出战宠与坐骑：到停机线先用补血精灵（有气力时），否则停机。中途停止可接手战斗。",Vector2(24,318),16)
	start_button=world.button("原地连续遇敌",start_training);start_button.position=Vector2(24,570);panel.add_child(start_button)
	var apply: Button=world.button("应用设置并关闭",func():apply_settings();close_menu());apply.position=Vector2(260,570);panel.add_child(apply)
	var close: Button=world.button("关闭 · Esc",close_menu);close.position=Vector2(730,570);panel.add_child(close)
	label_at(panel,"战斗预设",Vector2(24,366),17)
	preset=options(["普通攻击","抓宠（分身全防御）","带宠升级（镜像助战）"],Vector2(180,356))
	capture_hp=number(Vector2(610,356),1,100,100)
	capture_pet=options(["自动最低等级"],Vector2(180,406));capture_pet.set_item_id(0,-1)
	capture_pet_max_level=number(Vector2(610,406),1,120,10)
	capture_fallback_attempts=number(Vector2(230,289),1,30,5)
	capture_fallback_rate=number(Vector2(230,339),0,98,20)
	capture_fallback_hp=number(Vector2(230,389),1,99,50)
	label_at(panel,"抓宠血量线与削血宠设置统一在「自动抓极品 → 抓宠设置」。",Vector2(24,416),16)
	target_note=label_at(panel,"抓宠锁定目标；带宠升级需遇敌前启用。攻击或反击仍可能击倒目标。",Vector2(24,490),16)
	progress=Panel.new();progress.position=Vector2(100,600);progress.size=Vector2(1080,145)
	progress.add_theme_stylebox_override("panel",world.box(Color("20292f"),Color("b29b65")));add_child(progress)
	status=label_at(progress,"",Vector2(18,12),18);status.size=Vector2(840,42);status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	result=label_at(progress,"",Vector2(18,60),16);result.size=Vector2(840,76);result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	stop_button=world.button("停止 / 接手",func():stop_training("已手动停止"));stop_button.position=Vector2(900,20);progress.add_child(stop_button)
	minimize_button=world.button("最小化",minimize);minimize_button.name="MinimizeTraining";minimize_button.tooltip_text="收起为右下角进度条；自动战斗继续，可同时查看宠物与仓库"
	minimize_button.position=Vector2(900,80);progress.add_child(minimize_button)
	# Fresh UI defaults are opt-in; only Apply / Start changes live multipliers.
	var device_speed: float=world.battle_speed if world.battle_speed>0 else float(AutomationSettings.device_default("battle_speed",8))
	speed.select(maxi(0,[1.0,2.0,4.0,8.0].find(device_speed)))
	load_settings()
	target_level.value_changed.connect(func(_value):if not _loading:level_explicit=true)
	target_level.get_line_edit().text_submitted.connect(func(_text):level_explicit=true)
	world.pet_hunt_menu.install_capture_controls(capture_hp,capture_pet,capture_pet_max_level)
	world.pet_hunt_menu.install_fallback_controls(capture_fallback_attempts,capture_fallback_rate,capture_fallback_hp)
	for input in [capture_fallback_attempts,capture_fallback_rate,capture_fallback_hp]:input.value_changed.connect(func(_value):save_capture_settings(false))
	capture_hp.value_changed.connect(func(_value):save_capture_settings(false))
	capture_pet.item_selected.connect(func(_index):save_capture_settings(true))
	capture_pet_max_level.value_changed.connect(func(_value):save_capture_settings(false))
	progress.hide();hide()
func label_at(parent: Control,value: String,point: Vector2,font_size: int) -> Label:
	var node: Label=world.text(value,font_size);node.position=point;node.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(node);return node
func options(values: Array,point: Vector2) -> OptionButton:
	var node:=OptionButton.new();node.position=point;node.size=Vector2(180,38)
	for value in values:node.add_item(value)
	panel.add_child(node);return node
func number(point: Vector2,lo: int,hi: int,value: int) -> SpinBox:
	var node:=SpinBox.new();node.position=point;node.size=Vector2(135,36);node.min_value=lo;node.max_value=hi;node.value=value;panel.add_child(node)
	# Once the player stops typing, show any update that waited for them.
	node.get_line_edit().focus_exited.connect(func():call_deferred("load_settings"))
	return node
func _sync_default_level() -> void:
	if level_explicit:return
	target_level.set_value_no_signal(0 if int(world.session.snapshot().player.level)>=120 else 120)

## Shows the profile's effective settings. Only values that changed since the
## last load are rewritten, and never a number the player is typing.
func load_settings() -> void:
	var all: Dictionary=world.automation_settings()
	var training: Dictionary=all.training
	var capture: Dictionary=all.capture
	var old_training: Dictionary=_loaded.get("training",{})
	var old_capture: Dictionary=_loaded.get("capture",{})
	_loading=true
	if _changed(old_training,training,"xp"):multiplier.select(maxi(0,[1,2,10,100].find(int(training.xp))))
	if _changed(old_training,training,"compact"):compact.set_pressed_no_signal(bool(training.compact))
	if _changed(old_training,training,"spirit"):spirit.set_pressed_no_signal(bool(training.get("spirit",true)))
	if _changed(old_training,training,"protect"):protect.set_pressed_no_signal(bool(training.get("protect",true)))
	var shown:=all.duplicate(true)
	if not _sync_spin(hp_floor,old_training.get("hp"),training.hp):shown.training.hp=old_training.hp
	if not _sync_spin(battle_limit,old_training.get("limit"),training.limit):shown.training.limit=old_training.limit
	if not _sync_spin(side_heal,old_training.get("side_heal"),int(training.get("side_heal",50))):shown.training.side_heal=old_training.side_heal
	if _changed(old_training,training,"preset"):preset.select(maxi(0,["attack","capture","train_pet"].find(str(training.preset))))
	if _changed(old_training,training,"level_explicit") or _changed(old_training,training,"level"):
		if _typing(target_level):
			for key in ["level","level_explicit"]:if old_training.has(key):shown.training[key]=old_training[key]
		else:
			level_explicit=bool(training.level_explicit)
			if level_explicit:target_level.value=int(training.level)
			else:_sync_default_level()
	if not _sync_spin(capture_hp,old_capture.get("hp"),capture.hp):shown.capture.hp=old_capture.hp
	if not _sync_spin(capture_pet_max_level,old_capture.get("pet_max_level"),capture.pet_max_level):shown.capture.pet_max_level=old_capture.pet_max_level
	for entry in [[capture_fallback_attempts,"fallback_attempts"],[capture_fallback_rate,"fallback_rate"],[capture_fallback_hp,"fallback_hp"]]:
		if not _sync_spin(entry[0],old_capture.get(entry[1]),capture[entry[1]]):shown.capture[entry[1]]=old_capture[entry[1]]
	if _changed(old_capture,capture,"pet") or _changed(old_capture,capture,"pet_id"):_refresh_pet_choices()
	_loading=false
	_loaded=shown

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

## Every choice in these controls, in the runner's flat settings shape.
func current_settings() -> Dictionary:
	var result:={"speed":[1.0,2.0,4.0,8.0][maxi(0,speed.selected)],"xp":[1,2,10,100][maxi(0,multiplier.selected)],"compact":compact.button_pressed,"spirit":spirit.button_pressed,"protect":protect.button_pressed,"side_heal":int(side_heal.value),"hp":int(hp_floor.value),"level":int(target_level.value),"limit":int(battle_limit.value),"level_explicit":level_explicit,"preset":["attack","capture","train_pet"][maxi(0,preset.selected)],"capture_hp":int(capture_hp.value),"capture_pet":capture_pet.get_selected_id(),"capture_pet_max_level":int(capture_pet_max_level.value)}
	result.capture_pet_id=_selected_pet_id()
	return result

func _selected_pet_id() -> String:
	return str(capture_pet.get_item_metadata(capture_pet.selected)) if capture_pet.selected>=0 and capture_pet.get_item_metadata(capture_pet.selected)!=null else ""

## The changes these controls make to the profile's settings (see
## game.flush_automation_settings). Capture settings always; training ones
## only after Apply / Start. An automatic level target stores no level.
func settings_patch() -> Dictionary:
	var all: Dictionary=world.automation_settings()
	var patch := {}
	var capture:=AutomationSettings.diff(all.capture,{"hp":int(capture_hp.value),"pet":capture_pet.get_selected_id(),"pet_id":_selected_pet_id(),"pet_max_level":int(capture_pet_max_level.value),"fallback_attempts":int(capture_fallback_attempts.value),"fallback_rate":int(capture_fallback_rate.value),"fallback_hp":int(capture_fallback_hp.value)})
	if not capture.is_empty():patch.capture=capture
	if _training_applied:
		_training_applied=false
		var chosen: Dictionary=current_settings()
		var wanted:={"xp":chosen.xp,"compact":chosen.compact,"spirit":chosen.spirit,"protect":chosen.protect,"side_heal":chosen.side_heal,
"hp":chosen.hp,"limit":chosen.limit,"preset":chosen.preset,"level_explicit":level_explicit}
		if level_explicit:wanted.level=chosen.level
		var training:=AutomationSettings.diff(all.training,wanted)
		if not level_explicit and world.automation_overrides().get("training",{}).has("level"):training.level=null
		if not training.is_empty():patch.training=training
	return patch

func _refresh_pet_choices() -> void:
	capture_pet.clear();capture_pet.add_item("自动最低等级");capture_pet.set_item_id(0,-1);capture_pet.set_item_metadata(0,"")
	var pets: Array=world.session.snapshot().pets
	for i in range(pets.size()):
		capture_pet.add_item("%d. %s Lv.%d"%[i+1,pets[i].name,pets[i].level],i)
		capture_pet.set_item_metadata(i+1,str(pets[i].get("pet_id","")))
	var chosen: Dictionary=world.automation_settings().capture
	var selected:=capture_pet.get_item_index(int(chosen.pet))
	if not str(chosen.pet_id).is_empty():
		selected=-1
		for i in range(pets.size()):
			if str(pets[i].get("pet_id",""))==str(chosen.pet_id):selected=capture_pet.get_item_index(i)
	if selected<0:
		capture_pet.add_item("指定宠物不在随身队伍",-2)
		capture_pet.set_item_metadata(capture_pet.item_count-1,str(chosen.pet_id))
		selected=capture_pet.item_count-1
	capture_pet.select(selected)
func open_battle_menu() -> void:
	if minimized:restore();return
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
	capture_target=target
	world.flush_automation_settings()
	world.link.request({"type":"auto_start","kind":"capture_battle","target":target,"finish_battle":finish_battle,"speed":world.playback_speed(),"map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]})
func open_menu() -> void:
	if minimized:restore();return
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
	world.flush_automation_settings()
	hide();world.release_input();world.clear_input()
## Saves these choices to the profile and applies this device's playback speed
## and the live experience multiplier.
func apply_settings() -> void:
	for input in [capture_hp,capture_pet_max_level,capture_fallback_attempts,capture_fallback_rate,capture_fallback_hp,hp_floor,target_level,battle_limit,side_heal]:
		if input.get_line_edit().has_focus():input.apply()
	var chosen: Dictionary=current_settings()
	world.set_battle_speed(float(chosen.speed))
	world.session.experience_multiplier=int(chosen.xp)
	_training_applied=true
	world.mark_settings_dirty(self)
	world.flush_automation_settings()
func start_training() -> void:
	apply_settings()
	var chosen: Dictionary=current_settings()
	var command := {"type":"auto_start","kind":"battle","speed":float(chosen.speed),"map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]}
	if world.battle_session.snapshot().active and str(chosen.preset)=="capture":
		command.capture_target=capture_target if capture_target>=0 else int(world.battle_view.player_target)
	world.link.request(command)
func start_pet_training(pet_id: String, target_level_value: int = 120) -> bool:
	if running or world.battle_session.snapshot().active:return false
	# The backend forces pet-training values for this run only (8×, 10× XP,
	# compact, mirrors); the other choices here (health floor, limit) are saved
	# and used as for any start.
	for input in [hp_floor,battle_limit]:
		if input.get_line_edit().has_focus():input.apply()
	_training_applied=true
	world.mark_settings_dirty(self)
	world.flush_automation_settings()
	var reply: Dictionary=world.link.request({"type":"auto_start","kind":"pet_train","pet_id":pet_id,"target_level":target_level_value,"speed":8.0,"map_id":int(world.data.map_id),"cell":[world.cell.x,world.cell.y]})
	return bool(reply.ok) or bool(reply.get("pending",false))

func health_reason(state: Dictionary) -> String:
	return world.backend.automation.health_reason(state) if world.link.is_local() else ""
func stop_training(reason: String) -> void:
	if running:world.link.request({"type":"auto","name":"stop_battle","reason":reason})
	else:on_event({"kind":"battle_stopped","reason":reason,"battles":battles,"takeover":false})
func record_result(_state: Dictionary) -> void:
	pass
func update_status() -> void:
	var automation := _status()
	var profile: Dictionary=world.session.snapshot()
	var used: Dictionary=automation.get("settings",settings)
	status.text="自动练级 · %d 场 · Lv.%d → %d · 经验 %d× · 播放 %d×"%[battles,int(automation.get("initial_level",profile.player.level)),profile.player.level,int(used.get("xp",1)),int(used.get("speed",1))]
	var workflow=world.get("pet_workflow")
	if is_instance_valid(workflow) and workflow.active():status.text="找宠流程 · "+("抓宠 · " if str(used.get("preset",""))=="capture" else "练宠 · ")+status.text
	if world.session.clone_squad_enabled:status.text+=" · 五人镜像队"
	status.text+=" · 获得经验 %d（宠物 %d） · 缺素材跳过 %d 组"%[earned_xp,earned_pet_xp,skipped]
	if not str(automation.get("turn_text","")).is_empty():result.text=str(automation.turn_text)

## Backend status: show progress while running and mirror the active settings.
func on_status(automation: Dictionary) -> void:
	if not bool(automation.get("running",false)):
		if minimized:_end_minimized();world.release_input()
		return
	if minimized:_update_chip();return
	# A find-pet cycle minimized from 自动抓极品 keeps its capture battles out of
	# sight too, and 后台搜宠 shows its battles with the info block instead:
	# a progress window already up gives way.
	if world.pet_hunt_menu.minimized or bool(automation.get("flow",{}).get("showcase",false)):
		if visible:hide()
		return
	if not visible:
		get_parent().move_child(self,get_parent().get_child_count()-1)
		show()
	panel.hide();progress.show()
	update_status()

func on_event(detail: Dictionary) -> void:
	var reason:=str(detail.get("reason",""))
	if str(detail.kind)=="battle_refused":
		world.message.text=reason
		if reason.begins_with("带宠升级"):close_menu()
		else:panel.hide();progress.show();result.text=reason
		return
	# 后台搜宠 hands its capture and training runs on itself; its info block
	# reports them.
	var flow: Dictionary=world.state.automation.get("flow",{})
	if bool(flow.get("showcase",false)) and str(flow.get("phase","")) in ["capture","train"] and str(detail.get("reason","")) in ["本场自动战斗已完成","目标宠物已达到等级目标"]:return
	_end_minimized()
	if bool(detail.get("takeover",false)) and world.battle_session.snapshot().active:
		if world.adventure_menu.visible:world.adventure_menu.hide()
		world.battle_view.open_battle(world.battle_session.snapshot())
		world.set_music(world.music_track("res://assets/legacy/battle/audio/sabgm_b0.wav"))
	world.clear_input();hide()
	world.release_input()
	world.last_adventure_message="自动练级：%s · 已完成 %d 场。"%[reason,int(detail.get("battles",battles))]
	world.message.text=world.last_adventure_message
	if world.battle_view.visible and world.battle_session.snapshot().active:
		world.battle_view.report.text="自动抓宠／战斗已暂停："+reason+"；可手动接手。"
func _process(delta: float) -> void:
	if not running:return
	# Over a network the backend stops the run from position reports itself;
	# another device following the character must not stop a shared run.
	if world.link.is_local() and _moved():stop_training("位置发生变化");return
	# In-process, this frame drives the backend runner at the chosen speed.
	if world.link.is_local():world.link.request({"type":"auto","name":"tick_battle","delta":delta})

func _moved() -> bool:
	var automation:=_status()
	var origin: Array=automation.get("origin_cell",[0,0])
	return int(world.data.map_id)!=int(automation.get("origin_map",-1)) or world.cell!=Vector2i(int(origin[0]),int(origin[1])) or world.area_transition_busy
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_menu();get_viewport().set_input_as_handled()
## Test seam: run one backend runner step now, after acknowledging whatever
## this client has finished presenting.
func advance() -> void:
	if not running:return
	if _moved():stop_training("位置发生变化");return
	world.acknowledge_presentation()
	world.link.request({"type":"auto_step"})

## Capture settings (shown in 自动抓极品 → 抓宠设置) are saved on change: a
## choice at once, typed or stepped numbers once the player pauses.
func save_capture_settings(now: bool = true) -> void:
	if _loading:return
	world.mark_settings_dirty(self)
	if now:world.flush_automation_settings()

func acquire_clone_override()->void:
	world.link.request({"type":"auto","name":"acquire_clone"})

func release_clone_override()->void:
	world.link.request({"type":"auto","name":"release_clone"})

## Collapses the running window into a small progress bar. The run continues and
## the world, HUD and other panels (pets, warehouse, status) stay usable.
func minimize() -> void:
	if not running or minimized:return
	minimized=true
	hide();world.clear_input()
	_chip().pop_up();_update_chip()
	world.release_input()
	world.set_viewer_pref("training_minimized",true)

## Brings the full window back with the backend's current progress.
func restore() -> void:
	if not minimized:return
	_end_minimized()
	if world.adventure_menu.visible:world.close_adventure_menu()
	world.set_viewer_pref("training_minimized",false)
	if not running:
		world.release_input();open_menu();return
	world.clear_input();world.paused_input=true
	get_parent().move_child(self,get_parent().get_child_count()-1)
	show();panel.hide();progress.show()
	update_status()

func _end_minimized() -> void:
	if not minimized:return
	minimized=false
	if is_instance_valid(chip):chip.hide()

func _chip() -> Panel:
	if not is_instance_valid(chip):
		chip=preload("res://scripts/automation_chip.gd").new()
		chip.name="TrainingHelperChip"
		chip.setup(world,"自动练级",0,restore)
		get_parent().add_child(chip)
	return chip

func _update_chip() -> void:
	if not is_instance_valid(chip):return
	var automation:=_status()
	var used: Dictionary=automation.get("settings",settings)
	var mode: String={"attack":"普通攻击","capture":"抓宠","train_pet":"带宠升级"}.get(str(used.get("preset","attack")),"自动战斗")
	var level:=int(world.session.snapshot().player.level)
	chip.present("自动练级 · %s · %s"%[mode,"战斗中" if world.state.battle_open else "遇敌中"],
		"%d 场 · Lv.%d → %d · 经验 +%d"%[battles,int(automation.get("initial_level",level)),level,earned_xp])
