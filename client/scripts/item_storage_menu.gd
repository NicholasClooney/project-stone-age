extends Control
## Read-only snapshots + one RPC. No local or remote backend access.
const Storage=preload("res://server/item_storage.gd")
var world: Node
var deposit:=true
var selected: Dictionary={}
var busy:=false
var revision:=0
var page:=0
var policy: Label
var page_label: Label
const PAGE_SIZE:=15
var status: Label
var list: VBoxContainer
var heading: Label
var action: Button
var bag_tab: Button
var warehouse_tab: Button
var catalog=preload("res://scripts/quest_catalog.gd").new()
var last_view: Array=[]

func _ready() -> void:
	name="ItemStorageMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=50
	# Parent inventory is z50 too; do not add it into a visual-only z100.
	z_as_relative=false
	var shade:=ColorRect.new();shade.z_index=1;shade.color=Color(0.025,0.04,0.04,1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	var margin:=MarginContainer.new();margin.z_index=1;margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,48 if side=="bottom" else 16)
	add_child(margin)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);margin.add_child(box)
	box.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	box.add_theme_font_size_override("font_size",16)
	var title_row:=HBoxContainer.new();box.add_child(title_row)
	heading=Label.new();heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_row.add_child(heading)
	var close:=button("返回背包","StorageClose",title_row);close.pressed.connect(close_menu)
	var help:=Label.new();help.text="项目改动：3000格，无个体状态物品每堆64。\n所有背包道具均可存；装备存前先卸下。\n任务物品入仓后不算随身，交任务前请取出。";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(help)
	policy=Label.new();policy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(policy)
	var tabs:=HBoxContainer.new();box.add_child(tabs)
	bag_tab=button("背包 · 存入","StorageBagTab",tabs);bag_tab.pressed.connect(func():change_tab(true))
	warehouse_tab=button("仓库 · 取出","StorageWarehouseTab",tabs);warehouse_tab.pressed.connect(func():change_tab(false))
	var scroll:=ScrollContainer.new();scroll.name="StorageItemsScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;box.add_child(scroll)
	list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);scroll.add_child(list)
	var pages:=HBoxContainer.new();box.add_child(pages)
	var previous:=button("上一页","StoragePrevious",pages);previous.pressed.connect(func():page=maxi(0,page-1);refresh(true))
	page_label=Label.new();pages.add_child(page_label)
	var next:=button("下一页","StorageNext",pages);next.pressed.connect(func():page+=1;refresh(true))
	status=Label.new();status.name="StorageFeedback";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.y=48;box.add_child(status)
	var controls:=HBoxContainer.new();box.add_child(controls)
	var all:=button("全选可存","StorageSelectAll",controls)
	all.pressed.connect(func():
		if busy:return
		selected.clear()
		for row in Storage.rows(world.session.snapshot(),catalog.items,deposit):
			if row.reason.is_empty():selected[row.id]=Storage.take(row,1)
		refresh(true))
	action=button("存入所选","StorageTransfer",controls);action.pressed.connect(submit)
	world.state.changed.connect(state_changed)
	visibility_changed.connect(func():
		if not is_visible_in_tree():selected.clear())
	hide()

func button(caption: String, ident: String, parent: Node) -> Button:
	var result:=Button.new();result.text=caption;result.name=ident;result.custom_minimum_size=Vector2(0,44);result.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(result);return result

func open_menu() -> void:
	deposit=true;page=0;selected.clear();last_view=[];status.text="";show();refresh(true)

func close_menu() -> void:
	if busy:return
	hide()

func change_tab(to_bag: bool) -> void:
	if busy:return
	deposit=to_bag;page=0;selected.clear();status.text="";refresh(true)

func state_changed(_kind: String) -> void:
	if is_visible_in_tree():call_deferred("refresh")

func refresh(force: bool=false) -> void:
	if not is_visible_in_tree():return
	var profile: Dictionary=world.session.snapshot()
	var rows: Array=Storage.rows(profile,catalog.items,deposit)
	var view: Array=[rows,int(profile.get("item_storage_revision",0)),Storage.capacity(profile),Storage.used(profile),deposit]
	if not force and view==last_view:return
	if not last_view.is_empty() and view!=last_view and not busy and not selected.is_empty():
		selected.clear();status.text="物品状态已更新，请重新选择。"
	last_view=view.duplicate(true)
	revision=int(profile.get("item_storage_revision",0))
	heading.text="物品仓库 %d / %d"%[Storage.used(profile),Storage.capacity(profile)]
	bag_tab.disabled=busy or deposit;warehouse_tab.disabled=busy or not deposit
	for child in list.get_children():list.remove_child(child);child.queue_free()
	if rows.is_empty():
		var empty:=Label.new();empty.text="背包没有物品。" if deposit else "仓库是空的。";list.add_child(empty)
	var pages:=maxi(1,int(ceil(float(rows.size())/PAGE_SIZE)))
	page=clampi(page,0,pages-1);page_label.text="%d / %d"%[page+1,pages]
	policy.text="项目改动：存入和取出均免费。"
	for row in rows.slice(page*PAGE_SIZE,(page+1)*PAGE_SIZE):
		var line:=HBoxContainer.new();list.add_child(line)
		var item:=CheckBox.new();item.name="StorageRow_"+row.id;item.custom_minimum_size.y=56
		item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		item.text="%s ×%d%s\n%s"%[row.name,int(row.count)," · 耐久%d"%int(row.durability) if int(row.durability)>0 else "",row.reason if not row.reason.is_empty() else "可存入" if deposit else "可取出"]
		item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		item.button_pressed=selected.has(row.id);item.disabled=busy or not row.reason.is_empty()
		line.add_child(item)
		var quantity: SpinBox
		if int(row.count)>1:
			quantity=SpinBox.new();quantity.name="StorageCount_"+row.id;quantity.min_value=1;quantity.max_value=int(row.count);quantity.value=1;quantity.custom_minimum_size.x=88;quantity.editable=not busy and row.reason.is_empty()
			if selected.has(row.id):
				var choice: Dictionary=selected[row.id]
				quantity.value=choice.uids.size() if choice.has("uids") else int(choice.get("count",1))
			line.add_child(quantity)
			quantity.value_changed.connect(func(count: float):
				if not item.button_pressed:item.button_pressed=true
				selected[row.id]=Storage.take(row,int(count));update_action())
		item.toggled.connect(func(on: bool):
			if on:selected[row.id]=Storage.take(row,int(quantity.value) if quantity!=null else 1)
			else:selected.erase(row.id)
			update_action())
	var select_all:=find_child("StorageSelectAll",true,false) as Button
	select_all.text="全选可存" if deposit else "全选";select_all.disabled=busy
	update_action()

func update_action() -> void:
	action.text=("存入所选" if deposit else "取出所选")+"（%d）"%selected.size()
	action.disabled=busy or selected.is_empty()

func submit() -> void:
	if busy or selected.is_empty():return
	busy=true;status.text="正在保存…"
	var command: Dictionary={"type":"item_storage_transfer","direction":"deposit" if deposit else "withdraw","revision":revision,"items":selected.values().duplicate(true)}
	refresh(true)
	var weak: WeakRef=weakref(self)
	world.link.request(command,func(reply: Dictionary):
		if weak.get_ref()==null:return
		busy=false
		if bool(reply.get("ok",false)):selected.clear()
		status.text=str(reply.get("note",reply.get("reason","请求失败。")))
		refresh(true))
