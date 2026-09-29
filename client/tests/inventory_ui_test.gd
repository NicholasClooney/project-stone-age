extends SceneTree
## Source-backed five-slot inventory; total ownership stays in authority.
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value:
		failures+=1
		push_error(message)
func double_click(control: Control) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.double_click=true
	control.gui_input.emit(event)
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position=point
	motion.global_position=point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point
		event.global_position=point
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		root.push_input(event,true)
		await process_frame

func run() -> void:
	var world = load("res://scenes/main.tscn").instantiate()
	world.profile_persistence=false
	root.add_child(world)
	await process_frame
	world.session._profile.inventory.club=1
	world.adventure_menu.open_menu("inventory")
	var menu=world.adventure_menu
	check(menu.panel.has_node("BagIcon_club"),"Owned club initially appears in bag")
	double_click(menu.panel.get_node("ItemSlot_club"))
	await process_frame
	check(world.session.snapshot().equipped,"Double-click equips club")
	check(world.session.snapshot().inventory.club==1,"Equipping preserves total ownership")
	check(not menu.panel.has_node("BagIcon_club"),"Equipped sole copy leaves bag")
	check(menu.panel.get_node("EquippedClubIcon").position==Vector2(49,118),"Club uses original ARM slot and sprite offset")
	double_click(menu.panel.get_node("EquippedClub"))
	await process_frame
	check(not world.session.snapshot().equipped,"Double-click weapon slot unequips")
	check(menu.panel.has_node("BagIcon_club"),"Unequipped copy returns to bag")
	world.session._profile.inventory.club=2
	double_click(menu.panel.get_node("ItemSlot_club"))
	await process_frame
	check(menu.panel.get_node("BagCount_club").text=="1","Spare copy remains visible")
	double_click(menu.panel.get_node("ItemSlot_club"))
	await process_frame
	check(world.session.snapshot().equipped,"Double-click spare does not unequip active weapon")
	world.session._profile.player.level=2
	world.session._profile.player.allocated_stats.vitality=3
	menu.open_menu("status")
	check(not menu.panel.get_node("Allocate_vitality").visible,"No remaining points hides UP buttons")
	world.session._profile.player.allocated_stats.vitality=2
	menu.rebuild()
	check(menu.panel.get_node("Allocate_vitality").visible,"Remaining point shows UP buttons")
	check(menu.panel.get_node("Allocate_vitality").position==Vector2(110,289),"Original UP position includes ADRN offsets")
	check(menu.panel.get_node("Allocate_dexterity").position==Vector2(230,309),"Original second row advances exactly20 pixels")
	# menu.cpp:11754: the face at (209,118) less its ADRN offset (-32,-36); 魅力 row.
	var face: TextureRect=menu.panel.get_node("StatusFace")
	check(face.position==Vector2(177,82) and face.texture!=null and face.texture.get_size()==Vector2(64,72),"Status window shows the original character face")
	var charm:=str(world.session.snapshot().player.charm)
	check(menu.panel.get_children().any(func(node):return node is Label and node.text==charm and node.position==Vector2(87,238)),"Status window shows charm in the ninth row")
	await click(menu.panel.get_node("Allocate_vitality"))
	await process_frame
	check(not menu.panel.get_node("Allocate_vitality").visible,"Spending final earned point hides UP buttons")
	world.music.stop();world.effect.stop()
	await create_timer(0.3).timeout
	world.queue_free()
	await process_frame
	await process_frame
	print("INVENTORY UI: ","PASS" if failures==0 else "FAIL")
	quit(1 if failures else 0)
