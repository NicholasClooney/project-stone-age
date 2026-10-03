extends SceneTree
var failures:=0
func check(ok:bool,note:String):
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/main.tscn").instantiate()
 game.profile_persistence=false;root.add_child(game);await process_frame
 var catalog=game.world_catalog
 check(catalog.residents.any(func(n):return int(n.map_id)==1000 and n.role=="resident") and catalog.residents.any(func(n):return int(n.map_id)==10202 and n.role=="gate"),"existing Samgir residents and tunnel guards retained")
 var frozen:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dana-public-actors.json"))
 for id in [5100,5101,5103,5105,5106]:
  check(game.dev_visit(id),"Dana map loads %d"%id)
  await process_frame
  var travel=game.world_travel
  var expected:Array=frozen.actors.filter(func(n):return int(n.map_id)==id)
  var actual:Array=[]
  for n in travel.entries:
   var entry:Dictionary={}
   for field in ["map_id","cell","name","graphic","facing","role"]:entry[field]=n.get(field)
   if str(n.role)=="quest":entry.id=n.id
   actual.append(entry)
  var order:Callable=func(a,b):return str(a.cell)<str(b.cell)
  actual.sort_custom(order);expected.sort_custom(order)
  check(actual==expected,"exact original Dana actors plus reviewed fire NPC map%d"%id)
  check(travel.sprites.all(func(s):return s.texture!=null),"all original NPC graphics available map%d"%id)
  if id==5100:
   travel.approach(0)
   check(travel.pending==0,"airline guide can be approached from village arrival")
   for step in range(150):
    game._physics_process(0.25)
    await process_frame
    if travel.overlay.visible:break
   check(travel.overlay.visible and travel.body.text.contains("加美航空"),"walking to guide opens original dialogue")
   travel._close()
  for i in range(travel.entries.size()):
   var npc:Dictionary=travel.entries[i]
   var cell:=Vector2i(npc.cell[0],npc.cell[1])
   check(not game.is_walkable(cell),"NPC occupancy blocks walking "+str(npc.name))
   if npc.role=="decoration":continue
   var before:Dictionary=game.session.snapshot()
   travel.selected=i;travel._open()
   if npc.role=="deferred_service":
    check(travel.body.text.contains("尚未还原") and not travel.choice.visible,"unsupported service clearly inert "+str(npc.name))
   elif npc.role=="resident":
    check(npc.dialogues.any(func(line):return travel.body.text.ends_with(str(line))),"dialogue selected from original lines "+str(npc.name))
   elif npc.role=="sign":check(travel.body.text.contains("1000s"),"original airline sign text retained")
   travel._close()
   check(game.session.snapshot()==before,"NPC inspection grants no items currency quests "+str(npc.name))
  game.dev_map_overview.open_map()
  check(game.dev_map_overview.pois.any(func(p):return str(p.name)==str(travel.entries[0].name)),"Dana NPC visible in navigation map%d"%id)
  game.dev_map_overview.close_map()
 game.music.stop();game.effect.stop();game.queue_free();await process_frame;await create_timer(0.3).timeout
 print("DANA NPCS: %d failures"%failures);quit(1 if failures else 0)
