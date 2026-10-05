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
