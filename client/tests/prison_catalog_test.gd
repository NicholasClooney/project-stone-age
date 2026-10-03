extends SceneTree
const Catalog=preload("res://scripts/quest_catalog.gd")
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func projection(c,npc:Dictionary,wanted:Dictionary,label:String)->void:
 var rows:Array=[] if wanted.is_empty() else [wanted]
 var one:Dictionary=c.active_npc(str(npc.id))
 check(one==wanted and c.active_npcs().filter(func(n):return n.id==npc.id)==rows and c.active_npcs_on_map(int(npc.map_id)).filter(func(n):return n.id==npc.id)==rows and c.active_npcs_by_source(str(npc.source_script))==rows,label)
 if not one.is_empty():
  one.prison.money="fake";one.source_fields.WARP="fake";one.cell[0]=-1
  check(c.active_npc(str(npc.id))==wanted,"deep copy "+label)
func run()->void:
 var c=Catalog.new()
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json"))
 var actors:Array=fixture.npcs.filter(func(n):return n.get("kind","")=="original_prison")
 check(actors.size()==5,"exact five prison services")
 var closed:Array=c.enabled_events.filter(func(e):return int(e) not in [48,49,50,51,52])
 check(c.enabled_events.filter(func(e):return int(e) in [48,49,50,51,52])==[48,49,50,51,52],"production enables exact final directory tags")
 for npc in actors:
  var actual:Dictionary=c.npcs.filter(func(n):return n.id==npc.id)[0]
  projection(c,npc,actual,"production enabled "+str(npc.id))
 c.enabled_events=closed
 for npc in actors:projection(c,npc,{},"explicit disabled fixture "+str(npc.id))
 for npc in actors:
  c.npcs=c.npcs.filter(func(n):return n.id!=npc.id);c.npcs.append(npc.duplicate(true))
  for event in [48,49,50,51,52]:
   c.enabled_events=closed+[event]
   projection(c,npc,npc,"tag "+str(event)+" "+str(npc.id))
  for pair in [["source_create","fake"],["source_create_index",999],["map_id",999],["cell",[6.5,5]],["graphic",1],["facing",1],["handler","TimeMan"],["service_id","fake"],["prison_role","guard"],["events",[48]],["branches",[{"enabled":true,"events":[48]}]]]:
   var bad:Dictionary=npc.duplicate(true);bad[pair[0]]=pair[1];c.npcs[-1]=bad
   projection(c,npc,{},"reject "+str(pair[0]))
  for field in ["prison","source_fields"]:
   var bad:Dictionary=npc.duplicate(true);bad[field]["extra"]="fake";c.npcs[-1]=bad
   projection(c,npc,{},"reject extra "+field)
  c.npcs[-1]=npc.duplicate(true);c.npc_overrides[npc.id]={"cell":npc.cell}
  projection(c,npc,{},"reject personal override")
  c.npc_overrides.clear();c.enabled_events=closed
  projection(c,npc,{},"closed again")
 print("PRISON CATALOG: %d failures"%failures)
 quit(1 if failures else 0)
