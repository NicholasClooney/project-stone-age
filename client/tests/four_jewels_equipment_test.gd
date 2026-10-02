extends SceneTree
const Session=preload("res://server/game_session.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Effects=preload("res://scripts/original_item_effects.gd")
const Battle=preload("res://server/battle_session.gd")
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func run() -> void:
 for id in [2765]:
  var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/original-item-effects.json")).items[str(id)]
  var effects:Array=Effects.resolve(fixture)
  check(effects.filter(func(e):return e.type=="stat").all(func(e):return e.active),"actual ordinary attributes are active, never labelled unsupported")
  check(effects.filter(func(e):return e.type=="magic").all(func(e):return not e.active) and Effects.lines(fixture).any(func(line):return line.contains("未生效")),"source magic remains labelled metadata")
  var s=Session.new()
  s.gm_raise_level(-1,59)
  Equipment.add(s._profile,id)
  var uid:int=s._profile.original_instances[-1].uid
  check(not s.equip_item("original:%d"%uid),"original Lv60 equipment rejects59 %d"%id)
  s.gm_raise_level(-1,60)
  check(s.allocate_stat("toughness",50) and s.allocate_stat("dexterity",50),"real allocation keeps stats above negative-equipment floors")
  var before:Dictionary=s.effective_player_stats()
  check(s.equip_item("original:%d"%uid),"real equip at60 %d"%id)
  var after:Dictionary=s.effective_player_stats()
  for stat in ["attack","defence","speed"]:
   check(int(after[stat])-int(before[stat])==int(Equipment.ITEMS[id][stat]),"source numerical %s modifier %d"%[stat,id])
  check(Equipment.mods(s.snapshot()).charm==int(Equipment.ITEMS[id].charm),"source ordinary charm applies")
  check(Equipment.resistances(s.snapshot())==[0,0,0,0,0,0],"source has no invented resistance")
  check(int(s.snapshot().original_instances[-1].durability)==2500000,"reward starts at exact source durability")
  var resolver=Battle.new();resolver.start_battle(s.start_battle_config())
  for turn in range(12):resolver.submit_action("defend")
  var battle_state:Dictionary=resolver.snapshot()
  for turn in range(100):
   if not battle_state.active:break
   battle_state=resolver.submit_action("attack")
  check(not battle_state.active,"real equipment battle settles")
  check(int(battle_state.original_equipment_items[0].durability)>0 and int(battle_state.original_equipment_items[0].durability)<2500000,"real battle wears this original equipped instance")
  check(s.apply_battle_result(battle_state),"real settlement writes worn durability")
  var file:="user://four-jewels-equip-%d.json"%id
  check(s.save_game(file),"equipped reward persists")
  var loaded=Session.new()
  check(loaded.load_game(file) and loaded.snapshot().original_equipment.bracelet==uid,"equipped original UID reloads")
  check(loaded.snapshot().original_instances==s.snapshot().original_instances,"save reload preserves actual worn durability and UID")
  for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(file+suffix))
 print("FOUR JEWELS EQUIPMENT: %d failures"%failures)
 quit(1 if failures else 0)
