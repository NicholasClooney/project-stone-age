extends Control
## Presentation only. The authority owns eligibility, selection and settlement.
const STAT_NAMES := {"vitality":"体力", "strength":"腕力", "toughness":"耐力", "dexterity":"速度"}

# A delayed old preview may reuse a newer preview's token. Defer abandoned-token
# cleanup until every preview on this link has replied, then protect its live owner.
static var deliveries: Dictionary = {}
static func begin_preview(link) -> void:
	var id: int=link.get_instance_id()
	if not deliveries.has(id):deliveries[id]={"pending":0,"owners":{},"abandoned":{}}
	deliveries[id].pending+=1
static func finish_preview(link, reply: Dictionary, owner=null) -> void:
	var id: int=link.get_instance_id()
	if not deliveries.has(id):return
	var entry: Dictionary=deliveries[id]
	entry.pending-=1
	var value: String=str(reply.get("quick_transmigration",{}).get("token",""))
	if not value.is_empty():
		if is_instance_valid(owner):entry.owners[value]=weakref(owner)
		else:entry.abandoned[value]=true
	_flush_abandoned(link)
static func release_token(link, value: String, owner=null) -> void:
	if value.is_empty():return
	var id: int=link.get_instance_id()
	if not deliveries.has(id):deliveries[id]={"pending":0,"owners":{},"abandoned":{}}
	var current=deliveries[id].owners.get(value)
	if is_instance_valid(owner) and current!=null and is_instance_valid(current.get_ref()) and current.get_ref()!=owner:return
	deliveries[id].owners.erase(value)
	deliveries[id].abandoned[value]=true
	_flush_abandoned(link)
static func _flush_abandoned(link) -> void:
	var id: int=link.get_instance_id()
	var entry: Dictionary=deliveries[id]
	if int(entry.pending)>0:return
	var cancel: Array=[]
	for value in entry.abandoned:
		var holder=entry.owners.get(value)
		if holder==null or not is_instance_valid(holder.get_ref()):cancel.append(value)
	entry.abandoned.clear()
	for value in cancel:
		entry.owners.erase(value)
		link.request({"type":"quick_transmigration","action":"cancel","token":value})
	if entry.owners.is_empty():deliveries.erase(id)

class ReplyGuard extends RefCounted:
	var target: WeakRef
	var link
	var serial: int
	var action: String
	var bookkeeping: Callable
	static func deliver(reply: Dictionary, guard: ReplyGuard) -> void:
		var view=guard.target.get_ref()
		var accepted: bool=is_instance_valid(view) and view.live and view.serial==guard.serial
		if guard.action=="preview":
			guard.bookkeeping.call(guard.link,reply,view if accepted and reply.get("ok",false) else null)
		if accepted:view._receive(reply,guard.action)

signal dismissed
var world: Node
var link
var live := false
var busy := false
var stale := true
var serial := 0
var token := ""
var baseline: Dictionary = {}
var request_baseline: Dictionary = {}
var card: PanelContainer
var scroll: ScrollContainer
var details: VBoxContainer
var status: Label
var eligibility: Label
var confirm: Button
var refresh: Button
var cancel: Button
var modes: OptionButton
var bonus: CheckBox
var selectors: Array[CheckBox] = []
const MODES := ["current","120","130"]

