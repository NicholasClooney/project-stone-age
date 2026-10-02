extends SceneTree
const World=preload("res://scripts/world_catalog.gd")
const MapFile=preload("res://scripts/map_file.gd")
const Nav=preload("res://scripts/nav_grid.gd")
var failures:=0
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world=World.new()
 var backend=preload("res://server/backend.gd").new()
 backend.automation.position_changed(122,Vector2i(6,5))
 var gate:Dictionary=backend.quest_helper.destination(backend,backend.original_quests.npc_by_id("genout/wpm_120_19_15@120:19:15"),"near")
 var kaite:Dictionary=backend.quest_helper.destination(backend,backend.original_quests.npc_by_id("extra/event/marju01@119:97:88"),"near")
 var gate_cell:=Vector2i(int(gate.cell[0]),int(gate.cell[1]))
 var kaite_cell:=Vector2i(int(kaite.cell[0]),int(kaite.cell[1]))
 # Original gate warp, inter-floor warps, recipient's adjacent cell, exit.
 for segment in [[120,Vector2i(10,16),gate_cell],[122,Vector2i(6,5),Vector2i(289,168)],[118,Vector2i(232,12),Vector2i(13,8)],[119,Vector2i(96,4),kaite_cell],[119,kaite_cell,Vector2i(103,93)],[121,Vector2i(17,15),Vector2i(10,16)]]:
  var data:Dictionary=MapFile.load_map(world.file(segment[0]))
  check(not data.is_empty(),"actual source map imported %d"%segment[0])
  if data.is_empty():continue
  var grid=Nav.new();grid.region=Rect2i(0,0,int(data.width),int(data.height))
  grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
  grid.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
  grid.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE;grid.update()
  for i in range(data.blocked.size()):
   if int(data.blocked[i])!=0:grid.set_point_solid(Vector2i(i%int(data.width),i/int(data.width)))
  var path:Array=grid.get_id_path(segment[1],segment[2])
  check(not path.is_empty() and path.back()==segment[2],"original collision route %d %s → %s"%[segment[0],segment[1],segment[2]])
 for connection in [[122,Vector2i(289,168),118,[232,12]],[118,Vector2i(13,8),119,[96,4]],[119,Vector2i(103,93),121,[17,15]]]:
  var link:Dictionary=world.links(connection[0]).get(connection[1],{})
  check(int(link.get("to_map",-1))==connection[2] and link.get("target",[]).map(func(v):return int(v))==connection[3],"actual one-way/paired source portal matches")
 check(not world.links(121).values().any(func(portal):return int(portal.to_map)==119),"source exit has no invented reverse route")
 backend.free()
 print("MARJU ROUTE: %d failures"%failures)
 quit(1 if failures else 0)
