extends SceneTree
const Catalog=preload("res://scripts/quest_catalog.gd")
var failures:=0
const ID="777/ten.arg@32021:31:28"
func _initialize()->void:call_deferred("run")
func check(ok:bool,note:String)->void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func check_projection(c,expected:Dictionary,label:String)->void:
 var one:Dictionary=c.active_npc(ID)
 var whole:Array=c.active_npcs().filter(func(n):return str(n.id)==ID)
 var by_map:Array=c.active_npcs_on_map(32021).filter(func(n):return str(n.id)==ID)
 var by_source:Array=c.active_npcs_by_source("777/ten.arg")
 var rows:Array=[] if expected.is_empty() else [expected]
 check(one==expected and whole==rows and by_map==rows and by_source==rows,label+" four readers exact equal")
 if not one.is_empty():
  one.transmigration.rounds[0].texts.mainmsg="mutated"
  whole[0].transmigration.villages[0].presents[0]=-1
  by_map[0].cell[0]=-1;by_source[0].transmigration.maxmsg="mutated"
  check(c.active_npc(ID)==expected,label+" nested projection deep copy")
func run()->void:
 var c=Catalog.new()
 check(c.enabled_events.filter(func(e):return int(e) in [48,49,50,51,52])==[48,49,50,51,52],"production enables exact final directory tags")
 check_projection(c,c.npcs.filter(func(n):return str(n.id)==ID)[0],"production enabled original king")
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-final-source.json"))
 var king:Dictionary=fixture.npcs.filter(func(n):return str(n.id)==ID)[0]
 c.npcs=c.npcs.filter(func(n):return str(n.id)!=ID)
 c.npcs.append(king.duplicate(true))
 var original:Array=c.enabled_events.filter(func(e):return int(e) not in [48,49,50,51,52])
 c.enabled_events=original
 check_projection(c,{},"explicit source fixture with final events closed")
 for event in [48,49,50,51,52]:
  c.enabled_events=original+[event]
  check_projection(c,king,"explicit isolated label "+str(event))
 c.enabled_events=original+[48,49,50,51,52]
 for pair in [["source_script","777.old/ten.arg"],["source_create_index",6],["map_id",32020],["cell",[31,29]],["graphic",100443],["facing",0],["kind","fake_service"],["handler","TimeMan"],["service_id","other"],["events",[48]],["branches",[{"enabled":true,"events":[48],"type":"MESSAGE"}]]]:
  var bad:Dictionary=king.duplicate(true);bad[pair[0]]=pair[1]
  c.npcs[-1]=bad
  check_projection(c,{},"reject changed "+str(pair[0]))
 c.npcs[-1]=king.duplicate(true)
 c.npc_overrides[ID]={"map_id":32021,"cell":[31,28]}
 check_projection(c,{},"no personal relocation of original service")
 c.npc_overrides.clear();c.enabled_events=original
 check_projection(c,{},"closed again after prior enable")
 check(c.npcs[-1]==king,"source record unchanged")
 print("TRANSMIGRATION FINAL CATALOG: %d failures"%failures)
 quit(1 if failures else 0)
