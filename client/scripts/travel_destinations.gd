extends Control
## Metadata-only destination browser; map collision data loads only on travel.
var world: Node
var entries: Array = []
var filtered: Array = []
var search: LineEdit
var category: OptionButton
var destinations: ItemList
var note: Label
var visit_button: Button

func configure(owner: Node) -> void:world=owner
func _ready() -> void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 z_index=60
 var panel:=Panel.new()
 panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 panel.add_theme_stylebox_override("panel",world.box(Color("171d22"),Color("89929c")))
 add_child(panel)
 var title: Label=world.text("DEV 地点传送 · 全部已导入区域",22)
 title.position=Vector2(30,20);panel.add_child(title)
 var close: Button=world.button("关闭 · Esc",close_menu)
 close.position=Vector2(1080,20);panel.add_child(close)
 search=LineEdit.new();search.placeholder_text="搜索地图名、地图编号、村民或出入口"
 search.position=Vector2(30,70);search.size=Vector2(820,40);panel.add_child(search)
 search.text_changed.connect(func(_value):refresh())
 category=OptionButton.new();category.position=Vector2(870,70);category.size=Vector2(350,40)
 for label in ["全部地点","地图落点","村民 / 服务","出入口","刷怪点"]:category.add_item(label)
 category.item_selected.connect(func(_value):refresh());panel.add_child(category)
 destinations=ItemList.new();destinations.position=Vector2(30,125);destinations.size=Vector2(1190,525)
 destinations.add_theme_font_size_override("font_size",17)
 destinations.add_theme_font_override("font",load("res://assets/fonts/NotoSansSC.ttf"))
 destinations.item_selected.connect(func(_index):visit_button.disabled=false)
 destinations.item_activated.connect(func(index):visit_entry(filtered[index]))
 panel.add_child(destinations)
 note=world.text("",15);note.position=Vector2(30,665);note.size=Vector2(1000,65)
 note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_child(note)
 visit_button=world.button("瞬移到选中地点",visit_selected)
 visit_button.position=Vector2(1010,720);panel.add_child(visit_button)
 rebuild_entries();hide()

func rebuild_entries() -> void:
 entries.clear()
 var ids: Array=world.world_catalog.maps.keys()
 ids.sort_custom(func(a,b):return int(a)<int(b))
 for key in ids:
  var map: Dictionary=world.world_catalog.maps[key]
  add_entry(int(key),str(map.get("name",key))+(" [DEV 练级区]" if map.get("dev_only",false) else ""),map.get("spawn",[0,0]),1)
  for resident in world.world_catalog.residents:
   if int(resident.map_id)==int(key):add_entry(int(key),str(resident.name),resident.cell,2)
  var seen: Dictionary={}
  for cell in world.world_catalog.links(int(key)):
   var link: Dictionary=world.world_catalog.links(int(key))[cell]
   # Adjacent door squares share one destination entry.
   var group: String="%s:%s" % [link.to_map,Vector2i(cell.x/4,cell.y/4)]
   if seen.has(group):continue
   seen[group]=true
   var target: Dictionary=world.world_catalog.info(int(link.to_map))
   add_entry(int(key),"出入口 → "+str(target.get("name",link.to_map)),[cell.x,cell.y],3)
 if FileAccess.file_exists("res://data/training-spots.json"):
  var training: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/training-spots.json"))
  for spot in training.get("spots",[]):
   if world.world_catalog.maps.has(str(int(spot.map_id))):add_entry(int(spot.map_id),"练级区 Lv.%d–%d"%[spot.level_min,spot.level_max],spot.cell,4)
 # Two MVP service actors are stored separately from the original residents.
 var services: Array=[]
 if FileAccess.file_exists("res://assets/legacy/samgir-npc.json"):
  var villager: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/samgir-npc.json"))
  if villager is Dictionary:services.append({"map_id":1000,"name":villager.name,"cell":villager.cell})
 if not world.mvp_manifest.is_empty():
  var merchant: Dictionary=world.mvp_manifest.get("merchant",{})
  if not merchant.is_empty():services.append({"map_id":1002,"name":merchant.name,"cell":merchant.cell})
 for service in services:
  var found:=false
  for entry in entries:
   if entry.map_id==int(service.map_id) and entry.cell==Vector2i(service.cell[0],service.cell[1]):found=true
  if not found:add_entry(int(service.map_id),str(service.name),service.cell,2)
 refresh()

