extends "res://tests/original_wood_equipment_test.gd"
const Effects=preload("res://scripts/original_item_effects.gd")
func run()->void:
 var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-item-effects.json"))
 var items:Dictionary=fixture.items
 for id in [1206,2416,2418,2427,2448,2465,2481,2485,1357,2460,2487,2505,2605,2606,2489,2492,2493,2494]:
  var effects:Array=Effects.resolve(items[str(id)])
  check(effects.filter(func(e):return e.type=="stat").all(func(e):return bool(e.active)),"supported ordinary stats not labelled inactive %d"%id)
 for id in [1052,2482,2483,2490,2518,2519,2520,2525,2526,2532,2547,2551]:
  check(Effects.resolve(items[str(id)]).filter(func(e):return e.type=="stat").all(func(e):return not bool(e.active)),"unsupported original stats clearly inactive %d"%id)
 for id in [1357,2418,2427,2489,2491,2688,2689,2690,2765,2605,2606]:
  var labels:Array[String]=Effects.lines(items[str(id)])
  check(not labels.is_empty() and labels.all(func(line):return line.begins_with("【未生效】")),"magic and resistance metadata only %d"%id)
  check(Effects.evidence(items[str(id)]).contains("gmsv/data/itemset.txt:"),"source row and raw field evidence retained")
 check(Effects.lines(items["2450"])[0].contains("复活至500") and Effects.lines(items["2450"])[0].contains("ITEM_useRessurect"),"unimplemented revive names exact source action and amount")
 check(Effects.lines(items["2421"]).is_empty(),"ordinary quest token has no invented inactive effect")
 for id in Equipment.NEWLY_WEARABLE:
  var s=strong(40);var uid:=add(s,id)
  check(equip(s,uid),"new fixed equipment uses existing slot %d"%id)
  var spec:Dictionary=Equipment.ITEMS[id]
  check(int(spec.level)==int(items[str(id)].raw_columns[22]) and int(spec.type)==int(items[str(id)].raw_columns[19]) and int(spec.durability)==int(items[str(id)].raw_columns[31]),"source type level and durability match fixed definition")
  for stat in Equipment.STATS:check(int(s.equipment_mods()[stat])==int(spec[stat]),"real equipment modifier %d %s"%[id,stat])
  for stat in items[str(id)].stats_source:
   if str(stat.stat) in Equipment.STATS:check(int(stat.raw.min)==int(stat.raw.max) and int(spec[str(stat.stat)])==int(stat.raw.min),"definition equals exact fixed source values")
  check(s.save_game("user://effect-equipment.json"),"new equipment saves")
  var loaded=Session.new()
  check(loaded.load_game("user://effect-equipment.json") and int(loaded.snapshot().original_equipment[str(spec.slot)])==uid,"new equipment reads back exact UID")
  # A formerly metadata-only, unworn instance had durable zero. No new fields.
  var old:Dictionary=s.snapshot();old.original_equipment[str(spec.slot)]=0;old.original_instances[0].durability=0
  write("user://effect-old-equipment.json",old)
  loaded=Session.new()
  check(loaded.load_game("user://effect-old-equipment.json") and int(loaded.snapshot().original_instances[0].durability)==int(spec.durability),"old unworn metadata item migrates without save/schema expansion")
  check(loaded.snapshot().original_instances[0].keys().size()==3,"instance still only UID item and durability")
  var worn_zero:Dictionary=s.snapshot();worn_zero.original_instances[0].durability=0
  write("user://effect-old-equipment.json",worn_zero)
  check(not Session.new().load_game("user://effect-old-equipment.json"),"migration never accepts worn zero-durability equipment")
  old.original_instances[0].durability=1
  write("user://effect-old-equipment.json",old)
  loaded=Session.new()
  check(loaded.load_game("user://effect-old-equipment.json") and int(loaded.snapshot().original_instances[0].durability)==1,"migration never repairs a positive damaged durability")
 var b=Backend.new();root.add_child(b)
 var helpers:Dictionary=b.quest_helper.snapshot(b)
 var advertised:=false
 for quest in helpers.quests:
  for step in quest.steps:
   if step.has("reward_effects"):
    advertised=true
    check(step.reward_effects[0].effects[0].has("active"),"server helper exports resolved active flags")
   if step.has("effects_notice"):check(str(step.label).contains("未生效"),"existing helper UI receives explicit unsupported reward label")
 check(advertised,"real original helper rewards include effect source metadata")
 b.queue_free();await process_frame
 remove_files("user://effect-equipment.json");remove_files("user://effect-old-equipment.json")
 print("ORIGINAL ITEM EFFECTS: %d failures"%failures)
 quit(1 if failures else 0)
