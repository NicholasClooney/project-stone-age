extends "res://tests/brothers_golden_quests_test.gd"
## Isolated branch oracle exercises the same helper and production transaction.
## Source capacity: npc_exchangeman.c:3812-3910 counts DelItem before GetRandItem.
func run()->void:
 for spec in [
  {"name":"one feather at full bag","feathers":1,"delete":"2700","worn":false,"allowed":true,"size":15},
  {"name":"all three feathers at full bag","feathers":3,"delete":"2700","worn":false,"allowed":true,"size":13},
  {"name":"no deletion random reward at full bag","feathers":0,"delete":"","worn":false,"allowed":false,"size":15},
  {"name":"worn deletion frees no bag slot","feathers":0,"delete":"1357","worn":true,"allowed":false,"size":15},
  {"name":"bag-only deletion ignores worn item","feathers":0,"delete":"1357","scope":"bag","worn":true,"allowed":false,"size":15},
  {"name":"quantified deletion frees one bag slot","feathers":3,"delete":"2700*1","worn":false,"allowed":true,"size":15},
  {"name":"both direct and random rewards count","feathers":1,"delete":"2700","get":"2698","worn":false,"allowed":false,"size":15}
 ]:
  exercise(spec)
 print("QUEST RANDOM CAPACITY: %d failures"%failures)
 quit(1 if failures else 0)
func exercise(spec:Dictionary)->void:
 var b=fresh();b.session.snapshot()
 b.session._profile.original_items=[];b.session._profile.original_instances=[]
 for slot in b.session._profile.original_equipment:b.session._profile.original_equipment[slot]=0
 if spec.worn:
  Session.OriginalEquipment.add(b.session._profile,1357)
  b.session._profile.original_equipment.amulet=int(b.session._profile.original_instances[-1].uid)
 for i in range(int(spec.feathers)):Session.OriginalEquipment.add(b.session._profile,2700)
 while Session.bag_slots(b.session._profile)<15:Session.OriginalEquipment.add(b.session._profile,2415)
 var actions:Dictionary={"GetRandItem":"1357,2698"}
 if not str(spec.delete).is_empty():actions.DelItem=spec.delete
 if spec.has("get"):actions.GetItem=spec.get
 var branch:Dictionary={"event":-1,"type":"ACCEPT","condition":"LV>0","actions":actions,"texts":{"ItemFullMsg":"source full"},"enabled":true,"events":[2]}
 if spec.has("scope"):branch.item_deletion_scope=spec.scope
 var fixture:Dictionary={"id":"capacity-fixture","name":"isolated capacity source","map_id":1000,"cell":[56,123],"branches":[branch],"events":[2]}
 var quest:Dictionary={"steps":[],"blocked_reason":""}
 var before:Dictionary=b.session.snapshot()
 b.quest_helper.add_step(b,before,quest,"capacity",{"npc":fixture,"branch":branch},true,false,"capacity fixture")
 check(quest.steps.size()==1 and bool(quest.steps[0].actionable)==bool(spec.allowed),"helper capacity: "+str(spec.name))
 check(b.session.snapshot()==before,"helper never mutates UID candidate: "+str(spec.name))
 var result:Dictionary=b.original_quests.transact(b,before,branch,"reward")
 check(bool(result.ok)==bool(spec.allowed),"real transaction agrees: "+str(spec.name))
 if spec.allowed:
  check(Session.bag_slots(b.session.snapshot())==int(spec.size),"actual net bag slots: "+str(spec.name))
  if str(spec.delete)=="2700":check(Rules.item_count(b.session.snapshot(),2700)==0,"bare deletion removes every feather")
 else:check(b.session.snapshot()==before,"rejected random transaction keeps UID and worn state")
 b.free()
