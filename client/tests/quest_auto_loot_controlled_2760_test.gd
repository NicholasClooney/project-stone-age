extends "res://tests/quest_auto_loot_checkpoint_test.gd"
## UNRUN controlled C only. NOT natural RNG, P3, public admission or WS proof.
## Reuses internal E1, strong-character and explicit500ms fixture clock.
## Exception: fixed711, first member choice1305, actual1305 slot0 succeeds.
## Original count and every weighted RNG draw/actor call retained; NOT natural evidence.
const ControlledSession = preload("res://server/game_session.gd")
class Controlled2760Catalog:
 extends "res://server/encounter_catalog.gd"
 var step_calls := 0
 var roll_calls := 0
 var forced_slots := 0
 var drop_observations:Array=[]
 var member_scope := false
 var member_rng:RandomNumberGenerator
 var member_entries:Array=[]
 var member_calls := 0
 var member_super_calls := 0
 var forced_members := 0
 var member_records:Array=[]
 var member_error := ""
 func _weighted(entries:Array,rng:RandomNumberGenerator)->int:
  # Even the forced choice consumes exactly the original weighted RNG draw.
  # No override of count randi_range or actor generation.
  var original:int=super._weighted(entries,rng)
  if not member_scope:return original
  member_calls+=1
  member_super_calls+=1
  if not is_same(rng,member_rng) or entries!=member_entries:
   member_error="Scoped weighted call is not the original711 member input"
   return original
  if member_calls>100:
   member_error="Original100 member-attempt bound exceeded"
   return original
  var forced:bool=member_calls==1
  var selected:int=1305 if forced else original
  if forced:forced_members+=1
  member_records.append({"ordinal":member_calls,"original":original,"returned":selected,"forced":forced})
  return selected
 func step(map_id:int,cell:Vector2i,_rng:RandomNumberGenerator,is_portal:=false)->bool:
  step_calls+=1
  return map_id==100 and area_at(map_id,cell).get("id")==56 and not is_portal
 func roll(map_id:int,cell:Vector2i,rng:RandomNumberGenerator,held_items:Array=[])->Dictionary:
  roll_calls+=1
  var area:Dictionary=area_at(map_id,cell)
  if map_id!=100 or area.get("id")!=56 or 2764 not in held_items or 2760 in held_items:return {}
  if member_scope or roll_calls!=1:
   member_error="Unexpected nested or repeated controlled roll"
   return {}
  member_entries=data.groups["711"].enemies.duplicate(true)
  member_rng=rng
  member_scope=true
  var troop:Dictionary=super.roll_group(area,711,rng,held_items)
  member_scope=false
  member_rng=null
  return troop
 func roll_drops(enemy:Dictionary,rng:RandomNumberGenerator,original_slots:Array=[])->Array:
  if enemy.get("id")!=1305:return super.roll_drops(enemy,rng,original_slots)
  var expected_slots:Array=[{"slot":0,"item_id":2760,"probability":100,"denominator":1000}]
  var native_equal:bool=enemy.get("drops")==expected_slots
  var source_equal:bool=preload("res://server/quest_auto_loot_sources.gd").same(enemy.get("drops"),expected_slots)
  if drop_observations.size()<10:
   drop_observations.append({"enemy_id":enemy.get("id"),"id_type":typeof(enemy.get("id")),"drops":enemy.get("drops"),"native_equal":native_equal,"source_equal":source_equal})
  if not source_equal:return []
  forced_slots+=1
  original_slots.append(0)
  return [2760] # Only controlled generated source slot; never add to live bag.