func setup(owner: Node) -> void:
	world=owner;link=world.link
	name="QuickTransmigrationMenu"
	theme=Theme.new();theme.default_font=preload("res://assets/fonts/NotoSansSC.ttf");theme.default_font_size=16
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP;z_as_relative=false;z_index=91
	var shade:=ColorRect.new();shade.color=Color(0,0,0,0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	card=PanelContainer.new();add_child(card)
	var style:=StyleBoxFlat.new();style.bg_color=Color("24281f");style.border_color=Color("a69b70")
	style.set_border_width_all(2);style.set_corner_radius_all(8)
	style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=14;style.content_margin_bottom=14
	card.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);card.add_child(column)
	var title:=Label.new();title.text="人物快速转生 · 项目作弊便利";title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	_label(content,"每次只转一转，最多五转；仍回 Lv1，不自动练回或连续转生。免任务前置、免祭品，不扣宠物。")
	modes=OptionButton.new();modes.name="LevelMode";modes.custom_minimum_size.y=44
	for caption in ["当前真实等级","模拟练至120级（默认）","虚拟130级（作弊模拟）"]:modes.add_item(caption)
	modes.select(1);content.add_child(modes);modes.item_selected.connect(func(_index):_options_changed())
	_label(content,"130 超出自然120级上限，只用于本次作弊模拟，不改变真实升级上限。目标不能低于真实等级。")
	bonus=CheckBox.new();bonus.name="BonusQuests";bonus.text="本轮计入20项任务加成";bonus.button_pressed=true
	bonus.custom_minimum_size.y=44;content.add_child(bonus);bonus.toggled.connect(func(_on):_options_changed())
	_label(content,"关闭为本轮0项；保留历史累计，不补做任务或发前置奖励；不是增加20属性点。")
	_label(content,"已有未分配点 + 模拟每升一级新增3点，均分至勾选项（至少一项）。已配点不洗；余数依体腕耐速顺序。均分是默认方案，不代表最优。")
	var choices:=HFlowContainer.new();content.add_child(choices)
	for key in STAT_NAMES:
		var choice:=CheckBox.new();choice.name="Allocation_"+key;choice.text=STAT_NAMES[key];choice.button_pressed=true
		choice.set_meta("stat",key);choice.custom_minimum_size.y=44;choices.add_child(choice);selectors.append(choice)
		choice.toggled.connect(func(_on):_options_changed())
	eligibility=_label(content,"")
	details=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",10);content.add_child(details)
	status=_label(column,"")
	confirm=_button(column,"确认本次转生 · 回到Lv1",_confirm)
	refresh=_button(column,"获取服务器预览",_request_preview)
	cancel=_button(column,"取消",func():dismissed.emit())
	get_viewport().size_changed.connect(_layout)
	world.state.changed.connect(_state_changed)
	if link.has_signal("disconnected"):link.disconnected.connect(_disconnected)
	live=true;baseline=world.session.snapshot().duplicate(true)
	_layout();_buttons()

func _layout() -> void:
	var viewport: Vector2=size if size.x>0 and size.y>0 else get_viewport_rect().size
	card.position=Vector2(maxf(8,(viewport.x-600)/2),16)
	card.size=Vector2(minf(600,viewport.x-16),maxf(280,viewport.y-32))

func _label(parent: Node, value: String) -> Label:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(label);return label

func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button:=Button.new();button.text=caption;button.custom_minimum_size.y=44
	button.pressed.connect(callback);parent.add_child(button);return button

func selected_stats() -> Array:
	var result: Array=[]
	for choice in selectors:
		if choice.button_pressed:result.append(str(choice.get_meta("stat")))
	return result

func invalid_reason() -> String:
	var player: Dictionary=world.session.snapshot().get("player",{})
	var actual:=int(player.get("level",1))
	if int(player.get("transmigration",0))>=5:return "已经五转，不能继续转生。"
	if modes.selected==0 and actual<80:return "当前等级低于80，不能按当前等级转生；请选择120或130模拟。"
	if modes.selected>0 and int(MODES[modes.selected])<actual:return "目标等级低于真实等级，不能降级模拟；请选择更高目标或当前等级。"
	if selected_stats().is_empty():return "至少勾选一项属性接收候选配点。"
	return ""

func _buttons() -> void:
	var reason:=invalid_reason()
	var actual:=int(world.session.snapshot().get("player",{}).get("level",1))
	eligibility.text=reason if not reason.is_empty() else ("当前真实等级低于80：当前等级选项不可用，请使用120或130模拟。" if actual<80 else "")
	modes.set_item_disabled(0,actual<80)
	modes.set_item_disabled(1,actual>120)
	modes.set_item_disabled(2,actual>130)
	modes.tooltip_text="当前等级低于80时不可选；请选择120或130。目标低于真实等级时不可选。"
	confirm.disabled=busy or stale or token.is_empty() or not reason.is_empty()
	refresh.disabled=busy or not reason.is_empty()
	modes.disabled=busy;bonus.disabled=busy
	for choice in selectors:choice.disabled=busy

func _options_changed() -> void:
	stale=true
	status.text="选项已改变，请重新获取服务器预览。"
	_buttons()

func _state_changed(_kind: String) -> void:
	if not live:return
	if world.session.snapshot()==baseline:return
	stale=true;status.text="角色状态已更新，旧预览不能确认。请重新获取预览。";_buttons()

func _disconnected() -> void:
	if not live:return
	stale=true;status.text="连接已断开，请重新连接后重新获取预览。";_buttons()

func _request_preview() -> void:
	if not live or busy or not invalid_reason().is_empty():return
	request_baseline=world.session.snapshot().duplicate(true)
	stale=true
	_send({"type":"quick_transmigration","action":"preview","level_mode":MODES[modes.selected],"bonus_quests":20 if bonus.button_pressed else 0,"allocation_stats":selected_stats()},"preview")

