extends Control
const MapFile = preload("res://scripts/map_file.gd")
## Developer-only whole-map view. Colors come from original automap metadata.
var world: Node
var map_rect := Rect2(30,74,620,570)
var thumbnail: Texture2D
var pois: Array = []
var note: Label
var heading: Label
var list: VBoxContainer
var background: Panel
var map_dimensions := Vector2i.ONE
var current_map := -1
var source_data: Dictionary = {}
var walk_mode := false
var zoom_level := 1.0
var view_rect := Rect2(24,110,800,540)
var base_size := Vector2.ONE
var dragging := false
var drag_start := Vector2.ZERO
var last_pointer := Vector2.ZERO
var dragged := false
var selector: OptionButton
var category := 0
var all_maps := false
var tabs: TabBar
var scope_button: Button
var mode_button: Button
func configure(owner: Node) -> void:world=owner
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	z_index=50
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	background=Panel.new()
	background.show_behind_parent=true
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel",world.box(Color("171d22"),Color("89929c")))
	add_child(background)
	heading=world.text("",20)
	heading.position=Vector2(24,16)
	background.add_child(heading)
	note=world.text("滚轮缩放 · 拖动平移 · 点击地点 · 白：自己  黄：NPC  蓝：出入口",14)
	note.position=Vector2(24,45)
	background.add_child(note)
	var close: Button=world.button("关闭 · Esc",close_map)
	close.position=Vector2(1045,16)
	background.add_child(close)
	selector=OptionButton.new()
	selector.position=Vector2(24,72)
	selector.size=Vector2(320,30)
	var ids: Array=world.world_catalog.navigation_maps()
	ids.sort_custom(func(a,b):return int(a)<int(b))
	for ident in ids:selector.add_item("%s (%s)" % [world.world_catalog.maps[ident].name,ident],int(ident))
	selector.item_selected.connect(func(index:int):browse_map(selector.get_item_id(index)))
	background.add_child(selector)
	mode_button=world.button("DEV 传送",func():walk_mode=not walk_mode; mode_button.text="步行" if walk_mode else "DEV 传送")
	mode_button.position=Vector2(355,72)
	background.add_child(mode_button)
	var recenter: Button=world.button("居中 / 全图",recenter_map)
	recenter.position=Vector2(485,72)
	background.add_child(recenter)
	var encounters:=CheckBox.new()
	encounters.name="DevRandomEncounters"
	encounters.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	encounters.text="随机遇敌"
	encounters.position=Vector2(660,72)
	encounters.button_pressed=world.random_encounters
	encounters.toggled.connect(func(value):world.random_encounters=value)
	background.add_child(encounters)
	tabs=TabBar.new()
	tabs.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
	tabs.add_theme_font_size_override("font_size",16)
	tabs.position=Vector2(855,74)
	tabs.size=Vector2(400,36)
	for title in ["地点","练级点","Lv.1 宠物"]:tabs.add_tab(title)
	tabs.tab_changed.connect(select_category)
	background.add_child(tabs)
	scope_button=world.button("当前地图",func():all_maps=not all_maps;_build_pois())
	scope_button.position=Vector2(870,116)
	background.add_child(scope_button)
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(870,158)
	scroll.size=Vector2(380,492)
	background.add_child(scroll)
	list=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	hide()

func open_map() -> void:
	if world.battle_view.visible or world.paused_input:return
	world.clear_input()
	world.paused_input=true
	if current_map!=int(world.data.map_id):browse_map(int(world.data.map_id))
	show()
	queue_redraw()

func close_map() -> void:
	hide()
	world.paused_input=false
	world.clear_input()

func browse_map(map_id: int) -> void:
	var needed: Array=world.asset_packs.map_packs(map_id)
	if map_id!=int(world.data.map_id) and not world.asset_packs.is_ready(needed):
		world.asset_packs.ensure(needed,func(ok: bool):if ok and visible:browse_map(map_id),"地图")
		return
	current_map=map_id
	source_data=world.data if map_id==int(world.data.map_id) else MapFile.load_map(world.world_catalog.file(map_id))
	selector.select(selector.get_item_index(map_id))
	_build_map()
	heading.text="DEV 地图导航 · %s (%d) · %d × %d" % [world.world_catalog.info(map_id).name,map_id,map_dimensions.x,map_dimensions.y]
	queue_redraw()

func recenter_map() -> void:
	zoom_level=1.0
	map_rect=Rect2(view_rect.position+(view_rect.size-base_size)/2,base_size)
	queue_redraw()

