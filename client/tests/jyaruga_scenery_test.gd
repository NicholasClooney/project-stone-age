extends SceneTree
const Catalog = preload("res://scripts/world_catalog.gd")
const Encounters = preload("res://server/encounter_catalog.gd")
func _initialize():
 var catalog = Catalog.new()
 var encounters = Encounters.new()
 var failures := 0
 for id in [20101,20301,20401,20501,20601,20701,20801,20901,21001,21015,21201,21301]:
  var spawn: Array = catalog.info(id).get("spawn",[0,0])
  var original_area: Dictionary = encounters.area_at(id,Vector2i(spawn[0],spawn[1]))
  var ok: bool = not original_area.is_empty() and catalog.info(id).get("kind","")=="dungeon" and catalog.field(id) and not catalog.links(id).is_empty()
  print(("PASS: " if ok else "FAIL: ")+"scenic map %d retains original encounter area, field eligibility and doors" % id)
  if not ok: failures+=1
 var forge_ok: bool = not catalog.info(20508).is_empty() and not catalog.links(20508).is_empty()
 print(("PASS: " if forge_ok else "FAIL:")+"original Hahn forge is now explicitly reviewed and connected")
 if not forge_ok: failures+=1
 # Jan explicitly restores this map; mapwarp.txt:2308 wins over 2310.
 var jan:Dictionary=catalog.links(20607).get(Vector2i(75,13),{})
 var jan_ok:bool=catalog.info(20608).get("path","")=="world/20608.map" and catalog.field(20608) and int(jan.get("to_map",0))==20608 and point(jan.get("target",[-1,-1]))==Vector2i(0,7)
 for point in [Vector2i(0,7),Vector2i(0,8)]:
  var back:Dictionary=catalog.links(20608).get(point,{})
  jan_ok=jan_ok and int(back.get("to_map",0))==20607 and point(back.get("target",[-1,-1]))==Vector2i(75,13)
 print(("PASS: " if jan_ok else "FAIL: ")+"Jan room uses original first-match entrance and both source returns")
 if not jan_ok:failures+=1
 for id in [20711,20712,20001,21103]:
  if not catalog.info(id).is_empty():
   print("FAIL: unconnected/service map %d must remain excluded" % id)
   failures+=1
 quit(1 if failures else 0)

func point(values:Array)->Vector2i:return Vector2i(int(values[0]),int(values[1]))