class Controlled2760Backend:
 extends CountedBackend
 var clock_value:Array=[]
 var expected_target_count:=0
 var before_reward:Dictionary={}
 var original_pending:Dictionary={}
 var original_result:Dictionary={}
 var expected_profile:Dictionary={}
 var expected_error:String=""
 var settlement_frame:Dictionary={}
 var settlement_calls:=0
 var close_calls:=0
 var settlement_primary:PackedByteArray=PackedByteArray()
 var previous_primary:PackedByteArray=PackedByteArray()
 var settlement_backup:PackedByteArray=PackedByteArray()
 func _after_turn(state:Dictionary,settle:Dictionary={},drop_claims:Array=[])->Dictionary:
  if not state.get("active",true) and session._pending.has("quest_loot_receipt"):
   before_reward=session._profile.duplicate(true)
  return super._after_turn(state,settle,drop_claims)
 func _prepare_loot_settlement(pending:Dictionary,result:Dictionary)->Dictionary:
  original_pending=pending.duplicate(true)
  original_result=result.duplicate(true)
  previous_primary=FileAccess.get_file_as_bytes(save_path)
  # Independent counterfactual reward baseline: same actual terminal result,
  # no loot claims and no receipt. This clone never writes or touches live state.
  # Reuse original XP/HP/loyalty formulas; independently reconstruct bag+ledger.
  var shadow=preload("res://server/game_session.gd").new()
  shadow._profile=before_reward.duplicate(true)
  shadow._pending=pending.duplicate(true)
  shadow._pending.erase("quest_loot_receipt")
  shadow._pending.loot_claims=[]
  var no_drop_result:Dictionary=result.duplicate(true)
  if not shadow.apply_battle_result(no_drop_result):
   expected_error="Counterfactual original non-loot rewards rejected"
  elif not no_drop_result.drop_summary.is_empty():
   expected_error="Counterfactual no-claim baseline granted an item"
  else:
   expected_profile=shadow.snapshot()
   # Exact UID comes from the pre-reward monotonic allocator, not received data.
   var uid:int=int(before_reward.next_original_uid)
   if expected_profile.next_original_uid!=uid:
    expected_error="Non-loot result unexpectedly allocated an original UID"
   if expected_target_count==1:
    expected_profile.original_items.append(2760)
    expected_profile.original_instances.append({"uid":uid,"item_id":2760,"durability":int(session.OriginalEquipment.ITEMS.get(2760,{}).get("durability",0))})
   expected_profile.next_original_uid=uid+expected_target_count
   var entry:Dictionary=expected_profile.quest_loot.entries["jewels:hunt:2760"]
   entry.used_ms=quest_loot.base_used_ms+int(clock_value[0])-quest_loot.anchor_ms
   entry.revision+=1
   entry.open_span=false
   entry.settled_seq=entry.issued_seq
   entry.saved_battles+=1
   entry.new_items+=expected_target_count
  settlement_frame=super._prepare_loot_settlement(pending,result)
  return settlement_frame
 func _loot_settlement_written(payload:String,owner,path:String)->void:
  super._loot_settlement_written(payload,owner,path)
  if original_pending.is_empty():return # Original E1 acquire/open are counted by parent.
  settlement_calls+=1
  settlement_primary=FileAccess.get_file_as_bytes(path)
  settlement_backup=FileAccess.get_file_as_bytes(path+".bak")
 func close_battle()->String:
  close_calls+=1
  return super.close_battle()
func retained_fact(b)->Dictionary:
 return {"profile":b.session.snapshot(),"pending":b.session._pending.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"commits":b.commits,"settlements":b.settlement_calls,"closes":b.close_calls,"primary":FileAccess.get_file_as_bytes(b.save_path),"backup":FileAccess.get_file_as_bytes(b.save_path+".bak"),"tmp_exists":FileAccess.file_exists(b.save_path+".tmp"),"receipt":b.original_pending.quest_loot_receipt.duplicate(true)}
