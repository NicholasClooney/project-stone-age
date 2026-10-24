extends Control
const Clock=preload("res://scripts/clock.gd")
const MapFile = preload("res://scripts/map_file.gd")
## Developer-only whole-map view. Colors come from original automap metadata.
## Every marker carries a name label (Label nodes built once per map/tab and
## only moved on zoom/pan): places (exits, towns, caves) in white, NPCs in
## yellow, Lv.1 pet areas in green, training spots in orange.
const Encyclopedia = preload("res://scripts/pet_encyclopedia.gd")
const PLACE_COLOR := Color.WHITE
const CLOSED_COLOR := Color("aeb6bf")
const NPC_COLOR := Color("ffe45c")
const PET_COLOR := Color("6dff7c")
## Lv.1 pet spots this project added (data/rare-encounters.json: 补充 / 非原版).
const ADDED_PET_COLOR := Color("c58cff")
const TRAINING_COLOR := Color.ORANGE
## Label order per marker kind: earlier kinds get the uncluttered spot when
## labels would overlap.
const KIND_ORDER := ["place","pet","pet_added","closed","training","npc"]
const LABEL_NAMES_MAX := 3
## Exits with the same name closer than this (cells) share one marker.
const EXIT_MERGE := 12
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
## Clipped layer over view_rect holding one Label per marker group.
var label_layer: Control
## [{node: Label, poi: first poi of the group, cell, kind}] of the current map.
var map_labels: Array = []
var label_styles: Dictionary = {}
## Encounter rects (Rect2i, inclusive cells) of the Lv.1 pet areas shown.
var pet_rects: Array = []
## Areas with added (补充 / 非原版) Lv.1 pets, outlined in ADDED_PET_COLOR.
var added_pet_rects: Array = []
var legend: RichTextLabel
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
	note=world.text("滚轮缩放 · 拖动平移 · 点击标记或名字前往",14)
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
	var font: Font=load("res://assets/fonts/NotoSansSC.ttf")
	for kind in KIND_ORDER:
		var style:=LabelSettings.new()
		style.font=font
		style.font_size=12
		style.font_color={"place":PLACE_COLOR,"closed":CLOSED_COLOR,"npc":NPC_COLOR,"pet":PET_COLOR,"pet_added":ADDED_PET_COLOR,"training":TRAINING_COLOR}[kind]
		style.outline_size=4
		style.outline_color=Color(0,0,0,0.9)
		label_styles[kind]=style
	label_layer=Control.new()
	label_layer.name="MapLabels"
	label_layer.position=view_rect.position
	label_layer.size=view_rect.size
	label_layer.clip_contents=true
	label_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(label_layer)
	legend=RichTextLabel.new()
	legend.name="MapLegend"
	legend.bbcode_enabled=true
	legend.fit_content=true
	legend.scroll_active=false
	legend.autowrap_mode=TextServer.AUTOWRAP_OFF
	legend.mouse_filter=Control.MOUSE_FILTER_IGNORE
	legend.add_theme_font_override("normal_font",font)
	legend.add_theme_font_size_override("normal_font_size",12)
	legend.text="[bgcolor=#000000b0] [color=#00ffff]●[/color][color=#ffffff] 地点/出入口[/color]  [color=#aeb6bf]● 未开放区域[/color]  [color=#6dff7c]◆ Lv.1 宠物[/color]  [color=#c58cff]◆ 补充/非原版 Lv.1[/color]  [color=#ffe45c]● NPC[/color]  [color=#ffa500]● 练级点[/color]  [color=#ffffff]◉ 自己[/color] [/bgcolor]"
	legend.position=view_rect.position+Vector2(6,view_rect.size.y-26)
	legend.size=Vector2(view_rect.size.x-12,22)
	add_child(legend)
	hide()

func open_map() -> void:
	_cancel_project_wait()
	if world.battle_view.visible or world.paused_input:return
	world.clear_input()
	world.paused_input=true
	if current_map!=int(world.data.map_id):browse_map(int(world.data.map_id))
	show()
	queue_redraw()

func close_map() -> void:
	_cancel_project_wait()
	hide()
	world.paused_input=false
	world.clear_input()