func _build_map() -> void:
	map_dimensions=Vector2i(source_data.width,source_data.height)
	var scale_factor:=minf(view_rect.size.x/map_dimensions.x,view_rect.size.y/map_dimensions.y)
	base_size=Vector2(map_dimensions)*scale_factor
	recenter_map()
	# Rasterize once, retaining one texel per cell for the two full islands.
	# Cap oversized future maps at1600²; zoom/pan only transform this texture.
	var width:=clampi(map_dimensions.x,1,1600)
	var height:=clampi(map_dimensions.y,1,1600)
	var img:=Image.create(width,height,false,Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var colors: Dictionary=source_data.get("map_colors",{})
	var ground: PackedInt32Array=source_data.ground
	for index in range(ground.size()):
		if ground[index]==0:continue
		var x:=int(float(index%map_dimensions.x)*width/map_dimensions.x)
		var y:=int(float(index/map_dimensions.x)*height/map_dimensions.y)
		var rgb: Array=colors.get(str(ground[index]),[48,64,48])
		img.set_pixel(x,y,Color8(int(rgb[0]),int(rgb[1]),int(rgb[2])))
	thumbnail=ImageTexture.create_from_image(img)
	_build_pois()

func select_category(index: int) -> void:
	category=index
	_build_pois()

func _build_pois() -> void:
	pois.clear()
	scope_button.visible=category!=0
	scope_button.text="全部地图" if all_maps else "当前地图"
	if category==0:
		note.text="滚轮缩放 · 拖动平移 · 点击地点 · 白：自己  黄：NPC  蓝：出入口"
		for entry in world.world_catalog.residents:
			if int(entry.map_id)==current_map:pois.append({"name":entry.name,"cell":Vector2i(entry.cell[0],entry.cell[1]),"color":Color.YELLOW,"map_id":current_map})
		if current_map==int(world.data.map_id) and not world.npc_data.is_empty():pois.append({"name":world.npc_data.name,"cell":world.npc_cell,"color":Color.YELLOW,"map_id":current_map})
		var links: Dictionary=world.world_catalog.links(current_map)
		var seen: Dictionary={}
		for cell in links:
			var link: Dictionary=links[cell]
			var key:=str(link.to_map)+":"+str(Vector2i(int(cell.x)/8,int(cell.y)/8))
			if seen.has(key):continue
			seen[key]=true
			pois.append({"name":"→ "+str(world.world_catalog.info(int(link.to_map)).get("name",link.to_map)),"cell":cell,"color":Color.CYAN,"map_id":current_map})
	else:
		note.text="点击地点按所选方式步行 / DEV 传送；遇敌随机，不保证每次出现 Lv.1 宠物。" if category==2 else "点击地点按所选方式步行 / DEV 传送；等级为原始遇敌范围。"
		var file: String="res://data/level-one-spots.json" if category==2 else "res://data/training-spots.json"
		if FileAccess.file_exists(file):
			var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(file))
			for spot in catalog.get("spots",[]):
				var ident:=int(spot.map_id)
				if not world.world_catalog.maps.has(str(ident)) or (not all_maps and ident!=current_map):continue
				var label: String
				if category==2:
					label="%s · 固定 Lv.1"%spot.name if int(spot.level_max)==1 else "%s · 可遇 Lv.1（1–%d）"%[spot.name,int(spot.level_max)]
				else:label="练级 Lv.%d–%d"%[spot.level_min,spot.level_max]
				if all_maps:label+=" · "+str(world.world_catalog.info(ident).name)
				pois.append({"name":label,"cell":Vector2i(spot.cell[0],spot.cell[1]),"color":Color.LIME_GREEN if category==2 else Color.ORANGE,"map_id":ident,"area_id":int(spot.area_id)})
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for poi in pois:
		var button: Button=world.button("%s (%d,%d)" % [poi.name,poi.cell.x,poi.cell.y],func():select_poi(poi))
		button.add_theme_font_size_override("font_size",13)
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size=Vector2(350,36)
		list.add_child(button)
	if pois.is_empty():list.add_child(world.text("这张地图没有可用的此类地点。",14))
	queue_redraw()

func select_poi(poi: Dictionary) -> bool:
	if poi.has("area_id"):
		var point: Vector2i=poi.cell
		var area: Dictionary=world.encounter_catalog.area_at(int(poi.map_id),point)
		if area.is_empty() or int(area.id)!=int(poi.area_id):
			note.text="遇敌区域已改变，请重新生成导航地点。"
			return false
		if world.travel_landing.safe_destination(int(poi.map_id),point)!=point:
			note.text="该遇敌落点已不可用，请选择其他地点。"
			return false
	if int(poi.map_id)!=current_map:browse_map(int(poi.map_id))
	if poi.has("area_id") and nearest_safe(poi.cell)!=poi.cell:
		note.text="该遇敌落点已不可用，请选择其他地点。"
		return false
	return select_target(poi.cell)