func controlled_case(b)->bool:
 var time:Array=[1000]
 b.clock_value=time
 b.encounter_catalog=Controlled2760Catalog.new()
 # Inherited checkpoint.setup synchronizes original location before E1 save.
 if not prepare_attempt(b,"user://controlled-2760-c.json",time):return false
 check(b.commits==2 and 2760 not in b.session._profile.original_items,"Real durable E1 acquire/open; target absent before controlled E2")
 if failures:return false
 var expected_source:Dictionary={"map":100,"area":56,"group":711,"borrowed":false,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
 var before_e2:Dictionary=b.session.snapshot()
 var reply:Dictionary=b.quest_loot.attempt_once(b)
 check(reply.get("ok",false) and reply.get("battle",false) and b.field_calls==1 and b.encounter_catalog.step_calls==1 and b.encounter_catalog.roll_calls==1,"One real E2 calls fixed711 original troop generation once")
 if failures:return false
 var pending:Dictionary=b.session._pending.duplicate(true)
 b.expected_target_count=pending.enemies.filter(func(enemy):return enemy.source_enemy_id==1305).size()
 print("CONTROLLED_2760_E2_DIAGNOSTIC ",JSON.stringify({"group":pending.get("group_id"),"members":pending.enemies.map(func(enemy):return {"source_enemy_id":enemy.get("source_enemy_id"),"generated_drops":enemy.get("generated_drops"),"generated_drop_slots":enemy.get("generated_drop_slots")}),"enemy_count":pending.enemies.size(),"target_count":b.expected_target_count,"forced_slots":b.encounter_catalog.forced_slots,"member_calls":b.encounter_catalog.member_calls,"member_super_calls":b.encounter_catalog.member_super_calls,"forced_members":b.encounter_catalog.forced_members,"member_error":b.encounter_catalog.member_error,"member_records":b.encounter_catalog.member_records,"drop_observations":b.encounter_catalog.drop_observations}))
 check(pending.group_id==711 and pending.enemies.size()>=1 and pending.enemies.size()<=10 and b.expected_target_count==1 and b.encounter_catalog.forced_slots==b.expected_target_count,"Original711 count/member generation; forced slots belong only to actual1305")
 if failures:return false
 var catalog=b.encounter_catalog
 check(catalog.member_error.is_empty() and not catalog.member_scope and catalog.member_rng==null and catalog.forced_members==1 and catalog.member_calls>=pending.enemies.size() and catalog.member_calls<=100 and catalog.member_super_calls==catalog.member_calls and catalog.member_records.size()==catalog.member_calls and catalog.member_entries==catalog.data.groups["711"].enemies,"Exactly one scoped first member override; every actual weighted call delegated once; catalog entries unchanged")
 if failures:return false
 for index in range(catalog.member_records.size()):
  var observed:Dictionary=catalog.member_records[index]
  check(observed.ordinal==index+1 and observed.original in [1305,1309,1310] and observed.forced==(index==0) and observed.returned==(1305 if index==0 else observed.original),"First member1305 only; every later observed member returns the unmodified original draw")
  if failures:return false
 for enemy in pending.enemies:
  var wanted:Array=[2760] if enemy.source_enemy_id==1305 else []
  var slots:Array=[0] if enemy.source_enemy_id==1305 else []
  check(enemy.source_enemy_id in [1305,1309,1310] and enemy.generated_drops==wanted and enemy.generated_drop_slots==slots,"Every actual original711 member retains its exact generated slots")
  if failures:return false
 check(b.session.bag_slots(b.session._profile)+b.expected_target_count<=15,"Original fixture has room for every possible controlled target; capacity not bypassed")
 if failures:return false
 var receipt:Dictionary=pending.quest_loot_receipt.duplicate(true)
 check(receipt.owner_session_id==b.session.get_instance_id() and receipt.source==expected_source and receipt.ledger.battle_id==pending.battle_id,"Real timer-issued receipt has current Session/source/battle ownership")
 if failures:return false
 if not drive_original(b,time):return false
 check(not b.battle_open and b.session._pending.is_empty() and b.session._loot_settlement.is_empty() and b.battle_state.get("settled",false) and b.battle_state.outcome=="win","Original battle resolver, reward writer and original close all finish")
 if failures:return false
 check(b.expected_error.is_empty() and not b.expected_profile.is_empty() and b.settlement_calls==1 and b.close_calls==1 and b.commits==3,"Exactly two E1 commits plus one original reward+ledger commit and one close")
 if failures:return false
 var raw_drops:Array=[{"item_id":2760,"received":true}] if b.expected_target_count==1 else []
 var published_drops:Array=[]
 if b.expected_target_count==1:
  published_drops.append({"item_id":2760,"received":true,"name":str(b.quest_catalog.items.get("2760",{}).get("name","原版物品 #2760"))})
 check(b.original_result.drop_summary==raw_drops and b.battle_state.drop_summary==published_drops,"Actual received entries plus independently expected publication names, or exact empty result when1305 absent")
 if failures:return false
 check(b.session.snapshot()==b.expected_profile and b.session._profile==b.expected_profile,"Complete native profile equals independent counterfactual reward baseline plus exact one UID/ledger transition")
 if failures:return false
 var target_uid:int=int(b.before_reward.next_original_uid)
 var target_instances:Array=[]
 if b.expected_target_count==1:target_instances.append({"uid":target_uid,"item_id":2760,"durability":int(b.session.OriginalEquipment.ITEMS.get(2760,{}).get("durability",0))})
 check(b.session._profile.original_items.count(2760)==b.expected_target_count and b.session._profile.original_instances.filter(func(item):return item.item_id==2760)==target_instances and b.session._profile.next_original_uid==target_uid+b.expected_target_count,"Exact target quantity and independently predicted UID; no UID allocated when actual1305 absent")
 if failures:return false
 var entry:Dictionary=b.session._profile.quest_loot.entries[KEY]
 var old_entry:Dictionary=before_e2.quest_loot.entries[KEY]
 check(entry.limit_ms==old_entry.limit_ms and entry.budget_id==old_entry.budget_id and entry.generation==old_entry.generation and entry.saved_battles==old_entry.saved_battles+1 and entry.new_items==old_entry.new_items+b.expected_target_count and not entry.open_span,"Budget identity/limit preserved, one battle and exact actual target quantity counted")
 if failures:return false
 check(b.settlement_primary==JSON.stringify(b.expected_profile).to_utf8_buffer() and b.settlement_backup==b.previous_primary and FileAccess.get_file_as_bytes(b.save_path)==b.settlement_primary and FileAccess.get_file_as_bytes(b.save_path+".bak")==b.settlement_backup and b.last_saved_payload==b.settlement_primary.get_string_from_utf8() and not FileAccess.file_exists(b.save_path+".tmp"),"Full primary bytes and predecessor backup generation match independent complete candidate; original close adds no disk mutation")
 if failures:return false
 var backup:Dictionary=ProfileCompare.validated_copy(b.session,b.settlement_backup.get_string_from_utf8())
 check(backup.get("ok",false) and backup.profile==before_e2,"Complete independent backup oracle is exact pre-battle E1 saved profile")
 if failures:return false
 var loaded=ControlledSession.new()
 check(loaded.load_game(b.save_path) and loaded.last_load_source=="primary" and loaded.snapshot()==b.expected_profile and FileAccess.get_file_as_bytes(b.save_path)==b.settlement_primary and FileAccess.get_file_as_bytes(b.save_path+".bak")==b.settlement_backup,"Actual fresh Session primary load equals entire settled expected profile and UID")
 if failures:return false
 var frozen:Dictionary=retained_fact(b)
 check(not b.session.apply_battle_result(b.original_result.duplicate(true)) and b.session.prepare_loot_settlement(receipt,str(pending.battle_id)).is_empty(),"Consumed original result and receipt cannot manufacture another settlement")
 if failures:return false
 check(not b._commit_loot_settlement(b.settlement_frame).get("ok",true) and retained_fact(b)==frozen,"Replay of actual retained commit frame cannot write or grant twice; complete memory/primary/backup/serial unchanged")
 if failures:return false
 var closed:Dictionary=b.handle({"type":"battle_close","battle_id":pending.battle_id})
 check(closed.get("ok",true)==false and closed.get("stale",false)==true and retained_fact(b)==frozen,"Repeated original public battle_close is stale; no second close/write/reward/UID")
 if failures:return false
 var reloaded=ControlledSession.new()
 check(reloaded.load_game(b.save_path) and reloaded.last_load_source=="primary" and reloaded.snapshot()==b.expected_profile,"Primary complete load remains exact after duplicate receipt/close probes")
 if failures:return false
 print("CONTROLLED_2760_FACT ",JSON.stringify({"group":711,"actual_members":pending.enemies.map(func(enemy):return enemy.source_enemy_id),"member_calls":catalog.member_calls,"member_super_calls":catalog.member_super_calls,"forced_members":catalog.forced_members,"member_records":catalog.member_records,"later_member_calls":catalog.member_calls-1,"target_count":b.expected_target_count,"slot":0,"forced":true,"natural":false,"received":b.expected_target_count==1,"uid":target_uid if b.expected_target_count==1 else null,"receipt":receipt,"commits":b.commits,"settlements":b.settlement_calls,"close_calls":b.close_calls,"serial":b.quest_save_serial,"primary_sha256":b.settlement_primary.hex_encode().sha256_text(),"primary_sha_kind":"sha256-of-hex-encoded-bytes","ledger":entry}))
 return true
func run()->void:
 var b=Controlled2760Backend.new()
 var passed:bool=controlled_case(b)
 # Release only the test-retained frame (strong observer references), not live authority.
 b.settlement_frame={}
 b.free()
 if not passed or failures:quit(1);return
 print("CONTROLLED LOOT 2760: PASS; fixed711/first-member1305/original-count-and-draws/forced-slot0; real receipt/reward/UID/primary; duplicate result/receipt/close inert; NOT NATURAL")
 quit(0)
