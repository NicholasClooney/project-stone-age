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
 for id in [20508,20608,20711,20712,20001,21103]:
  if not catalog.info(id).is_empty():
   print("FAIL: unconnected/service map %d must remain excluded" % id)
   failures+=1
 quit(1 if failures else 0)
