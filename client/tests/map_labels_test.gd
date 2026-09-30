extends SceneTree
## 地图导航 names every marker: exits (manifest portals and the not yet
## imported caves/mountains), NPCs and Lv.1 pet areas, visible without zooming.
const Encyclopedia = preload("res://scripts/pet_encyclopedia.gd")
var failures:=0
func check(ok: bool,note: String):
	print(("PASS: " if ok else "FAIL: ")+note)
	if not ok:failures+=1
func _initialize():call_deferred("run")

func texts(menu,kind: String) -> Array:
	return menu.map_labels.filter(func(entry):return entry.kind==kind).map(func(entry):return str(entry.node.text))

func find_label(menu,kind: String,part: String) -> Dictionary:
	for entry in menu.map_labels:
		if entry.kind==kind and str(entry.node.text).contains(part):return entry
	return {}

func click(menu,point: Vector2) -> void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		event.position=point
		menu._gui_input(event)

func run():
	# Pure helpers.
	check(preload("res://scripts/dev_map_overview.gd").short_place_name("阿布的洞窟地下１楼")=="阿布的洞窟","floor suffix trimmed from cave names")
	check(preload("res://scripts/dev_map_overview.gd").short_place_name("地下１楼")=="洞窟 地下１楼","a cave named only by its floor stays readable")
	check(preload("res://scripts/dev_map_overview.gd").pet_names_text(["甲","乙","丙","丁","戊"])=="甲、乙、丙 等5种","long pet lists are capped")
	var game=load("res://scenes/main.tscn").instantiate()
	game.profile_persistence=false;root.add_child(game)
	await process_frame
	game.random_encounters=false
	var book=Encyclopedia.shared(game.encounter_catalog.data,game.world_catalog.maps)
	var giru: Array=book.level_one_areas(300)
	check(giru.any(func(area):return area.names.has("邦奇诺")),"encyclopedia lists a Lv.1 邦奇诺 area on 吉鲁岛")
	var menu=game.dev_map_overview
	menu.open_map();menu.walk_mode=false
	menu.browse_map(100);menu.select_category(0)
	check(menu.zoom_level==1.0,"whole island at zoom 1")
	var places: Array=texts(menu,"place")
	for town in ["萨姆吉尔村","玛丽娜丝渔村","柯奥村","霍特尔村","卡坦村"]:
		check(places.has(town),"萨伊那斯 labels the exit to "+town)
	var closed: Array=texts(menu,"closed")
	check(closed.has("阿布的洞窟") and closed.has("柯奥山的小洞窟"),"not yet imported caves are labelled from their original floor names: %s"%[closed])
	check(texts(menu,"pet").any(func(text):return text.ends_with(" Lv1")),"萨伊那斯 has Lv.1 pet area labels")
	check(not menu.pet_rects.is_empty(),"Lv.1 pet areas are outlined")
	var shown: Array=menu.map_labels.filter(func(entry):return entry.node.visible)
	check(shown.size()==menu.map_labels.size() and menu.map_labels.size()>=places.size(),"every label shows without zooming (%d)"%shown.size())
	var overlaps:=0
	for i in range(shown.size()):
		for j in range(i+1,shown.size()):
			if Rect2(shown[i].node.position,shown[i].node.size).grow(-1).intersects(Rect2(shown[j].node.position,shown[j].node.size).grow(-1)):overlaps+=1
	check(overlaps==0,"labels are nudged apart on 萨伊那斯 (%d overlaps)"%overlaps)
	var built: Array=menu.map_labels.map(func(entry):return entry.node)
	menu.zoom_at(menu.view_rect.get_center(),2.0)
	check(menu.map_labels.map(func(entry):return entry.node)==built,"zooming moves the labels without rebuilding them")
	menu.recenter_map()
	menu.browse_map(300)
	var bangino: Dictionary=find_label(menu,"pet","邦奇诺")
	check(not bangino.is_empty() and str(bangino.node.text).ends_with(" Lv1") and bangino.node.visible,"吉鲁岛 shows 「邦奇诺 … Lv1」 without zooming")
	check(texts(menu,"place").has("福尔德村") and texts(menu,"place").has("达那村"),"吉鲁岛 labels its village exits")
	menu.close_map()
	# Clicking a name travels to its marker (DEV teleport on the same map).
	var spawn: Array=game.world_catalog.info(300).spawn
	game.load_area_id(300,Vector2i(spawn[0],spawn[1]))
	await process_frame;await process_frame
	menu=game.dev_map_overview
	menu.open_map();menu.walk_mode=false;menu.select_category(0)
	bangino=find_label(menu,"pet","邦奇诺")
	var node: Label=bangino.node
	click(menu,menu.view_rect.position+node.position+node.size*Vector2(0.8,0.5))
	var target: Vector2i=bangino.poi.cell
	check(not menu.visible and game.cell==target,"clicking the 邦奇诺 name teleports to its verified landing %s (at %s)"%[target,game.cell])
	menu.open_map();menu.walk_mode=false;menu.select_category(0)
	var village: Dictionary=find_label(menu,"place","福尔德村")
	click(menu,menu.cell_to_point(village.cell))
	check(not menu.visible and game.cell.distance_to(village.cell)<3,"clicking a place dot still travels beside it (%s)"%game.cell)
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.music.stop();game.effect.stop();game.queue_free()
	await process_frame;await create_timer(0.3).timeout
	print("MAP LABELS: %d failures"%failures)
	quit(1 if failures else 0)
