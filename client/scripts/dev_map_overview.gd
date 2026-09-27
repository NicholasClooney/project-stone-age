extends Control
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
	note=world.text("点击地图或地点传送 · 白：自己  黄：NPC  蓝：出入口",14)
	note.position=Vector2(24,45)
	background.add_child(note)
	var close: Button=world.button("关闭 · Esc",close_map)
	close.position=Vector2(1045,16)
	background.add_child(close)
	var scroll:=ScrollContainer.new()
	scroll.position=Vector2(870,80)
	scroll.size=Vector2(380,570)
	background.add_child(scroll)
	list=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	hide()

func open_map() -> void:
	if world.battle_view.visible or world.paused_input:return
	world.clear_input()
	world.paused_input=true
	if current_map!=int(world.data.map_id):_build_map()
	heading.text="DEV 全图 · %s (%d) · %d × %d" % [world.area_name(),world.data.map_id,map_dimensions.x,map_dimensions.y]
	show()
	queue_redraw()

func close_map() -> void:
	hide()
	world.paused_input=false
	world.clear_input()

func _build_map() -> void:
	current_map=int(world.data.map_id)
	map_dimensions=Vector2i(world.data.width,world.data.height)
	var scale_factor:=minf(800.0/map_dimensions.x,570.0/map_dimensions.y)
	map_rect=Rect2(Vector2(24,80),Vector2(map_dimensions)*scale_factor)
	# Rasterize at most800×570, once per map. No million-cell per-frame drawing.
	var width:=maxi(1,int(map_rect.size.x))
	var height:=maxi(1,int(map_rect.size.y))
	var img:=Image.create(width,height,false,Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var colors: Dictionary=world.data.get("map_colors",{})
	for entry in world.data.ground:
		var x:=int(float(entry[0])*width/map_dimensions.x)
		var y:=int(float(entry[1])*height/map_dimensions.y)
		var rgb: Array=colors.get(str(int(entry[2])),[48,64,48])
		img.set_pixel(x,y,Color8(int(rgb[0]),int(rgb[1]),int(rgb[2])))
	# Upsampled smallmaps need solid cell rectangles rather than isolated points.
	if width>map_dimensions.x or height>map_dimensions.y:
		var small:=Image.create(map_dimensions.x,map_dimensions.y,false,Image.FORMAT_RGB8)
		small.fill(Color.BLACK)
		for entry in world.data.ground:
			var rgb: Array=colors.get(str(int(entry[2])),[48,64,48])
			small.set_pixel(int(entry[0]),int(entry[1]),Color8(int(rgb[0]),int(rgb[1]),int(rgb[2])))
		small.resize(width,height,Image.INTERPOLATE_NEAREST)
		img=small
	thumbnail=ImageTexture.create_from_image(img)
	pois.clear()
	for entry in world.world_catalog.residents:
		if int(entry.map_id)==current_map:pois.append({"name":entry.name,"cell":Vector2i(entry.cell[0],entry.cell[1]),"color":Color.YELLOW})
	if not world.npc_data.is_empty():pois.append({"name":world.npc_data.name,"cell":world.npc_cell,"color":Color.YELLOW})
	var links: Dictionary=world.world_catalog.links(current_map)
	var seen: Dictionary={}
	for cell in links:
		var link: Dictionary=links[cell]
		var key:=str(link.to_map)+":"+str(Vector2i(int(cell.x)/8,int(cell.y)/8))
		if seen.has(key):continue
		seen[key]=true
		pois.append({"name":"→ "+str(world.world_catalog.info(int(link.to_map)).get("name",link.to_map)),"cell":cell,"color":Color.CYAN})
	for child in list.get_children():child.queue_free()
	for poi in pois:
		var button: Button=world.button("%s (%d,%d)" % [poi.name,poi.cell.x,poi.cell.y],func():teleport_near(poi.cell))
		button.add_theme_font_size_override("font_size",13)
		list.add_child(button)

func cell_to_point(cell: Vector2i) -> Vector2:
	return map_rect.position+(Vector2(cell)+Vector2.ONE*0.5)/Vector2(map_dimensions)*map_rect.size
func point_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(((point-map_rect.position)/map_rect.size*Vector2(map_dimensions)).floor())
func nearest_safe(target: Vector2i) -> Vector2i:
	var links: Dictionary=world.world_catalog.links(int(world.data.map_id))
	for radius in range(0,33):
		for y in range(-radius,radius+1):
			for x in range(-radius,radius+1):
				if maxi(absi(x),absi(y))!=radius:continue
				var point:=target+Vector2i(x,y)
				if world.is_walkable(point) and not links.has(point):return point
	return Vector2i(-1,-1)
func teleport_near(target: Vector2i) -> bool:
	var destination:=nearest_safe(target)
	if destination.x<0:
		note.text="附近没有可站立的地面，请选择其他地点。"
		return false
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
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and map_rect.has_point(event.position):
		teleport_near(point_to_cell(event.position))
		accept_event()
func _draw() -> void:
	if not visible or not thumbnail:return
	draw_texture_rect(thumbnail,map_rect,false)
	for poi in pois:draw_circle(cell_to_point(poi.cell),3,poi.color)
	draw_circle(cell_to_point(world.cell),5,Color.WHITE)
	draw_rect(map_rect,Color.GRAY,false)
