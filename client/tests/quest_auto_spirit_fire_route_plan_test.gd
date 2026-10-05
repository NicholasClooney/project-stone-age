extends SceneTree
const Plan=preload("res://server/quest_auto_spirit_fire_route_plan.gd")
var assertions:int=0
var failures:int=0
func check(ok:bool,label:String)->bool:
 assertions+=1
 if not ok:failures+=1;push_error(label)
 return ok
func _initialize()->void:call_deferred("run")
func run()->void:
 var table:Dictionary=Plan.source_table()
 if not check(not table.is_empty(),"complete source lock"):finish();return
 if not check(table.version==2 and table.runtime_raw_records.size()==7 and table.offline_audit.commit=="43432997e6069574c4b772ab00355c77b4e33fe3" and table.offline_audit.sha256=="46d203d0e0ad38d6aaef89fb5d96c4d9fac2aafa063309e515225e66b0dea976","layered source retains immutable full audit reference"):finish();return
 for key in table.runtime_raw_records:
  var row:Dictionary=table.runtime_raw_records[key]
  var bytes:PackedByteArray=Marshalls.base64_to_raw(str(row.bytes_base64))
  var context:HashingContext=HashingContext.new()
  if not check(context.start(HashingContext.HASH_SHA256)==OK,"raw record hash starts"):finish();return
  if not check(context.update(bytes)==OK,"raw record hash updates"):finish();return
  if not check(bytes.size()==int(row.byte_length) and context.finish().hex_encode()==row.sha256 and row.full_source_sha256==table.offline_audit.source_hashes[row.source],"raw exact record bytes and full-source link"):finish();return
 var price:Dictionary=table.runtime_raw_records.item2422_price
 if not check(price.first_line==2005 and price.last_line==2005 and table.price_rows[0].full_columns[16]=="2422" and table.price_rows[0].full_columns[18]=="200","full original price row retained, no guessed field"):finish();return
 for pair in [["permit200",200],["seimu300",300]]:
  var fee:String=pair[0]
  var amount:int=pair[1]
  var low:Dictionary=Plan.fee_contract(fee,amount-1)
  if not check(low.stage=="insufficient_gold" and low.amount==amount and low.shortfall==1 and not low.has("fee_contract"),"insufficient funds stop"):finish();return
  for gold in [amount,amount+1]:
   var enough:Dictionary=Plan.fee_contract(fee,gold)
   if not check(enough.stage=="manual_core_contract" and enough.fee_contract.amount==amount and enough.advisory_only and not enough.has("step"),"funds never create executable fee capability"):finish();return
  for invalid in [-1,1.5,true,"300",NAN,INF]:
   if not check(Plan.fee_contract(fee,invalid).stage=="invalid_gold","invalid balance rejected"):finish();return
 for fee in ["jug1150","extra_ticket","40_1_8","40_12_18","unknown"]:
  if not check(Plan.fee_contract(fee,99999).stage=="manual_unapproved_fee","unapproved fee stays manual"):finish();return
 if not check(table.permit_sellers.size()==2 and table.permit_sellers[0].current_residents[0].map_id==1100 and table.permit_sellers[1].current_residents[0].map_id==4000,"two original permit vendors"):finish();return
 var branch:Dictionary=table.seimu_npc.branches[0]
 if not check(branch.type=="FREEWARP" and branch.condition=="LV>0" and branch.actions=={"Warp":"31301,10,104","DelStone":"300"},"exact original paid Warp, no NOW46 or invented free permit condition"):finish();return
 var result:Dictionary=Plan.fee_contract("seimu300",300)
 observe_contract("before_mutation",result.fee_contract)
 result.fee_contract.amount=0
 result.fee_contract.target_cell[0]=0
 observe_contract("old_after_mutation",result.fee_contract)
 var next:Dictionary=Plan.fee_contract("seimu300",300)
 observe_contract("new_return",next.fee_contract)
 print("fee_observe original_amount_clause=",next.fee_contract.amount==300," original_cell_clause=",next.fee_contract.target_cell==[10,104])
 if not check(result.fee_contract.amount==0 and Plan.Compare.same_source(result.fee_contract.target_cell,[0,104]),"old return retains caller mutation independently"):finish();return
 if not check(next.fee_contract.amount==300 and Plan.Compare.same_source(next.fee_contract.target_cell,[10,104]),"caller cannot poison future contract"):finish();return
 finish()
func observe_contract(label:String,contract:Dictionary)->void:
 var safe:Dictionary=contract.duplicate(true)
 var cell:Variant=safe.get("target_cell")
 print("fee_observe ",label," amount=",safe.get("amount")," amount_type=",typeof(safe.get("amount"))," contract_type=",typeof(safe)," target_cell=",cell," cell_type=",typeof(cell))
 if cell is Array:
  for index in range(cell.size()):
   print("fee_observe ",label," index=",index," value=",cell[index]," type=",typeof(cell[index]))
func finish()->void:
 print("quest_auto_spirit_fire_route_plan_test: %d assertions, %d failures"%[assertions,failures])
 quit(1 if failures else 0)
