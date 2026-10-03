extends "res://tests/brothers_golden_quests_test.gd"
## Actual public source NPCs; no synthetic branches or route receipts.
const WOOD="jaruga/event/20501ev5"
const ELDER="giiru/event/sink/sink03@300:407:298"
func prepare(id:String,gold:int):
 var b=fresh();b.session.snapshot()
 b.session._profile.original_items=[];b.session._profile.original_instances=[]
 for slot in b.session._profile.original_equipment:b.session._profile.original_equipment[slot]=0
 b.session._profile.player.gold=gold
 if id==WOOD:
  Session.OriginalEquipment.add(b.session._profile,2478)
  for i in range(14):Session.OriginalEquipment.add(b.session._profile,2468)
 else:
  for item in [2708,2708,2709]:Session.OriginalEquipment.add(b.session._profile,item)
 return b
func confirm(b,id:String)->Dictionary:
 var npc:Dictionary=b.original_quests.npc_by_id(id)
 check(not npc.is_empty(),"real public gold source is imported "+id)
 if npc.is_empty():return {"ok":false}
 b.automation.position_changed(int(npc.map_id),Vector2i(npc.cell[0],npc.cell[1]+1))
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":id})
 r=choose(b,r,"yes")
 return choose(b,r,"ok") if r.has("dialogue") else r
func delivered(b,id:String)->bool:
 var items:Array=b.session.snapshot().original_items
 return items==[2481] if id==WOOD else items==[2709]
func run()->void:
 for id in [WOOD,ELDER]:
  var amount:int=20000 if id==WOOD else 1149
  for gold in [1000001,1000000000-amount]:
   var b=prepare(id,gold)
   check(confirm(b,id).get("ok",false),"source credits above old million and inclusive project cap "+id)
   check(int(b.session.snapshot().player.gold)==gold+amount and delivered(b,id),"source amount and original bare deletion/reward remain exact "+id)
   b.free()
  var b=prepare(id,1000000000-amount+1);var before:Dictionary=b.session.snapshot()
  var npc:Dictionary=b.original_quests.npc_by_id(id)
  var source_full:String=str(b.original_quests.branch_for(npc,before).texts.StoneFullMsg)
  var r:=confirm(b,id)
  check(not r.get("ok",false) and str(r.get("reason","")).contains("10亿"),"overflow explains the project billion cap "+id)
  check(str(r.get("reason","")).contains(source_full) and str(r.get("reason","")).contains("项目改动"),"overflow retains original NPC wording and labels project change "+id)
  check(b.session.snapshot()==before,"overflow preserves money, item UIDs, counters and flags "+id)
  b.free()
  b=prepare(id,1000001);before=b.session.snapshot();b.save_path="user://missing-gold-limit/save.json"
  r=confirm(b,id)
  check(not r.get("ok",false) and str(r.get("reason",""))=="save_failed" and b.session.snapshot()==before,"save failure rolls back source exchange atomically "+id)
  b.save_path="user://source-gold-limit.json"
  check(confirm(b,id).get("ok",false) and int(b.session.snapshot().player.gold)==1000001+amount and delivered(b,id),"new source confirmation retries after save recovery "+id)
  var saved:Dictionary=b.session.snapshot();var copy=Backend.new()
  check(copy.load_profile(b.save_path) and copy.session.snapshot().original_instances==saved.original_instances and int(copy.session.snapshot().player.gold)==int(saved.player.gold),"actual saved gold and surviving UIDs reload "+id)
  copy.free();b.free()
  b=prepare(id,1000001)
  Session.OriginalEquipment.remove(b.session._profile,2478 if id==WOOD else 2709)
  before=b.session.snapshot();confirm(b,id)
  check(b.session.snapshot()==before,"original license/water prerequisite still prevents payout "+id)
  b.free()
 print("ORIGINAL QUEST GOLD LIMIT: %d failures"%failures);quit(1 if failures else 0)
