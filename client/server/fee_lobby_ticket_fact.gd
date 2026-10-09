extends RefCounted
## Purchase-only tagged JSON fact. This pure validator grants no authority.
const J=preload("res://server/fee_attempt_lifecycle.gd")
const E=preload("res://server/fee_start_journal_writer.gd")
const KEYS=["schema","scope","origin","owner","transaction_id","fee_kind","phase","run_id","step_id","attempt_id","source_id","offer_id","currency","amount","balance_before","balance_after","item_id","ticket_uid","status","durability","save_serial","candidate_sha256"]
static func valid(v:Variant)->bool:
 if not v is Dictionary or not J.exact_keys(v,KEYS):return false
 if not v.owner is Dictionary or not J.exact_keys(v.owner,["profile_id","character_id"]) or E.owner(v.owner).is_empty():return false
 for key in ["scope","origin","fee_kind","phase","step_id","source_id","offer_id","currency","status","durability","candidate_sha256"]:
  if not v[key] is String:return false
 if not J.strict_int(v.schema,1,1) or v.scope!="profile" or v.origin!="explicit_start" or v.fee_kind!="golden44_lobby_ticket" or v.phase!="ticket_purchase" or v.step_id!="golden44:lobby_purchase":return false
 if not J.opaque(v.transaction_id) or not J.opaque(v.run_id) or not J.opaque(v.attempt_id):return false
 if v.transaction_id in [v.run_id,v.attempt_id] or v.run_id==v.attempt_id:return false
 if v.currency!="stone" or v.status!="committed" or v.durability!="disk":return false
 if not J.strict_int(v.amount,1,1000000000) or not J.strict_int(v.balance_before,v.amount,1000000000) or not J.strict_int(v.balance_after,0,1000000000) or v.balance_after!=v.balance_before-v.amount:return false
 if not J.strict_int(v.item_id,2755,2757) or not J.strict_int(v.ticket_uid,1) or not J.strict_int(v.save_serial,0,9223372036854775807):return false
 if v.candidate_sha256.length()!=64 or not v.candidate_sha256.is_valid_hex_number():return false
 match v.item_id:
  2755:return v.source_id=="quiz/uketuke" and v.offer_id=="quiz/uketuke@2020:18:13:2" and v.amount%20==0 and v.amount>=600 and v.amount<=980
  2756:return v.source_id=="quiz/uketuke" and v.offer_id=="quiz/uketuke@2020:18:13:1" and v.amount%40==0 and v.amount>=2000 and v.amount<=2760
  2757:return v.source_id=="quiz/uketuke2" and v.offer_id=="quiz/uketuke2@4020:18:13:0" and v.amount%40==0 and v.amount>=2800
 return false
