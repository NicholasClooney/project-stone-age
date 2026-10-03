extends SceneTree
var failures:=0
func _initialize()->void:
 var oracle:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/public-quest-npcs.json"))
 var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/legacy/quests/catalog.json"))
 for identity in oracle.groups["transmigration-final"].npcs:
  var matches:Array=catalog.npcs.filter(func(n):return n.id==identity.id)
  if matches.size()!=1:
   print("FAIL: imported final identity "+str(identity.id));failures+=1;continue
  var path:String="res://assets/legacy/"+str(matches[0].path)
  var texture:Texture2D=load(path) if ResourceLoader.exists(path) else null
  var valid:bool=texture!=null and texture.get_width()>0 and texture.get_height()>0
  print(("PASS: " if valid else "FAIL: ")+"imported original texture resource "+str(identity.id))
  if not valid:failures+=1
 print("TRANSMIGRATION FINAL RESOURCES: %d failures"%failures)
 quit(1 if failures else 0)
