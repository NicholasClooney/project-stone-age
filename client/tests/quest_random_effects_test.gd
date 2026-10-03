extends "res://tests/brothers_golden_quests_test.gd"
const Effects=preload("res://scripts/original_item_effects.gd")
# Independently frozen ruri05:14, full85 source slots (not a deduplicated pool).
const POOL="36,46,60,160,162,170,250,257,261,339,345,356,442,453,457,540,544,561,646,652,664,747,750,755,36,160,250,257,339,442,532,646,745,2694,2695,2696,957,966,1036,1047,1144,1156,1359,1357,11806,11804,11813,11835,11836,11844,11845,11856,11864,11875,11883,11902,957,966,970,1036,1044,1056,1144,1156,1159,1357,1358,1367,11805,11804,11814,11815,11834,11835,11836,11845,11846,11855,11865,11875,11884,11904,2691,2692,2693"
class EffectFixture:
 extends RefCounted
 var actions:Dictionary
 func stage_key(_h,_b)->Array:return []
 func steps(_h,_b,_p,q:Dictionary)->void:q.steps.append({"id":"fixture","label":"unchanged label","source":{"actions":actions.duplicate(true)}})
func run()->void:
 var b=fresh()
 # Load independently reviewed item source metadata even when earth itself is
 # disabled; do not enable production branches or mutate shared resources.
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/transmigration-equipment.json"))
 for record in fixture.records:b.quest_catalog.items[str(int(record.id))]=record.item.duplicate(true)
 b.quest_catalog.jobs=[{"id":999,"event":39,"title":"isolated effect projection"}]
 b.quest_catalog.enabled_events=[39]
 var projection:=EffectFixture.new();projection.actions={"GetRandItem":POOL,"DelItem":"2700"}
 b.quest_helper.transmigration.helpers={"transmigration-earth":projection}
 var first:Dictionary=b.quest_helper.snapshot(b).quests[0].steps[0]
 var slots:Array=Rules.item_list(POOL)
 check(slots.size()==85 and slots[56]==957 and slots.count(957)==2 and slots.count(36)==2,"frozen85 slots restore957 and duplicate weights")
 check(first.source.actions==projection.actions,"projection preserves exact original action strings")
 var expected:Array=[]
 for id in slots:
  var item:Dictionary=b.quest_catalog.items.get(str(id),{})
  var effects:Array=Effects.resolve(item)
  if not effects.is_empty():expected.append({"item_id":id,"name":str(item.get("name","")),"effects":effects})
 check(first.reward_effects==expected,"all original ordered slot effects remain available, including repeats")
 check(first.effects_notice.contains("原奖池85槽、67种物品") and first.effects_notice.contains("重复槽保持原权重") and first.effects_notice.contains("不按物品种类均分概率"),"summary distinguishes slots from item types and preserves weighting meaning")
 check(first.effects_notice.contains("未实现效果类别：连续攻击次数、特殊攻击方式、魔法、抗性。") and not first.effects_notice.contains("普通属性"),"summary lists actual inactive categories only")
 check(first.effects_notice.length()<180 and first.label.length()<220,"source85 summary fits bounded phone text without arbitrary truncation")
 projection.actions={"GetItem":"957"};b.quest_helper.cached_key=""
 var fixed:Dictionary=b.quest_helper.snapshot(b).quests[0].steps[0]
 var notice:String=str(b.quest_catalog.items["957"].name)+"："+"；".join(Effects.lines(b.quest_catalog.items["957"]))
 check(fixed.effects_notice==notice and not fixed.label.contains("原奖池"),"fixed reward keeps precise existing item effects")
 projection.actions={"GetItem":"957","GetRandItem":POOL};b.quest_helper.cached_key=""
 var combined:Dictionary=b.quest_helper.snapshot(b).quests[0].steps[0]
 check(combined.effects_notice.begins_with(notice+"\n") and combined.effects_notice.contains("原奖池85槽、67种物品"),"mixed direct and random branch retains both distinct notices")
 check(combined.reward_effects.size()==expected.size()+1 and combined.reward_effects.slice(1)==expected,"mixed branch retains fixed effect and all weighted random slots")
 b.free()
 print("QUEST RANDOM EFFECTS: %d failures"%failures)
 quit(1 if failures else 0)
