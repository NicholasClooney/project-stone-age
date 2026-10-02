extends RefCounted
## Adapt only the old collection window. Keep the existing controls/callbacks,
## so remote clients use exactly the same Session actions as desktop clients.
const TOUCH_NAMES := {26058:"PetRenameTouch",26046:"PetSkillsTouch",26093:"PetRenameConfirmTouch",26050:"PetRenameCancelTouch",26180:"PetPreviousTouch",26182:"PetNextTouch",26043:"PetBackTouch",26056:"PetDetailsTouch",26042:"PetNativeCloseTouch"}

static func resize(menu: Control) -> void:
	if menu.visible and menu.kind=="pets" and not menu.pet_records_open and not menu.pet_compare_open and not menu.pet_storage_open:
		menu.call_deferred("rebuild")

static func build(menu: Control) -> void:
	var panel: Control=menu.panel
	var original_nodes:=panel.get_children()
	var native_height:float=panel.size.y
	if menu.pet_rename:native_height=432
	panel.size=Vector2(menu.size.x-8,menu.size.y-48)
	var frame:=PanelContainer.new()
	frame.name="PetCollectionMobile"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(frame)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("252a24")
	style.border_color=Color("a59b73")
	style.set_border_width_all(2)
	style.content_margin_left=8;style.content_margin_right=8
	style.content_margin_top=8;style.content_margin_bottom=8
	frame.add_theme_stylebox_override("panel",style)
	var layout:=VBoxContainer.new()
	layout.add_theme_constant_override("separation",8)
	frame.add_child(layout)
	var close:=Button.new()
	close.name="PetCollectionClose";close.text="宠物收藏 · 关闭"
	close.custom_minimum_size.y=44
	close.pressed.connect(menu.world.close_adventure_menu)
	layout.add_child(close)
	var scroll:=ScrollContainer.new()
	scroll.name="PetCollectionScroll"
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter=Control.MOUSE_FILTER_STOP
	layout.add_child(scroll)
	var content:=VBoxContainer.new()
	content.name="PetCollectionContent"
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",8)
	scroll.add_child(content)
	var native_center:=CenterContainer.new()
	content.add_child(native_center)
	var native:=Control.new()
	native.name="PetNativeView"
	native.custom_minimum_size=Vector2(272,native_height)
	native_center.add_child(native)
	var actions:=GridContainer.new()
	actions.name="PetNativeActions";actions.columns=2
	actions.add_theme_constant_override("h_separation",8)
	actions.add_theme_constant_override("v_separation",8)
	content.add_child(actions)
	var collection:Array[Control]=[]
	var growth:Array[Control]=[]
	for node in original_nodes:
		if not node is Control:continue
		if node.position.x>=560:
			growth.append(node)
		elif node.position.x>=288:
			collection.append(node)
		else:
			node.reparent(native,false)
			if node is TextureButton:
				# The original art remains in the native card; small interactive
				# controls become labelled 44px targets below it, without overlaps.
				node.hide()
				var caption:String=node.tooltip_text
				if caption.is_empty():caption="返回资料" if menu.pet_view=="skills" else "返回列表" if menu.pet_view=="detail" else "关闭"
				if node.texture_normal==menu.original(26093):caption="确定改名"
				if node.texture_normal==menu.original(26050):caption="取消改名"
				if node.name=="PetStatusStore":caption="存入仓库"
				if str(node.name).begins_with("PetState"):
					var index:=int(str(node.name).trim_prefix("PetState"))
					caption+=" · "+str(menu.world.session.snapshot().pets[index].name)
				var touch:=Button.new()
				touch.name=str(node.name)+"Touch";touch.text=caption
				for ident in TOUCH_NAMES:
					if node.texture_normal==menu.original(ident):touch.name=TOUCH_NAMES[ident]
				touch.tooltip_text=node.tooltip_text
				touch.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
				touch.custom_minimum_size=Vector2(0,44)
				touch.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				touch.disabled=node.disabled
				touch.pressed.connect(node.pressed.emit)
				actions.add_child(touch)
			elif node is LineEdit:
				node.reparent(content,false)
				node.custom_minimum_size.y=44
				content.move_child(node,1)
	# Keep categories, page controls and each existing helper action in order.
	collection.sort_custom(func(a,b):return a.position.y<b.position.y if a.position.y!=b.position.y else a.position.x<b.position.x)
	for node in collection:
		if node is TextureRect:
			node.queue_free();continue
		node.reparent(content,false)
		node.position=Vector2.ZERO
		node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		node.custom_minimum_size.x=0
		if node is TextureButton:
			node.hide()
			var touch:=Button.new()
			touch.text=node.tooltip_text;touch.name="PetPagePrevious" if node.tooltip_text=="上一页" else "PetPageNext"
			touch.custom_minimum_size.y=44
			touch.pressed.connect(node.pressed.emit)
			content.add_child(touch)
		elif node is BaseButton:
			node.custom_minimum_size.y=44
			if node is Button:node.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		elif node is Label:
			node.size.x=0
			node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	if not growth.is_empty():
		# Reflow the existing forecast labels; each row's values retain their
		# columns and all explanatory text wraps inside the scroll width.
		var rows:={}
		for node in growth:
			if not node is Label:node.queue_free();continue
			var y:=int(node.position.y)
			if not rows.has(y):rows[y]=[]
			rows[y].append(node)
		var ys:=rows.keys();ys.sort()
		for y in ys:
			var labels:Array=rows[y]
			labels.sort_custom(func(a,b):return a.position.x<b.position.x)
			var row:=HBoxContainer.new()
			content.add_child(row)
			for node in labels:
				node.reparent(row,false)
				node.size=Vector2.ZERO
				node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				node.custom_minimum_size.x=0
				node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
