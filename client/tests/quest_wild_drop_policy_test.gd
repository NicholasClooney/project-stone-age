extends "res://tests/brothers_golden_quests_test.gd"
const DropPolicy=preload("res://server/quest_wild_drop_policy.gd")
const ArrivalPolicy=preload("res://server/quest_arrival_policy.gd")
func run()->void:
 var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/quest-wild-drop-policy.json"))
 var keys:Dictionary={}
 for row in data.rules:
  var args:Array=[int(row.map),int(row.area),int(row.group),int(row.enemy),int(row.item),int(row.slot)]
  var key:String=str(args)
  check(not keys.has(key),"unique exact tuple "+key);keys[key]=true
  check(DropPolicy.match_rule.callv(args)==row and ArrivalPolicy.scope(int(row.map))==str(row.scope),"reviewed tuple and original scope "+key)
  for field in range(6):
   var wrong:Array=args.duplicate();wrong[field]=-999
   check(DropPolicy.match_rule.callv(wrong).is_empty(),"mismatched source field is not restricted "+str(field))
  var copy:Dictionary=DropPolicy.match_rule.callv(args);copy.scope="forged"
  check(str(DropPolicy.match_rule.callv(args).scope)==str(row.scope),"caller cannot mutate static rule")
 for args in [[200,88,414,563,2468,0],[1099,267,414,563,2468,0],[21206,0,0,1334,1249,0],[10705,0,0,513,2428,0]]:
  check(DropPolicy.match_rule.callv(args).is_empty(),"public/unverified/ordinary/fixed guard excluded "+str(args))
 var b=fresh();var other=fresh()
 var entrance:Dictionary={}
 for link in b.quest_helper.places.links(300).values():
  if int(link.to_map)==31801 and not link.has("gate_source"):entrance=link;break
 check(not entrance.is_empty(),"real miner entrance available")
 if not entrance.is_empty():
  b.automation.position_changed(31801,Vector2i(int(entrance.target[0]),int(entrance.target[1])))
  var invalid:Dictionary=b.quest_arrival.wild_context(b)
  check(not b.quest_arrival.check_wild(b,invalid,"miner").is_empty(),"project start cannot obtain wild eligibility")
  b.automation.position_changed(300,Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
  check(b.handle({"type":"report_position","map_id":31801,"cell":entrance.target}).ok,"production original entrance movement")
  check(not b.quest_arrival.check_wild(b,invalid,"miner").is_empty(),"later legal route cannot repair old invalid start")
  var proof:Dictionary=b.quest_arrival.wild_context(b)
  check(b.quest_arrival.check_wild(b,proof,"miner").is_empty(),"server original route receipt accepted")
  check(not other.quest_arrival.check_wild(other,proof,"miner").is_empty(),"another role/device backend cannot reuse receipt")
  var forged:Dictionary=proof.duplicate(true);forged.serial+=1
  check(not b.quest_arrival.check_wild(b,forged,"miner").is_empty(),"modified client-shaped receipt rejected")
  check(not b.quest_arrival.check_wild(b,proof,"dragon").is_empty(),"scope mismatch rejected")
  # Pure receipt-layer retry contract; actual combat save-failure is owned
  # by backend integration tests, not simulated by granting a scope here.
  check(b.quest_arrival.check_wild(b,proof,"miner").is_empty() and b.quest_arrival.check_wild(b,proof,"miner").is_empty(),"repeated final validation does not consume receipt")
  b.automation.position_changed(300,Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
  check(b.handle({"type":"report_position","map_id":31801,"cell":entrance.target}).ok,"actual original re-entry")
  check(not b.quest_arrival.check_wild(b,proof,"miner").is_empty(),"leave and return cannot reuse old epoch")
  proof=b.quest_arrival.wild_context(b);b.quest_arrival.reset()
  check(not b.quest_arrival.check_wild(b,proof,"miner").is_empty(),"restart/reset invalidates receipt")
 b.free();other.free()
 print("QUEST WILD DROP POLICY: %d failures"%failures);quit(1 if failures else 0)
