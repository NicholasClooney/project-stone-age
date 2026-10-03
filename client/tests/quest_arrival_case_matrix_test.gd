extends "res://tests/brothers_golden_quests_test.gd"
const Policy=preload("res://server/quest_arrival_policy.gd")
var cases:Array=[]
func audit(b,label:String)->void:
 for n in b.quest_catalog.active_npcs():
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  var branches:Array=n.get("branches",[])
  if str(n.get("kind","")) in ["golden_bui_gate","golden_bui_quiz","golden_bui_janken","original_jug_shop"]:
   branches=[{"type":"SERVICE","event":-1,"condition":"original service private rule","actions":{}}]
  for i in range(branches.size()):
   var branch:Dictionary=branches[i]
   if branch.get("actions",{}).is_empty() and str(branch.type) not in ["REQUEST","SERVICE"]:continue
   if str(branch.type)=="CLEAN":continue # Original cancellation only removes flags.
   var scope:String=Policy.scope(int(n.map_id))
   var before:Dictionary=b.session.snapshot()
   if scope.is_empty():
    check(b.quest_arrival.check_action(b,n,branch,"reward").is_empty(),"public original branch adds no arrival predicate "+str(n.id))
   else:
    var result:Dictionary=b.original_quests.transact(b,before,branch,"SERVICE" if str(branch.type)=="SERVICE" else "reward","",str(n.id))
    check(not result.get("ok",false) and str(result.get("reason","")).begins_with("项目补充") and b.session.snapshot()==before,"actual final source transaction rejects project arrival "+str(n.id)+"/"+str(i))
   cases.append({"catalog":label,"npc":n.id,"map":n.map_id,"cell":n.cell,"scope":scope,"branch":branch.duplicate(true),"catalog_index":i,"source":Policy.source(n),"marks":Policy.action_marks(n,branch)})
func run()->void:
 var b=fresh()
 check(not b.quest_catalog.active_npcs().any(func(n):return int(n.map_id) in [32011,32021] or str(n.get("kind",""))=="transmigration"),"planned dark cave/king has no active NPC transaction")
 for event in [47,48,49,50,51,52]:check(event not in b.quest_catalog.enabled_events,"later master/rebirth events remain inactive "+str(event))
 audit(b,"baseline active catalogue")
 b.free()
 for chain in ["earth","fire","water"]:
  b=fresh()
  var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-%s-source.json"%chain))
  var ids:Array=fixture.npcs.map(func(n):return str(n.id))
  b.quest_catalog.npcs=b.quest_catalog.npcs.filter(func(n):return str(n.id) not in ids)
  b.quest_catalog.npcs.append_array(fixture.npcs.duplicate(true));b.quest_catalog.items.merge(fixture.items,true)
  for event in [39,40,46]:
   if event not in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(event)
  audit(b,chain+" isolated locked-source catalogue")
  b.free()
 var path:String=OS.get_environment("STONE_AGE_ARRIVAL_CASE_REPORT")
 if not path.is_empty():
  var file=FileAccess.open(path,FileAccess.WRITE)
  check(file!=null,"audit report writable")
  if file!=null:file.store_string(JSON.stringify(cases,"  "));file.close()
 print("QUEST ARRIVAL CASE MATRIX: %d failures; %d tested branch rows"%[failures,cases.size()]);quit(1 if failures else 0)