func browse_map(map_id: int) -> void:
	_cancel_project_wait()
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
	_layout_labels()
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
	pet_rects.clear()
	added_pet_rects.clear()
	scope_button.visible=category!=0
	scope_button.text="全部地图" if all_maps else "当前地图"
	if category==0:
		note.text="滚轮缩放 · 拖动平移 · 点击标记或名字前往"
		for entry in world.world_catalog.residents:
			if int(entry.map_id)==current_map:pois.append({"name":entry.name,"cell":Vector2i(entry.cell[0],entry.cell[1]),"color":NPC_COLOR,"map_id":current_map,"kind":"npc","tag":str(entry.name)})
		if current_map==int(world.data.map_id) and not world.npc_data.is_empty():pois.append({"name":world.npc_data.name,"cell":world.npc_cell,"color":NPC_COLOR,"map_id":current_map,"kind":"npc","tag":str(world.npc_data.name)})
		var exits: Array=[]
		var links: Dictionary=world.world_catalog.links(current_map)
		for cell in links:exits.append({"cell":cell,"to_map":int(links[cell].to_map),"open":true})
		for link in world.world_catalog.unsupported_exits(current_map):
			var cell:=Vector2i(int(link.cell[0]),int(link.cell[1]))
			if not links.has(cell):exits.append({"cell":cell,"to_map":int(link.to_map),"open":false})
		var kept: Array=[]
		for exit in exits:
			var title:=short_place_name(world.world_catalog.map_name(exit.to_map))
			if kept.any(func(other):return other.title==title and maxi(absi(other.cell.x-exit.cell.x),absi(other.cell.y-exit.cell.y))<EXIT_MERGE):continue
			exit.title=title
			kept.append(exit)
			if exit.open:pois.append({"name":"→ "+title,"cell":exit.cell,"color":Color.CYAN,"map_id":current_map,"kind":"place","tag":title})
			else:pois.append({"name":"→ %s（未开放）"%title,"cell":exit.cell,"color":CLOSED_COLOR,"map_id":current_map,"kind":"closed","tag":title})
		_add_level_one_areas()
	else:
		note.text="点击地点按所选方式步行 / DEV 传送；遇敌随机，不保证每次出现 Lv.1 宠物。" if category==2 else "点击地点按所选方式步行 / DEV 传送；等级为原始遇敌范围。"
		var file: String="res://data/level-one-spots.json" if category==2 else "res://data/training-spots.json"
		if FileAccess.file_exists(file):
			var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(file))
			for spot in catalog.get("spots",[]):
				var ident:=int(spot.map_id)
				if not world.world_catalog.maps.has(str(ident)) or (not all_maps and ident!=current_map):continue
				var label: String
				var tag: String
				if category==2:
					label="%s · 固定 Lv.1"%spot.name if int(spot.level_max)==1 else "%s · 可遇 Lv.1（1–%d）"%[spot.name,int(spot.level_max)]
					tag=str(spot.name)
					# Rows added by data/rare-encounters.json (tools/import_encounters.py).
					match str(spot.get("origin","")):
						"original_area":label+=" · 补充"
						"added":label+=" · 非原版"
				else:
					label="练级 Lv.%d–%d"%[spot.level_min,spot.level_max]
					tag=label
				if all_maps:label+=" · "+str(world.world_catalog.info(ident).name)
				pois.append({"name":label,"cell":Vector2i(spot.cell[0],spot.cell[1]),"color":(ADDED_PET_COLOR if spot.has("origin") else PET_COLOR) if category==2 else TRAINING_COLOR,"map_id":ident,"area_id":int(spot.area_id),"kind":("pet_added" if spot.has("origin") else "pet") if category==2 else "training","tag":tag})
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
	_build_labels()
	queue_redraw()

## 阿布的洞窟地下１楼 -> 阿布的洞窟: the floor suffix only lengthens a map label.
## Destinations are exits' entry floors, so the floor adds nothing.
static func short_place_name(name: String) -> String:
	var pattern:=RegEx.create_from_string("(地下)?[0-9０-９]+[楼樓]$")
	var short:=pattern.sub(name,"")
	# Two Giru dungeons name their floors only (地下１楼).
	return short if not short.is_empty() else "洞窟 "+name

## Lv.1 pet areas of the current map, from the pet encyclopedia's wild
## locations (the same rows as 野外出现地点). A verified landing cell makes
## the marker a checked encounter destination; otherwise it sits at the
## area's centre and travels like any map point.
func _add_level_one_areas() -> void:
	var rects: Dictionary={}
	for area in world.encounter_catalog.data.get("areas",[]):
		if int(area.map_id)==current_map:rects[int(area.id)]=area.rect
	var book=Encyclopedia.shared(world.encounter_catalog.data,world.world_catalog.maps)
	for spot in book.level_one_areas(current_map):
		var r: Array=rects.get(int(spot.area_id),[])
		if r.size()!=4:continue
		var rect:=Rect2i(int(r[0]),int(r[1]),int(r[2])-int(r[0])+1,int(r[3])-int(r[1])+1)
		(added_pet_rects if spot.added else pet_rects).append(rect)
		var names:=pet_names_text(spot.names)
		var poi:={"name":("Lv.1 宠物（补充/非原版）：%s" if spot.added else "Lv.1 宠物：%s")%"、".join(spot.names),"color":ADDED_PET_COLOR if spot.added else PET_COLOR,"map_id":current_map,"kind":"pet_added" if spot.added else "pet","tag":names,"area_names":spot.names}
		if spot.cell.size()==2:
			poi.cell=Vector2i(int(spot.cell[0]),int(spot.cell[1]))
			poi.area_id=int(spot.area_id)
		else:poi.cell=rect.position+rect.size/2
		pois.append(poi)