func _confirm() -> void:
	if not live or busy or stale or token.is_empty():return
	if world.session.snapshot()!=baseline:
		_state_changed("snapshot");return
	_send({"type":"quick_transmigration","action":"confirm","token":token},"confirm")

func _send(command: Dictionary, action: String) -> void:
	busy=true;_buttons()
	status.text="确认已提交，正在保存；关闭不会撤销已提交操作。" if action=="confirm" else "正在获取服务器预览……"
	cancel.text="关闭（确认已提交）" if action=="confirm" else "取消"
	var guard:=ReplyGuard.new();guard.target=weakref(self);guard.link=link;guard.serial=serial;guard.action=action;guard.bookkeeping=finish_preview
	if action=="preview":begin_preview(link)
	link.request(command,ReplyGuard.deliver.bind(guard))

func _receive(reply: Dictionary, action: String) -> void:
	busy=false;cancel.text="取消"
	if not bool(reply.get("ok",false)):
		stale=true
		status.text=str(reply.get("reason","操作失败。"))+"\n请重新获取预览后再确认。"
		_buttons();return
	if action=="confirm":
		world.message.text="快速转生成功，已保存并返回村庄；当前Lv1。"
		dismissed.emit();return
	var value: Dictionary=reply.get("quick_transmigration",{})
	if str(value.get("token","")).is_empty():
		stale=true;status.text="服务器未返回有效预览，请重新获取。";_buttons();return
	var old:=token;token=str(value.token)
	if old!=token:release_token(link,old,self)
	baseline=request_baseline.duplicate(true)
	stale=world.session.snapshot()!=baseline
	for child in details.get_children():details.remove_child(child);child.queue_free()
	_label(details,"服务器预览：第%d转 → 第%d转；转后Lv1\n真实等级 %d → 计算等级 %d（%s）" % [int(baseline.get("player",{}).get("transmigration",0)),int(value.get("new_count",0)),int(value.get("actual_level",0)),int(value.get("target_level",0)),str(value.get("level_mode",""))])
	_label(details,"旧未配点 %d + 模拟新增点 %d = 候选可配点 %d（全部分配）" % [int(value.get("existing_points",0)),int(value.get("gained_points",0)),int(value.get("existing_points",0))+int(value.get("gained_points",0))])
	var allocations: Array[String]=[]
	for row in value.get("allocation",[]):allocations.append("%s %d" % [STAT_NAMES.get(str(row.get("stat","")),str(row.get("stat",""))),int(row.get("points",0))])
	_label(details,"配点去向："+"；".join(allocations))
	for pair in [["pre_base_stats","转前候选四维"],["base_stats","转后继承四维"]]:
		var stats: Dictionary=value.get(pair[0],{})
		var lines: Array[String]=[]
		for key in STAT_NAMES:lines.append("%s %.2f" % [STAT_NAMES[key],float(stats.get(key,0))/100.0])
		_label(details,str(pair[1])+"："+"；".join(lines))
	var equation:=int(value.get("equation",0))
	_label(details,"新一轮自由点：%d；本轮任务加成计数：%d\n继承计算累计：任务加成Q=%d，转生等级L=%d（含模拟，不代表真实完成任务数）。" % [int(value.get("stat_points",0)),int(value.get("quest_count",0)),equation >> 16,equation & 65535])
	var reward: Dictionary=value.get("reward",{});var location: Dictionary=value.get("location",{})
	_label(details,"奖励：Lv1 %s\n返回出生村，坐标(%d, %d)。" % [str(reward.get("name","奖励宠物")),int(location.get("x",0)),int(location.get("y",0))])
	_label(details,"免祭品，不扣宠。大部分本轮任务进度重置，原规则保留的进度不变。若走自然转生路线，四精灵试炼需重新完成；本入口仍免任务前置。骑乘解除，宠物忠诚重算，不合条件装备卸入背包；金币及仓库存量保留。")
	if not str(value.get("warning","")).is_empty():_label(details,str(value.warning))
	status.text="角色状态已改变，请重新获取预览。" if stale else "请核对预览；确认只执行本次一转。"
	refresh.text="重新获取预览";_buttons()
	scroll.call_deferred("ensure_control_visible",details)

func shutdown() -> void:
	if not live:return
	live=false;serial+=1
	release_token(link,token,self);token="";hide()

func _exit_tree() -> void:shutdown()