func add_entry(map_id: int, label: String, coordinates: Array, kind: int) -> void:
 var map: Dictionary=world.world_catalog.info(map_id)
 var point:=Vector2i(int(coordinates[0]),int(coordinates[1]))
 entries.append({"map_id":map_id,"name":label,"cell":point,"kind":kind,"available":FileAccess.file_exists(world.world_catalog.file(map_id)),"label":"%s · %s (%d) · %d,%d" % [label,map.get("name",map_id),map_id,point.x,point.y]})

func refresh() -> void:
 filtered.clear();destinations.clear()
 var query:=search.text.strip_edges().to_lower()
 for entry in entries:
  if category.selected>0 and entry.kind!=category.selected:continue
  if not query.is_empty() and not str(entry.label).to_lower().contains(query):continue
  filtered.append(entry)
  destinations.add_item(str(entry.label)+("" if entry.available else " · 未导入"))
  destinations.set_item_disabled(destinations.item_count-1,not entry.available)
 visit_button.disabled=true
 note.text="%d 张已登记地图 · %d 个筛选结果。双击可直接传送；自动避开墙壁、NPC 和传送门触发格。尚未导入的原版区域不在可用范围内。" % [world.world_catalog.maps.size(),filtered.size()]

func open_menu() -> void:
 if world.paused_input or world.area_transition_busy or world.battle_view.visible:return
 if is_instance_valid(world.travel_router):world.travel_router.cancel("地点传送取消了自动寻路。")
 world.clear_input();world.paused_input=true
 rebuild_entries();show()
 get_parent().move_child(self,get_parent().get_child_count()-1)
 search.grab_focus()

func close_menu() -> void:
 hide();world.paused_input=false;world.clear_input()

func _input(event: InputEvent) -> void:
 if visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
  close_menu();get_viewport().set_input_as_handled()

func visit_selected() -> void:
 var selected:=destinations.get_selected_items()
 if not selected.is_empty():visit_entry(filtered[selected[0]])

func safe_destination(map_id: int, target: Vector2i) -> Vector2i:
 var filename: String=world.world_catalog.file(map_id)
 if not world.world_catalog.maps.has(str(map_id)) or not FileAccess.file_exists(filename):return Vector2i(-1,-1)
 var data: Variant=world.data if map_id==int(world.data.map_id) else JSON.parse_string(FileAccess.get_file_as_string(filename))
 if not data is Dictionary:return Vector2i(-1,-1)
 var occupied: Dictionary={}
 for resident in world.world_catalog.residents:
  if int(resident.map_id)==map_id:occupied[Vector2i(resident.cell[0],resident.cell[1])]=true
 for entry in entries:
  if entry.kind==2 and entry.map_id==map_id:occupied[entry.cell]=true
 if map_id==int(world.data.map_id):occupied[world.npc_cell]=true
 var links: Dictionary=world.world_catalog.links(map_id)
 var bounds:=Rect2i(0,0,int(data.width),int(data.height))
 for radius in range(33):
  for y in range(-radius,radius+1):
   for x in range(-radius,radius+1):
    if maxi(absi(x),absi(y))!=radius:continue
    var point:=target+Vector2i(x,y)
    if bounds.has_point(point) and int(data.blocked[point.y*int(data.width)+point.x])==0 and not occupied.has(point) and not links.has(point):return point
 return Vector2i(-1,-1)

func visit_entry(entry: Dictionary) -> bool:
 if not visible or world.area_transition_busy or world.battle_view.visible:return false
 if not bool(entry.get("available",false)):return false
 var point:=safe_destination(int(entry.map_id),entry.cell)
 if point.x<0:
  note.text="附近没有安全落点，未传送。";return false
 close_menu()
 if world.load_area_id(int(entry.map_id),point):return true
 world.paused_input=true;show();note.text="地图加载失败，未传送。";return false
