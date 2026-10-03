extends VBoxContainer
## Read-only snapshot projection; actions are UID signals handled by the caller.
const Table = preload("res://scripts/pet_table.gd")
const Comparison = preload("res://scripts/pet_comparison.gd")
signal withdraw_requested(uid: String)
var order := ""
var ascending := false
var individuals: Array = []
var best_sum_uid := ""
var best_attack_uid := ""
var pending := false
var rows: VBoxContainer
var header: HBoxContainer
const COLUMNS := [["name","名字 / UID",176],["level","Lv",32],["attack","攻",36],["defence","防",36],["speed","敏",36],["stat_total","三围合",54],["hp","血 / 上限",88],["place","位置",78],["best","120级最佳",76],["action","操作",72]]

func _init() -> void:
	name = "OwnedList"
	add_theme_constant_override("separation",2)
	var hint := Table.text("当前属性 · 点列名排序；窄屏左右滑动查看全部列", "meta")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.name = "OwnedHorizontalScroll"
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation",6)
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left",6)
	inset.add_theme_constant_override("margin_right",6)
	inset.add_child(header)
	content.add_child(inset)
	for column in COLUMNS:
		var key: String = column[0]
		var control: Control
		if key in ["level","attack","defence","speed","stat_total"]:
			var button := Button.new()
			button.name = "OwnedSort_"+key
			button.text = column[1]
			Table.style_button(button,true)
			button.pressed.connect(func():sort_by(key))
			control = button
		else:control = Table.text(column[1],"head")
		if control is Label:control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		control.custom_minimum_size = Vector2(column[2],44)
		header.add_child(control)
	rows = VBoxContainer.new()
	rows.name = "OwnedIndividuals"
	rows.add_theme_constant_override("separation",2)
	content.add_child(rows)

func update_snapshot(items: Array, profile: Dictionary, busy: bool) -> void:
	individuals = items.duplicate()
	pending = busy
	best_sum_uid = ""
	best_attack_uid = ""
	var best_sum := -1
	var best_attack := -1
	# Same tie rule as Encyclopedia.owned_best: carried then stored, first in
	# authority order. Sorting only this projection cannot change the winner.
	for item in individuals:
		var pet: Dictionary = item.pet
		var stats: Dictionary = Comparison.expected(pet)
		var total := Comparison.sort_value(stats,"stat_total")
		if total > best_sum:
			best_sum = total
			best_sum_uid = str(pet.pet_id)
		if int(stats.get("attack",0)) > best_attack:
			best_attack = int(stats.attack)
			best_attack_uid = str(pet.pet_id)
		item.place = "仓库" if item.location == "pet_storage" else "随身"
		if item.location == "pets":
			if int(item.index) == int(profile.get("active_pet",-1)):item.place += "·出战"
			if int(item.index) == int(profile.get("ride_pet",-1)):item.place += "·骑乘"
	_redraw()

func sort_by(key: String) -> void:
	ascending = not ascending if order == key else false
	order = key
	_redraw()

func _redraw() -> void:
	for column in COLUMNS:
		var button := header.get_node_or_null("OwnedSort_"+str(column[0]))
		if button != null:button.text = str(column[1])+("↑" if ascending else "↓") if order == column[0] else str(column[1])
	var sorted := individuals.duplicate()
	if not order.is_empty():
		# Reuse warehouse's comparator, with sequential source indices as ties.
		var pets: Array = individuals.map(func(item):return item.pet)
		sorted = Comparison.storage_rows({"pet_storage":pets},order,false,ascending).map(func(item):return individuals[item.index])
	var existing := {}
	for row in rows.get_children():existing[str(row.get_meta("pet_id"))] = row
	for index in range(sorted.size()):
		var item: Dictionary = sorted[index]
		var pet: Dictionary = item.pet
		var uid := str(pet.pet_id)
		var sum_best := uid == best_sum_uid
		var attack_best := uid == best_attack_uid
		var row: PanelContainer = existing.get(uid)
		if row == null:
			row = Table.row_panel(index,sum_best or attack_best)
			row.name = "OwnedPet_"+uid
			row.set_meta("pet_id",uid)
			var line := HBoxContainer.new()
			line.name = "Line"
			line.add_theme_constant_override("separation",6)
			row.add_child(line)
			for column in COLUMNS:
				var control: Control
				if column[0] == "action":
					var button := Button.new()
					button.name = "WithdrawOwned_"+uid
					button.text = "移到随身"
					Table.style_button(button,true)
					button.pressed.connect(func():withdraw_requested.emit(uid))
					control = button
				else:
					control = Table.cell("",column[2]) if column[0] in ["level","attack","defence","speed","stat_total","hp"] else Table.text("","meta",Table.TEXT)
					control.name = column[0]
				if control is Label:control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				control.custom_minimum_size = Vector2(column[2],38)
				line.add_child(control)
			rows.add_child(row)
		existing.erase(uid)
		rows.move_child(row,index)
		var style_row := Table.row_panel(index,sum_best or attack_best)
		row.add_theme_stylebox_override("panel",style_row.get_theme_stylebox("panel"))
		style_row.free()
		row.set_meta("best_sum",sum_best)
		row.set_meta("best_attack",attack_best)
		var line := row.get_node("Line")
		line.get_node("name").text = "%s · %s" % [pet.get("name",""),uid]
		for key in ["level","attack","defence","speed","stat_total"]:line.get_node(key).text = str(Comparison.sort_value(pet,key))
		line.get_node("hp").text = "%d/%d" % [pet.get("hp",0),pet.get("max_hp",0)]
		line.get_node("place").text = item.place
		line.get_node("best").text = ("合★ " if sum_best else "")+("攻★" if attack_best else "")
		line.get_node("best").add_theme_color_override("font_color",Table.GOLD)
		var button: Button = line.get_node("WithdrawOwned_"+uid)
		button.visible = item.location == "pet_storage"
		button.disabled = pending
		row.tooltip_text = "%s · %s\n120级最佳并列：随身优先，再按原有顺序首只；不随列表排序改变。" % [pet.get("name",""),uid]
	for row in existing.values():
		rows.remove_child(row)
		row.queue_free()

	# Let unusually long names, UIDs, dual positions or numbers widen every
	# matching column together. Horizontal scrolling keeps them complete.
	for column_index in range(COLUMNS.size()):
		var width: float = maxf(COLUMNS[column_index][2],header.get_child(column_index).get_minimum_size().x)
		for row in rows.get_children():
			width = maxf(width,row.get_node("Line").get_child(column_index).get_minimum_size().x)
		header.get_child(column_index).custom_minimum_size.x = width
		for row in rows.get_children():row.get_node("Line").get_child(column_index).custom_minimum_size.x = width