func cell_to_point(cell: Vector2i) -> Vector2:
	return map_rect.position+(Vector2(cell)+Vector2.ONE*0.5)/Vector2(map_dimensions)*map_rect.size
func point_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(((point-map_rect.position)/map_rect.size*Vector2(map_dimensions)).floor())
func nearest_safe(target: Vector2i) -> Vector2i:
	var links: Dictionary=world.world_catalog.links(current_map)
	for radius in range(0,33):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(y))!=radius:continue
				var point:=target+Vector2i(x,y)
				if _walkable(point) and not links.has(point):return point
	return Vector2i(-1,-1)
func _walkable(point: Vector2i) -> bool:
	if not Rect2i(Vector2i.ZERO,map_dimensions).has_point(point):return false
	if int(source_data.blocked[point.y*map_dimensions.x+point.x])!=0:return false
	for resident in world.world_catalog.residents:
		if int(resident.map_id)==current_map and point==Vector2i(resident.cell[0],resident.cell[1]):return false
	return not (current_map==int(world.data.map_id) and point==world.npc_cell)

func select_map_point(point: Vector2) -> bool:
	# Markers occupy several tiles at whole-island scale. Select their verified
	# landing, rather than an adjacent tile with a different encounter table.
	var nearest: Dictionary={}
	var distance:=6.0
	for poi in pois:
		if int(poi.get("map_id",current_map))!=current_map:continue
		var marker:=cell_to_point(poi.cell)
		if not view_rect.has_point(marker):continue
		var candidate:=point.distance_to(marker)
		if candidate<distance:
			nearest=poi;distance=candidate
	if not nearest.is_empty():return select_poi(nearest)
	return select_target(point_to_cell(point))

func select_target(target: Vector2i) -> bool:
	if not walk_mode:return teleport_near(target)
	close_map()
	if world.travel_router.request(current_map,target):return true
	note.text=world.travel_router.last_error
	world.paused_input=true
	show()
	return false

func teleport_near(target: Vector2i) -> bool:
	var destination:=nearest_safe(target)
	if destination.x<0:
		note.text="附近没有可站立的地面，请选择其他地点。"
		return false
	world.travel_router.cancel("开发传送取消了步行路线。")
	if current_map!=int(world.data.map_id):
		close_map()
		world.call_deferred("load_area_id",current_map,destination)
		return true
	world.clear_input()
	world.moving=false
	world.cell=destination
	world.target_cell=destination
	world.logical_position=Vector2(destination)
	world.player.position=world.project(Vector2(destination))
	world.player.set_action(3)
	world.camera.reset_smoothing()
	world.marker_cell=Vector2i(-1,-1)
	world.checkpoint()
	world.queue_redraw()
	close_map()
	return true
func zoom_at(pointer: Vector2, multiplier: float) -> void:
	var cell_point: Vector2=(pointer-map_rect.position)/map_rect.size
	zoom_level=clampf(zoom_level*multiplier,1.0,12.0)
	map_rect.size=base_size*zoom_level
	map_rect.position=pointer-cell_point*map_rect.size
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and view_rect.has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position,1.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.8)
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
			if event.pressed and view_rect.has_point(event.position):
				dragging=true
				dragged=false
				drag_start=event.position
				last_pointer=event.position
			elif not event.pressed and dragging:
				dragging=false
				if not dragged and event.button_index==MOUSE_BUTTON_LEFT and map_rect.has_point(event.position) and view_rect.has_point(event.position):select_map_point(event.position)
			accept_event()
	elif event is InputEventMouseMotion and dragging:
		if event.position.distance_to(drag_start)>4:dragged=true
		if dragged:
			map_rect.position+=event.position-last_pointer
			queue_redraw()
		last_pointer=event.position

func _draw() -> void:
	if not visible or not thumbnail:return
	var visible_rect:=map_rect.intersection(view_rect)
	if visible_rect.has_area():
		var texture_rect:=Rect2((visible_rect.position-map_rect.position)/map_rect.size*thumbnail.get_size(),visible_rect.size/map_rect.size*thumbnail.get_size())
		draw_texture_rect_region(thumbnail,visible_rect,texture_rect)
	for poi in pois:
		if int(poi.get("map_id",current_map))!=current_map:continue
		var point:=cell_to_point(poi.cell)
		if view_rect.has_point(point):draw_circle(point,3,poi.color)
	if current_map==int(world.data.map_id) and view_rect.has_point(cell_to_point(world.cell)):draw_circle(cell_to_point(world.cell),5,Color.WHITE)
	draw_rect(view_rect,Color.GRAY,false)
