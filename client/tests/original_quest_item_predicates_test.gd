extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Equipment=preload("res://server/original_equipment.gd")
const BARL="jaruga/event/20501ev3"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run() -> void:
 var b=Backend.new()
 b.session.gm_raise_level(-1,30)
 for key in b.session._profile.inventory:b.session._profile.inventory[key]=0
 Equipment.add(b.session._profile,2465)
 var uid:int=b.session.snapshot().original_instances[-1].uid
 Rules.set_flag(b.session._profile,"now",18,true)
 check(b.handle({"type":"quest_visit","npc_id":BARL,"mode":"near"}).ok,"real original Barl location")
 var equip:Dictionary={"type":"equip_item","item":"original:%d"%uid}
 check(b.handle(equip).ok,"real backend equips original axe")
 var state:Dictionary=b.session.snapshot()
 var before:Dictionary=state.duplicate(true)
 check(not Rules.matches(state,"ITEM=2465") and Rules.matches(state,"ITEM!=2465"),"plain positive and negative ITEM ignore worn axe")
 check(Rules.matches(state,"ITEM=2465*1") and not Rules.matches(state,"ITEM=2465*2"),"quantified positive ITEM includes worn slots")
 check(Rules.matches(state,"ITEM!=2465*2"),"C inequality is evaluated before quantity and uses bag-only absence")
 check(state==before,"predicate evaluation never changes equipment or profile")
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":BARL})
 check(str(b.original_quests.pending.phase)!="ACCEPT","wearing sole axe does not reach original delivery branch")
 var helper:Dictionary=b.quest_helper.snapshot(b)
 var task:Dictionary={}
 for quest in helper.quests:
  if int(quest.event)==18:task=quest
 check(str(task.get("blocked_reason","")).contains("先卸下"),"helper explains why the worn quest item is unavailable")
 b.handle({"type":"quest_close","token":r.dialogue.token})
 check(b.handle(equip).ok,"real backend unequips original axe")
 state=b.session.snapshot()
 check(Rules.matches(state,"ITEM=2465") and not Rules.matches(state,"ITEM!=2465"),"unworn axe satisfies original delivery")
 helper=b.quest_helper.snapshot(b)
 for quest in helper.quests:
  if int(quest.event)==18:task=quest
 check(not str(task.get("blocked_reason","")).contains("先卸下"),"helper refreshes when only equipment location changes")
 r=b.handle({"type":"quest_talk","npc_id":BARL})
 check(str(b.original_quests.pending.phase)=="ACCEPT","unworn axe reaches actual original Barl ACCEPT")
 r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 before=b.session.snapshot();b.save_path="user://missing-item-predicate/save.json"
 check(not b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"ok"}).ok and b.session.snapshot()==before,"original delivery save failure preserves axe and flags")
 b.save_path=""
 r=b.handle({"type":"quest_talk","npc_id":BARL})
 r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 check(b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"ok"}).ok and Rules.flag(b.session.snapshot(),"ended",18) and not 2465 in b.session.snapshot().original_items,"actual original delivery consumes axe once after unequip")
 # Preserve the already documented quantified DelItem compatibility correction.
 Equipment.add(b.session._profile,2481);Equipment.add(b.session._profile,2481)
 state=b.session.snapshot();uid=int(state.original_instances[-1].uid)
 check(b.handle({"type":"equip_item","item":"original:%d"%uid}).ok,"wear newer duplicate through Session")
 state=b.session.snapshot()
 check(Rules.matches(state,"ITEM=2481") and Rules.matches(state,"ITEM=2481*2") and not Rules.matches(state,"ITEM!=2481*99"),"bag spare and worn duplicate obey each original check family")
 Rules.remove_items(b.session._profile,"2481*1")
 state=b.session.snapshot()
 check(state.original_items.count(2481)==1 and state.original_equipment.bracelet==0,"quantified DelItem still removes worn-first exactly one")
 b.free()
 print("ORIGINAL QUEST ITEM PREDICATES: %d failures"%failures)
 quit(1 if failures else 0)
