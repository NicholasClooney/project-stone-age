extends Control
## Presentation only. The authority owns eligibility, selection and settlement.
const NPC_ID := "777/ten.arg@32021:31:28"
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
	var value: String=str(reply.get("transmigration",{}).get("token",""))
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
		link.request({"type":"transmigration","action":"cancel","token":value})
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
			guard.bookkeeping.call(guard.link,reply,view if accepted and reply.get("ok",false) and str(reply.get("transmigration",{}).get("npc_id",""))==NPC_ID else null)
		if accepted:view._receive(reply,guard.action)

signal dismissed
var world: Node
var link
var live := false
var busy := false
var stale := false
var serial := 0
var token := ""
var preview: Dictionary = {}
var baseline: Dictionary = {}
var selected_ids: Array = []
var card: PanelContainer
var scroll: ScrollContainer
var details: VBoxContainer
var status: Label
var confirm: Button
var refresh: Button
var cancel: Button
var selectors: Array[Button] = []

func setup(owner: Node) -> void:
	world=owner;link=world.link
	name="TransmigrationConfirmation"
	theme=Theme.new()
	theme.default_font=preload("res://assets/fonts/NotoSansSC.ttf")
	theme.default_font_size=16
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_as_relative=false;z_index=90
	var shade:=ColorRect.new()
	shade.color=Color(0,0,0,0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	card=PanelContainer.new();add_child(card)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("24281f")
	style.border_color=Color("a69b70")
	style.set_border_width_all(2);style.set_corner_radius_all(8)
	style.content_margin_left=16;style.content_margin_right=16
	style.content_margin_top=14;style.content_margin_bottom=14
	card.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);card.add_child(column)
	var title:=Label.new();title.text="精灵王 · 人物转生确认"
	title.add_theme_font_size_override("font_size",21);column.add_child(title)
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;column.add_child(scroll)
	details=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation",10);scroll.add_child(details)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(status)
	confirm=_button(column,"确认转生并消耗所列宠物",_confirm)
	refresh=_button(column,"重新获取预览",func():_request_preview(selected_ids))
	cancel=_button(column,"取消 · 不消耗",func():dismissed.emit())
	get_viewport().size_changed.connect(_layout)
	world.state.changed.connect(_state_changed)
	_layout()

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button:=Button.new();button.text=title;button.custom_minimum_size.y=44
	button.pressed.connect(callback);parent.add_child(button);return button

func _layout() -> void:
	var viewport: Vector2=get_viewport_rect().size
	card.position=Vector2(maxf(8,(viewport.x-580)/2),16)
	card.size=Vector2(minf(580,viewport.x-16),maxf(280,viewport.y-32))

func show_preview(value: Dictionary) -> void:
	live=true;busy=false;stale=false
	preview=value.duplicate(true);token=str(value.get("token",""))
	baseline=world.session.snapshot().duplicate(true)
	selected_ids.clear();selectors.clear()
	for child in details.get_children():details.remove_child(child);child.queue_free()
	var player: Dictionary=baseline.get("player",{})
	_label("第 %d 转 → 第 %d 转\n转生后等级 1；新轮自由点 %d；已完成计数 %d。" % [int(player.get("transmigration",0)),int(value.get("new_count",0)),int(value.get("stat_points",0)),int(value.get("quest_count",0))])
	var stats: Dictionary=value.get("base_stats",{})
	var lines: Array[String]=[]
	for key in STAT_NAMES:lines.append("%s %.2f" % [STAT_NAMES[key],float(stats.get(key,0))/100.0])
	_label("继承基础属性\n"+"　".join(lines))
	_label("将消耗以下随身宠物（默认按原槽顺序）。可选择同模板的另一 UID；更换后须重新审核预览。")
	for sacrifice in value.get("sacrifices",[]):
		selected_ids.append(str(sacrifice.get("pet_id","")))
		_label("%s · Lv%d\nUID %s · 模板 %d" % [str(sacrifice.get("name","")),int(sacrifice.get("level",0)),str(sacrifice.get("pet_id","")),int(sacrifice.get("template_id",0))])
		var slot:=selected_ids.size()-1
		var group:=ButtonGroup.new()
		for pet in baseline.get("pets",[]):
			var template_id: int=int(pet.get("template_id",-1))
			var species:=str(pet.get("species",""))
			if species.begins_with("original_") and species.trim_prefix("original_").is_valid_int():template_id=int(species.trim_prefix("original_"))
			if template_id!=int(sacrifice.get("template_id",-2)):continue
			var uid:=str(pet.get("pet_id",""))
			var choice:=Button.new();choice.custom_minimum_size.y=48
			choice.text="%s · Lv%d\nUID %s" % [str(pet.get("name","")),int(pet.get("level",0)),uid]
			choice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			choice.toggle_mode=true;choice.button_group=group
			choice.button_pressed=uid==str(sacrifice.get("pet_id",""))
			choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			choice.set_meta("pet_id",uid)
			selectors.append(choice);details.add_child(choice)
			choice.pressed.connect(func():
				selected_ids[slot]=uid
				stale=true;status.text="祭品选择已改变，请重新获取预览后再确认。";_buttons())

	var reward: Dictionary=value.get("reward",{})
	var location: Dictionary=value.get("location",{})
	_label("奖励：Lv1 宠物模板 %d（原敌人编号 %d）\n返村：地图 %d，坐标 (%d, %d)。" % [int(reward.get("template_id",0)),int(reward.get("enemy_id",0)),int(location.get("map_id",0)),int(location.get("x",0)),int(location.get("y",0))])
	_label("任务旗标：本轮任务按原规则清除；原已置位的 END69–72、109、118、122、127、131、158、159 和 NOW69–72 保留，补记本次转生旗标。四信物 END53 奖励不开放。\n本轮未分配赠点不结转；分配点归零。骑乘解除；其它宠物保留，忠诚重算，不合条件的装备卸入背包。金币上限统一为 10 亿，现有金币、物品仓库及宠仓存量保留；物仓仍为免费 3000 格，宠仓不缩减。")
	var warning:=str(value.get("warning",""))
	if not warning.is_empty():_label(warning)
	status.text="请核对 UID；确认成功后将消耗所列宠物并返村。"
	scroll.scroll_vertical=0;_buttons();show()

