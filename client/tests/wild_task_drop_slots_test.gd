extends "res://tests/wild_task_drop_test.gd"
func run()->void:
 slots()
 var b=fresh();b.automation.position_changed(21206,Vector2i(30,30))
 var enemy:Dictionary=b.encounter_catalog.data.enemies["1334"]
 var rng=RandomNumberGenerator.new();rng.seed=99277
 var generated:Array=[];var original_slots:Array=[]
 for attempt in range(20000):
  original_slots=[];generated=b.encounter_catalog.roll_drops(enemy,rng,original_slots)
  if generated==[1249,2766]:break
 check(generated==[1249,2766] and original_slots==[0,1],"actual enemy1334 original RNG yields ordinary material and task shell in distinct source slots")
 b.session._pending={"source_encounter":true,"area_id":578,"group_id":722,"enemies":[{"source_enemy_id":1334,"generated_drops":generated,"generated_drop_slots":original_slots}]}
 Loot.freeze(b)
 var receipt:Dictionary=b.session._pending.get("wild_drop_receipt",{})
 check(receipt.get("error","").is_empty() and receipt.get("rules",{}).size()==1 and receipt.rules.has("0:1"),"complete actual map/area/group/enemy/item/slot selects shell only")
 var claims:Array=[{"enemy":0,"item":0},{"enemy":0,"item":1}]
 check(b._loot_claims_valid(b.session._pending,claims,{"enemies":[{"hp":0,"captured":false}]}),"original complete water claims remain valid")
 check(Loot.filter_claims(b,receipt,claims).claims==[{"enemy":0,"item":0}] and b.session._pending.enemies[0].generated_drops==[1249,2766],"project arrival withholds actual water shell while preserving same-enemy ordinary material and frozen originals")
 b.free()
 print("WILD TASK DROP SLOTS: %d failures"%failures);quit(1 if failures else 0)