## 邦奇诺、乌力、… 等5种: at most LABEL_NAMES_MAX names on the map.
static func pet_names_text(names: Array) -> String:
	if names.size()<=LABEL_NAMES_MAX:return "、".join(names)
	return "%s 等%d种"%["、".join(names.slice(0,LABEL_NAMES_MAX)),names.size()]

## One Label per marker group (same cell and kind) of the current map, built
## when the map or tab changes; zoom and pan only move them.
func _build_labels() -> void:
	for entry in map_labels:entry.node.queue_free()
	map_labels.clear()
	var groups: Dictionary={}
	var ordered: Array=[]
	for poi in pois:
		if int(poi.get("map_id",current_map))!=current_map or not poi.has("tag"):continue
		var key:="%s:%d,%d"%[poi.kind,poi.cell.x,poi.cell.y]
		if not groups.has(key):
			groups[key]={"poi":poi,"cell":poi.cell,"kind":poi.kind,"tags":[]}
			ordered.append(groups[key])
		if not groups[key].tags.has(str(poi.tag)):groups[key].tags.append(str(poi.tag))
	ordered.sort_custom(func(a,b):return KIND_ORDER.find(a.kind)<KIND_ORDER.find(b.kind))
	for group in ordered:
		var text: String
		if group.kind in ["pet","pet_added"]:text=(str(group.tags[0]) if group.poi.has("area_names") else pet_names_text(group.tags))+" Lv1"
		else:text="、".join(group.tags)
		var label:=Label.new()
		label.text=text
		label.label_settings=label_styles[group.kind]
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		label_layer.add_child(label)
		label.size=label.get_minimum_size()
		map_labels.append({"node":label,"poi":group.poi,"cell":group.cell,"kind":group.kind})
	_layout_labels()

## Place each label next to its marker, trying right, left, above, below and
## then stacking downwards until it clears the labels already placed (in
## KIND_ORDER). Runs on zoom/pan only; a few dozen labels per map.
func _layout_labels() -> void:
	if label_layer==null:return
	var placed: Array=[]
	for entry in map_labels:
		var node: Label=entry.node
		var anchor:=cell_to_point(entry.cell)-view_rect.position
		node.visible=Rect2(Vector2.ZERO,view_rect.size).has_point(anchor)
		if not node.visible:continue
		var size:=node.size
		var candidates:=[anchor+Vector2(5,-size.y/2),anchor+Vector2(-5-size.x,-size.y/2),anchor+Vector2(-size.x/2,-size.y-3),anchor+Vector2(-size.x/2,3)]
		for step in range(1,6):candidates.append(anchor+Vector2(5,-size.y/2+step*(size.y-2)))
		for step in range(1,4):candidates.append(anchor+Vector2(5,-size.y/2-step*(size.y-2)))
		var chosen: Vector2=candidates[0]
		for candidate in candidates:
			var box:=Rect2(candidate,size).grow(-1)
			if not placed.any(func(other):return other.intersects(box)):
				chosen=candidate
				break
		node.position=chosen.round()
		placed.append(Rect2(node.position,size))

func select_poi(poi: Dictionary) -> bool:
	# A web client has only the maps it downloaded: the landing check reads
	# the target map's file, so its packs come first (as in 宠物大全).
	var needed: Array=world.area_packs(int(poi.map_id))
	if not world.asset_packs.is_ready(needed):
		note.text="正在下载地图 %s…"%world.world_catalog.map_name(int(poi.map_id))
		_select_after_download(poi,needed)
		return true
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

func _select_after_download(poi: Dictionary, needed: Array) -> void:
	var ok: bool=await world.await_packs(needed,"地图 %s"%world.world_catalog.map_name(int(poi.map_id)))
	if not ok:
		note.text="地图素材下载失败，请稍后再试。"
		return
	select_poi(poi)

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
	# A name selects its marker too.
	for entry in map_labels:
		var node: Label=entry.node
		if node.visible and Rect2(node.position+view_rect.position,node.size).has_point(point):return select_poi(entry.poi)
	return select_target(point_to_cell(point))