func _label(value: String) -> void:
	var label:=Label.new();label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	details.add_child(label)

func _buttons() -> void:
	confirm.disabled=busy or stale or token.is_empty()
	refresh.disabled=busy
	for choice in selectors:choice.disabled=busy

func _state_changed(kind: String) -> void:
	if not live or kind not in ["profile","pet_storage","snapshot"]:return
	if world.session.snapshot()==baseline:return
	stale=true;status.text="角色状态已更新，旧预览不能确认。请重新获取预览。";_buttons()

func _request_preview(pet_ids: Array) -> void:
	if not live or busy:return
	_send({"type":"transmigration","action":"preview","npc_id":NPC_ID,"pet_ids":pet_ids.duplicate()},"preview")

func _confirm() -> void:
	if not live or busy or stale or token.is_empty():return
	_send({"type":"transmigration","action":"confirm","token":token},"confirm")

func _send(command: Dictionary, action: String) -> void:
	busy=true;_buttons()
	status.text="确认已提交，正在保存；关闭不会撤销已提交操作。" if action=="confirm" else "正在核对，请稍候……"
	cancel.text="关闭（确认已提交）" if action=="confirm" else "取消 · 不消耗"
	var guard:=ReplyGuard.new();guard.target=weakref(self);guard.link=link;guard.serial=serial;guard.action=action;guard.bookkeeping=finish_preview
	if action=="preview":begin_preview(link)
	link.request(command,ReplyGuard.deliver.bind(guard))

func _receive(reply: Dictionary, action: String) -> void:
	busy=false;cancel.text="取消 · 不消耗"
	if not bool(reply.get("ok",false)):
		var reason:=str(reply.get("reason","操作失败。"))
		if reason=="save_failed":reason="保存失败，尚未扣除祭品或完成转生。"
		elif reason=="offline":reason="连接已断开，请重新连接后核对角色状态。"
		if reason.contains("已过期") or reason.contains("状态已改变"):stale=true
		status.text=reason+"\n保存失败可用原确认重试；若预览已失效，请重新获取预览。"
		_buttons();return
	if action=="confirm":
		world.message.text="转生成功，已由服务器保存并返回村庄。"
		dismissed.emit();return
	var value: Dictionary=reply.get("transmigration",{})
	if str(value.get("npc_id",""))!=NPC_ID or str(value.get("token","")).is_empty():
		stale=true;status.text="服务器未返回有效的精灵王预览，请重新获取。";_buttons();return
	var old:=token
	show_preview(value)
	if old!=token:release_token(link,old,self)

func shutdown() -> void:
	if not live:return
	live=false;serial+=1
	release_token(link,token,self);token=""
	hide()

func _exit_tree() -> void:
	shutdown()
