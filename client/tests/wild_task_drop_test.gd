extends "res://tests/wild_position_authority_test.gd"
const Route=preload("res://tests/support/original_route_driver.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Loot=preload("res://server/quest_wild_loot.gd")
func strong(b)->void:
 b.session.gm_raise_level(-1,80)
 b.session._profile.player.base_stats={"vitality":50000,"strength":50000,"toughness":50000,"dexterity":50000}
 preload("res://server/progression.gd").refresh(b.session._profile.player)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 Equipment.add(b.session._profile,2536)
func mine(b,legal:bool)->void:
 if not legal:
  b.automation.position_changed(31801,Vector2i(37,48));return
 var entrance:Dictionary={}
 for link in b.quest_helper.places.links(300).values():
  if int(link.to_map)==31801 and not link.has("gate_source"):entrance=link;break
 check(not entrance.is_empty(),"source mine entrance")
 if entrance.is_empty():return
 b.automation.position_changed(300,Vector2i(int(entrance.cell[0]),int(entrance.cell[1])))
 check(b.handle({"type":"report_position","map_id":31801,"cell":entrance.target}).ok,"real public portal grants mine route")
 check(Route.walk(b,31801,Vector2i(37,48),[31801]).ok,"real continuous floor walk reaches ore area")
 check(b.quest_arrival.has_arrival(b,31801,Vector2i(37,48)),"actual route remains authorized")
func finish(b)->void:
 for turn in range(100):
  if not b.battle.snapshot().active:return
  var target:=0
  for i in range(b.battle._state.enemies.size()):
   if int(b.battle._state.enemies[i].hp)>0:target=i;break
  b.handle({"type":"battle_command","action":"attack","target":target})
 check(not b.battle.snapshot().active,"real battle reaches terminal state")
func ore(b,mode:String="wild")->bool:
 b.encounter_rng.seed=27
 for attempt in range(200):
  if mode=="stationary":
   if not b.stationary.running:check(b.handle({"type":"stationary_encounters","enabled":true}).ok,"stationary starts normally")
   b.stationary.lease=5.0;b.stationary.tick(b,0.5)
  elif mode=="field":b.handle({"type":"field_step","map_id":31801,"cell":[37,48],"encounter":true})
  else:check(b.handle({"type":"wild_encounter","map_id":31801,"cell":[37,48]}).ok,"actual seed27 wild roll")
  if not b.battle_open:continue
  if b.session._pending.enemies.any(func(e):return int(e.get("source_enemy_id",0))==1043):return true
  finish(b);check(b.handle({"type":"battle_close"}).ok,"ordinary prior encounter closes")
 return false
func run()->void:
 slots()
 for mode in ["wild","field","stationary"]:
  for legal in [false,true]:
   var b=fresh();strong(b);mine(b,legal)
   check(ore(b,mode),"actual original ore encountered via "+mode)
   check(b.session._pending.has("wild_drop_receipt"),"source context frozen before battle")
   var before:Dictionary=b.session.snapshot()
   var original:Dictionary=b.session._pending.duplicate(true)
   b.save_path="user://no-task-drop-dir/save.json"
   finish(b)
   check(not b.battle_state.get("settled",false) and b.session.snapshot()==before,"savefail restores ordinary profile and special loot together")
   var pending:Dictionary=b.session._pending.duplicate(true)
   check(pending.wild_drop_receipt==original.wild_drop_receipt,"savefail retains exact original source/epoch")
   for retry in range(2):check(not b.handle({"type":"battle_close"}).ok and b.session._pending==pending,"repeat savefail keeps all original claims")
   b.save_path=""
   check(b.handle({"type":"battle_close"}).ok,"ordinary result closes after save retry")
   check(b.session.snapshot().original_items.count(2534)==(1 if legal else 0),"special ore only for original arrival "+mode+str(legal))
   check(b.session.snapshot().completed_battles.size()==before.completed_battles.size()+1 and int(b.session.snapshot().player.gold)>int(before.player.gold),"ordinary battle count and coins preserved")
   check(b.battle_state.has("quest_drop_denied")!=legal,"project supplement denial explained only when withheld")
   var saved:Dictionary=b.session.snapshot();b.handle({"type":"battle_close"});check(b.session.snapshot()==saved,"close replay cannot duplicate rewards")
   b.free()
 for reset in [false,true]:
  var b=fresh();strong(b);mine(b,true);check(ore(b),"valid source battle before epoch invalidation")
  var original:Dictionary=b.session._pending.wild_drop_receipt.duplicate(true)
  var borrowed:Dictionary=original.duplicate(true);borrowed.source.map=31802
  var claim_key:String=str(original.rules.keys()[0]);var exact_claim:Array=[{"enemy":int(claim_key.get_slice(":",0)),"item":int(claim_key.get_slice(":",1))}]
  check(Loot.filter_claims(b,original,exact_claim).claims==exact_claim and Loot.filter_claims(b,borrowed,exact_claim).claims.is_empty(),"same-scope different source map cannot borrow task-drop permission")
  borrowed=original.duplicate(true);borrowed.source.borrowed=true;borrowed.source.cell=[39,48]
  check(Loot.filter_claims(b,borrowed,exact_claim).claims.is_empty(),"same-map borrowed source cell cannot borrow task-drop permission")
  if reset:b.quest_arrival.reset()
  else:
   b.automation.position_changed(31801,Vector2i(38,48));b.automation.position_changed(31801,Vector2i(37,48))
  check(b.session._pending.wild_drop_receipt==original,"midbattle invalidation cannot refresh frozen proof")
  finish(b);check(b.handle({"type":"battle_close"}).ok and b.session.snapshot().original_items.count(2534)==0,"epoch loss suppresses only ore and allows close")
  b.free()
 print("WILD TASK DROP: %d failures"%failures);quit(1 if failures else 0)
func slots()->void:
 var catalog=preload("res://server/encounter_catalog.gd").new()
 var a=RandomNumberGenerator.new();var b=RandomNumberGenerator.new();a.seed=771;b.seed=771
 var source:={"drops":[{"slot":0,"item_id":2534,"probability":1000},{"slot":6,"item_id":2482,"probability":1000},{"slot":9,"item_id":1249,"probability":0}]}
 var sidecar:Array=[];var actual:Array=catalog.roll_drops(source,a,sidecar)
 var expected:Array=[]
 for drop in source.drops:
  if int(drop.probability)!=0 and b.randi_range(0,999)<int(drop.probability):expected.append(int(drop.item_id))
 check(actual==expected and a.state==b.state and sidecar==[0,6],"same RNG draws preserve sparse original slot, ordinary item, and probability-zero behavior")
 var host=fresh();var pending:={"enemies":[{"generated_drops":[2534,2482]}]};var result:={"enemies":[{"hp":0,"captured":false}]}
 var claims:Array=[{"enemy":0,"item":0},{"enemy":0,"item":1}]
 var receipt:={"rules":{"0:0":{"scope":"miner"}},"context":{}}
 check(host._loot_claims_valid(pending,claims,result),"whole original valid claims pass before policy")
 check(Loot.filter_claims(host,receipt,claims).claims==[{"enemy":0,"item":1}] and claims.size()==2,"only exact selected source slot removed on candidate copy")
 for bad in [[{"enemy":0,"item":0},{"enemy":0,"item":0}],[{"enemy":99,"item":0}],[{"enemy":0,"item":99}],[{"enemy":0,"item":0.5}]]:
  check(not host._loot_claims_valid(pending,bad,result),"malformed complete claims cannot be washed clean by suppression")
 host.automation.position_changed(31801,Vector2i(37,48))
 for unknown_slots in [[],[-1],[9],[0.5]]:
  host.session._pending={"source_encounter":true,"area_id":356,"group_id":508,"enemies":[{"source_enemy_id":1043,"generated_drops":[2534],"generated_drop_slots":unknown_slots}]}
  Loot.freeze(host)
  check(not str(host.session._pending.get("wild_drop_receipt",{}).get("error","")).is_empty(),"unknown source slot fails closed before settlement")
 host.session._pending={"source_encounter":true,"area_id":356,"group_id":508,"enemies":[{"source_enemy_id":1043,"generated_drops":[1249],"generated_drop_slots":[0]}]}
 Loot.freeze(host)
 check(not str(host.session._pending.wild_drop_receipt.error).is_empty(),"wrong item at exact original slot fails closed")
 host.free()
