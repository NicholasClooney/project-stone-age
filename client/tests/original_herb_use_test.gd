extends SceneTree
const Backend=preload("res://server/backend.gd")
const Rules=preload("res://server/original_quests.gd")
const Session=preload("res://server/game_session.gd")
const GIRL="jaruga/event/event01_1"
const DOCTOR="jaruga/event/event01_2"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> void:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
func row(b) -> Dictionary:
 for q in b.quest_helper.snapshot(b).quests:
  if int(q.event)==1:return q
 return {}
func current(b,id:String) -> bool:
 return row(b).steps.any(func(s):return s.id=="herb:"+id and s.current and s.actionable)
func trade(b,id:String) -> Dictionary:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(b.handle({"type":"quest_visit","npc_id":id,"mode":"near"}).ok,"source herb safe visit")
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":id})
 r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 if r.has("dialogue"):r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"ok"})
 return r
func use(b,pet_id:Variant="") -> Dictionary:
 return b.handle({"type":"use_item","item":"original_2401","pet_id":pet_id})
func run() -> void:
 var b=Backend.new()
 check(b.quest_catalog.items["2401"].use.roll_min==90 and b.quest_catalog.items["2401"].use.roll_max==110 and b.quest_catalog.items["2401"].use.consume_at_full,"reviewed source nominal100 rolls90..110 and full consumes")
 check(trade(b,GIRL).ok and trade(b,DOCTOR).ok and current(b,"return"),"real quest medicine granted")
 b.session.gm_raise_level(-1,30)
 b.session.gm_set_base_stat(-1,"vitality",150)
 b.session._profile.player.hp=1
 b.session.recovery_rng.seed=90210
 var expected_rng:=RandomNumberGenerator.new();expected_rng.seed=90210
 var power:=expected_rng.randi_range(90,110)
 var before:Dictionary=b.session.snapshot()
 var answer:=use(b)
 check(answer.ok and b.session.snapshot().player.hp==1+power and b.session.recovery_rng.state==expected_rng.state,"one server random draw and exact original field recovery")
 check(b.session.snapshot().original_items.is_empty() and Rules.flag(b.session.snapshot(),"now",1) and not Rules.flag(b.session.snapshot(),"ended",1) and current(b,"medicine"),"consume one herb preserves quest flags and refreshes doctor step")
 check(str(answer.note).contains("耐久力回复%d"%power),"reply reports actual clamped recovery")
 check(trade(b,DOCTOR).ok and 2401 in b.session.snapshot().original_items,"real doctor replenishes eaten herb")
 b.session._profile.original_items.append(2401)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 before=b.session.snapshot()
 check(use(b).ok and b.session.snapshot().player.hp==before.player.hp and b.session.snapshot().original_items==[2401] and current(b,"return"),"full HP consumes exactly one copy and keeps remaining quest herb")
 check(use(b).ok and current(b,"medicine"),"last full-HP copy consumed and helper returns to doctor")
 before=b.session.snapshot();var rng_state:int=b.session.recovery_rng.state
 check(not use(b).ok and b.session.snapshot()==before and b.session.recovery_rng.state==rng_state,"missing herb rejects without random draw or side effect")
 b.session._profile.original_items=[2414,2401,2427,2401]
 b.session.grant_starter_pets();b.session.snapshot()
 var first:String=b.session._profile.pets[0].pet_id
 var target:String=b.session._profile.pets[1].pet_id
 var provenance:int=b.session._profile.pets[1].original_end_event
 b.session._profile.pets[0].name="同名伙伴";b.session._profile.pets[1].name="同名伙伴"
 b.session._profile.pets[0].hp=1;b.session._profile.pets[1].hp=0
 before=b.session.snapshot()
 check(use(b,target).ok and b.session.snapshot().pets[1].hp>0 and b.session.snapshot().pets[1].hp<=b.session.snapshot().pets[1].max_hp,"original field recovery accepts zero-HP carried pet")
 check(b.session.snapshot().pets[0].hp==before.pets[0].hp and b.session.snapshot().player.hp==before.player.hp and b.session.snapshot().pets[1].pet_id==target and b.session.snapshot().pets[1].original_end_event==provenance,"UID chooses exact pet and retains doctor source field")
 check(b.session.snapshot().original_items==[2414,2427,2401],"only one2401 removed without disturbing item order")
 b.session._profile.player.hp=0
 before=b.session.snapshot();rng_state=b.session.recovery_rng.state
 check(not use(b,target).ok and b.session.snapshot()==before and b.session.recovery_rng.state==rng_state,"dead owner cannot administer item even to a living pet")
 b.session._profile.player.hp=1
 check(b.session.store_pet(1),"target moved into warehouse")
 before=b.session.snapshot();rng_state=b.session.recovery_rng.state
 check(not use(b,target).ok and b.session.snapshot()==before and b.session.recovery_rng.state==rng_state,"stored UID cannot be treated as a carried pet")
 for command in [{"type":"use_item","item":"original_2401","pet_id":"pet-999999"},{"type":"use_item","item":"original_2401","pet_id":0},{"type":"use_item","item":2401},{"type":"use_item","item":"original_2401","pet_id":{}},{"type":"use_item","item":"original_2401","pet_id":null},{"type":"use_item","item":"original_2427"},{"type":"use_item","item":"potion","pet_id":first},{"type":"use_item","pet_id":first}]:
  check(not b.handle(command).ok and b.session.snapshot()==before and b.session.recovery_rng.state==rng_state,"invalid item/target refused without mutation")
 b.session._profile.pets[0].hp=b.session._profile.pets[0].max_hp-1
 before=b.session.snapshot()
 check(use(b,first).ok and b.session.snapshot().pets[0].hp==b.session.snapshot().pets[0].max_hp and b.session.snapshot().player.hp==before.player.hp,"clamp to maxHP on exact carried UID")
 b.session._profile.original_items=[2401]
 b.save_path="user://missing-herb-use/save.json"
 before=b.session.snapshot()
 check(not use(b).ok and b.session.snapshot()==before and b.session.last_note.is_empty(),"save failure rolls back HP, inventory, flags and does not claim success")
 b.save_path=""
 var config:Dictionary=b.session.start_battle_config()
 before=b.session.snapshot();rng_state=b.session.recovery_rng.state
 check(not use(b).ok and b.session.snapshot()==before and b.session.recovery_rng.state==rng_state,"pending battle rejects field herb before drawing")
 b.session._pending={}
 b.battle_open=true
 check(not use(b).ok and b.session.snapshot()==before,"open battle rejects field herb even after pending cleared")
 b.battle_open=false
 # Clients cannot specify recovery power. Extra fields never change the
 # source-driven effect, and one accepted command draws once.
 expected_rng.seed=77;b.session.recovery_rng.seed=77;power=expected_rng.randi_range(90,110)
 answer=b.handle({"type":"use_item","item":"original_2401","power":999999,"target":"foreign-player"})
 check(answer.ok and b.session.snapshot().player.hp==1+power and b.session.recovery_rng.state==expected_rng.state,"client-supplied heal power cannot override original source")
 b.session._profile.original_items=[2401];b.save_path="user://herb-use-roundtrip.json"
 b.session._profile.player.hp=1
 check(use(b).ok,"successful source recovery writes save")
 var loaded=Session.new()
 check(loaded.load_game(b.save_path) and loaded.snapshot().original_items.is_empty() and loaded.snapshot().player.hp==b.session.snapshot().player.hp and loaded.snapshot().pets==b.session.snapshot().pets,"HP, consumed item and pet provenance survive disk roundtrip")
 for suffix in ["",".bak",".tmp"]:DirAccess.remove_absolute(b.save_path+suffix)
 # Old prototype potion keeps its 30/self/full refusal rules.
 b.save_path="";b.session._profile.player.hp=1
 before=b.session.snapshot()
 check(b.handle({"type":"use_item","item":"potion"}).ok and b.session.snapshot().player.hp==31 and b.session.snapshot().inventory.potion==before.inventory.potion-1,"prototype potion behavior remains30/self")
 b.free()
 print("ORIGINAL HERB USE: %d failures"%failures)
 quit(1 if failures else 0)