func select_target(target: Vector2i) -> bool:
	if not walk_mode:return teleport_near(target)
	close_map()
	if world.travel_router.request(current_map,target):return true
	note.text=world.travel_router.last_error
	world.paused_input=true
	show()
	return false

var _project_travel_pending:=false
var _project_travel_ticket:=0
func _cancel_project_wait()->void:
	_project_travel_ticket+=1
	_project_travel_pending=false

func teleport_near(target: Vector2i) -> bool:
	if _project_travel_pending:return false
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
	_project_travel_pending=true
	_project_travel_ticket+=1
	var ticket:=_project_travel_ticket
	var requested_map:=current_map
	var reply:Dictionary=world.link.request({"type":"project_position","map_id":requested_map,"cell":[destination.x,destination.y]},func(result:Dictionary):_finish_project_move(result,requested_map,destination,ticket))
	return bool(reply.get("ok",false)) or bool(reply.get("pending",false))

func _project_wait_valid(ticket:int)->bool:
	return ticket==_project_travel_ticket and not is_queued_for_deletion() and is_instance_valid(world) and not world.is_queued_for_deletion() and is_instance_valid(note) and not note.is_queued_for_deletion()

func _finish_project_move(reply:Dictionary,map_id:int,destination:Vector2i,ticket:int)->void:
	if not _project_wait_valid(ticket):return
	if not bool(reply.get("ok",false)):
		_project_travel_pending=false
		note.text=str(reply.get("reason","服务器拒绝项目移动。"))
		world.message.text=note.text
		return
	var expected:Array=[map_id,destination]
	var deadline:int=Clock.ticks_msec()+30000
	while _project_wait_valid(ticket):
		# A newer authority event supersedes this request even while its
		# earlier map/scene transition is still settling.
		var incoming:Array=world._follow
		if not incoming.is_empty() and incoming!=expected:
			_project_travel_pending=false
			note.text="另一台设备已移动角色，请重新选择落点。"
			return
		if int(world.data.get("map_id",-1))==map_id and world.cell==destination and not world.moving and not world.area_transition_busy:
			_project_travel_pending=false
			world.checkpoint()
			close_map()
			return
		if (incoming.is_empty() and world._followed!=expected) or Clock.ticks_msec()>deadline:
			_project_travel_pending=false
			note.text="权威位置已改变，请重新选择落点。"
			return
		await get_tree().process_frame

func zoom_at(pointer: Vector2, multiplier: float) -> void:
	var cell_point: Vector2=(pointer-map_rect.position)/map_rect.size
	zoom_level=clampf(zoom_level*multiplier,1.0,12.0)
	map_rect.size=base_size*zoom_level
	map_rect.position=pointer-cell_point*map_rect.size
	_layout_labels()
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
			_layout_labels()
			queue_redraw()
		last_pointer=event.position

func _draw() -> void:
	if not visible or not thumbnail:return
	var visible_rect:=map_rect.intersection(view_rect)
	if visible_rect.has_area():
		var texture_rect:=Rect2((visible_rect.position-map_rect.position)/map_rect.size*thumbnail.get_size(),visible_rect.size/map_rect.size*thumbnail.get_size())
		draw_texture_rect_region(thumbnail,visible_rect,texture_rect)
	for rects in [[pet_rects,PET_COLOR],[added_pet_rects,ADDED_PET_COLOR]]:
		for rect in rects[0]:
			var corner:=map_rect.position+Vector2(rect.position)/Vector2(map_dimensions)*map_rect.size
			var area:=Rect2(corner,Vector2(rect.size)/Vector2(map_dimensions)*map_rect.size).intersection(view_rect)
			if area.has_area():
				draw_rect(area,Color(rects[1],0.08))
				draw_rect(area,Color(rects[1],0.35),false)
	for poi in pois:
		if int(poi.get("map_id",current_map))!=current_map:continue
		var point:=cell_to_point(poi.cell)
		if not view_rect.has_point(point):continue
		if poi.get("kind","") in ["pet","pet_added"]:
			var diamond:=PackedVector2Array([point+Vector2(0,-4),point+Vector2(4,0),point+Vector2(0,4),point+Vector2(-4,0)])
			draw_colored_polygon(diamond,poi.color)
			draw_polyline(diamond+PackedVector2Array([diamond[0]]),Color.BLACK,1)
		else:draw_circle(point,3,poi.color)
	if current_map==int(world.data.map_id) and view_rect.has_point(cell_to_point(world.cell)):draw_circle(cell_to_point(world.cell),5,Color.WHITE)
	draw_rect(view_rect,Color.GRAY,false)
