extends RefCounted
## Entry-only fact, never a second purchase debit or a capability.
const J=preload("res://server/fee_attempt_lifecycle.gd")
const E=preload("res://server/fee_start_journal_writer.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
const KEYS=["schema","scope","origin","owner","transaction_id","fee_kind","phase","run_id","step_id","attempt_id","source_id","currency","amount","balance_before","balance_after","item_id","ticket_uid","consumed_ticket_uid","destination","status","durability","save_serial","candidate_sha256"]
static func valid(v:Variant)->bool:
 if not v is Dictionary or not J.exact_keys(v,KEYS):return false
 if not v.owner is Dictionary or not J.exact_keys(v.owner,["profile_id","character_id"]) or E.owner(v.owner).is_empty():return false
 for key in ["scope","origin","fee_kind","phase","step_id","source_id","currency","status","durability","candidate_sha256"]:
  if not v[key] is String:return false
 if not J.strict_int(v.schema,1,1) or v.scope!="profile" or v.origin!="explicit_start" or v.fee_kind!="golden44_ticket_entry" or v.phase!="ticket_entry":return false
 if not J.opaque(v.transaction_id) or not J.opaque(v.run_id) or not J.opaque(v.attempt_id):return false
 if v.transaction_id in [v.run_id,v.attempt_id] or v.run_id==v.attempt_id:return false
 if not Source.GATES.has(v.source_id) or v.step_id!="golden44:entry:"+v.source_id:return false
 if v.currency!="stone" or v.status!="committed" or v.durability!="disk":return false
 if not J.strict_int(v.amount,0,0) or not J.strict_int(v.balance_before,0,1000000000) or not J.strict_int(v.balance_after,0,1000000000) or v.balance_before!=v.balance_after:return false
 var gate:Array=Source.GATES[v.source_id]
 if not J.strict_int(v.item_id,2755,2757) or v.item_id!=gate[3] or not J.strict_int(v.ticket_uid,1) or not J.strict_int(v.consumed_ticket_uid,1):return false
 if not v.destination is Dictionary or not J.exact_keys(v.destination,["map_id","x","y"]):return false
 for key in ["map_id","x","y"]:
  if not J.strict_int(v.destination[key]):return false
 if v.destination!={"map_id":gate[2],"x":14,"y":26}:return false
 return J.strict_int(v.save_serial,0,9223372036854775807) and v.candidate_sha256.length()==64 and v.candidate_sha256.is_valid_hex_number()
