extends "res://tests/brothers_golden_quests_test.gd"
const Policy=preload("res://server/quest_arrival_policy.gd")
const KING="777/ten.arg@32021:31:28"
const Service=preload("res://server/transmigration_service.gd")
var cases:Array=[]
func audit(b,label:String)->void:
 for n in b.quest_catalog.active_npcs():
  b.automation.position_changed(int(n.map_id),Vector2i(int(n.cell[0])+1,int(n.cell[1])))
  if str(n.id)==KING:
   check(Policy.context_service(n) and Policy.scope(int(n.map_id))=="transmigration" and Policy.action_marks(n,{})==["transmigration_king"],"exact active king binds reviewed scope and final-room mark")
   var before:Dictionary=b.session.snapshot()
   var result:Dictionary=b.handle({"type":"transmigration","action":"preview","npc_id":KING,"pet_ids":[]})
   check(not result.get("ok",false) and str(result.get("reason","")).begins_with("项目补充") and b.session.snapshot()==before,"real king service rejects project arrival without profile mutation")
   check(b.quest_arrival.action_context(b,n,{},"SERVICE").is_empty(),"project arrival cannot mint king service receipt")
   cases.append({"catalog":label,"npc":n.id,"map":n.map_id,"scope":Policy.scope(int(n.map_id)),"phase":"SERVICE","marks":Policy.action_marks(n,{})})
   continue
  var branches:Array=n.get("branches",[])
  if str(n.get("kind","")) in ["golden_bui_gate","golden_bui_quiz","golden_bui_janken","original_jug_shop"]:
   branches=[{"type":"SERVICE","event":-1,"condition":"original service private rule","actions":{}}]
  for i in range(branches.size()):
   var branch:Dictionary=branches[i]
   if branch.get("actions",{}).is_empty() and str(branch.type) not in ["REQUEST","SERVICE"]:continue
   if str(branch.type)=="CLEAN":continue # Original cancellation only removes flags.
   var scope:String=Policy.scope(int(n.map_id))
   var before:Dictionary=b.session.snapshot()
   if scope.is_empty() and Policy.action_approach(n).is_empty():
    check(b.quest_arrival.check_action(b,n,branch,"reward").is_empty(),"public original branch adds no arrival predicate "+str(n.id))
   else:
    var result:Dictionary=b.original_quests.transact(b,before,branch,"SERVICE" if str(branch.type)=="SERVICE" else "reward","",str(n.id))
    check(not result.get("ok",false) and str(result.get("reason","")).begins_with("项目补充") and b.session.snapshot()==before,"actual final source transaction rejects project arrival "+str(n.id)+"/"+str(i))
   cases.append({"catalog":label,"npc":n.id,"map":n.map_id,"cell":n.cell,"scope":scope,"branch":branch.duplicate(true),"catalog_index":i,"source":Policy.source(n),"marks":Policy.action_marks(n,branch)})
func run()->void:
 var b=fresh()
 for event in [48,49,50,51,52]:check(event in b.quest_catalog.enabled_events,"approved final-chain catalogue enabled "+str(event))
 check(47 not in b.quest_catalog.enabled_events and 53 not in b.quest_catalog.enabled_events,"unapproved master and END53 reward remain inactive")
 check(not b.original_quests.npc_by_id(KING).is_empty(),"production catalogue contains exact reviewed king service")
 audit(b,"baseline active catalogue")
 b.free()
 # Explicit isolated closure preserves the old rejection test without reverting
 # the approved production descriptor or equating policy existence with activation.
 b=fresh()
 b.quest_catalog.enabled_events=b.quest_catalog.enabled_events.filter(func(event):return event not in [48,49,50,51,52])
 check(b.original_quests.npc_by_id(KING).is_empty(),"explicit closed catalogue hides king")
 var before:Dictionary=b.session.snapshot()
 for action in ["preview","confirm","cancel"]:
  var denied:Dictionary=b.handle({"type":"transmigration","action":action,"npc_id":KING})
  check(not denied.get("ok",false) and denied.get("reason","")==Service.CLOSED and b.session.snapshot()==before,"explicit closed service rejects "+action+" without mutation")
 audit(b,"explicit final-chain closed catalogue")
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
