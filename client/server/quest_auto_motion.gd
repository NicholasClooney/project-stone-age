extends RefCounted
## Position receipts are acknowledgements of server moves, never move authority.
const IDENTITY_FIELDS=["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]
static func tagged(command:Dictionary)->bool:
 if command.has("quest_position_seq"):return true
 for field in IDENTITY_FIELDS:
  if command.has(field):return true
 return false
static func matches(command:Dictionary,receipt:Dictionary,identity)->bool:
 if receipt.get("quest_run_id","")!=identity.run_id or receipt.get("quest_step_id","")!=identity.step_id or receipt.get("quest_revision",-1)!=identity.revision:return false
 if command.get("quest_position_seq",-1)!=receipt.get("seq",-2) or command.get("map_id",-1)!=receipt.get("map_id",-2) or command.get("cell",[])!=receipt.get("cell",[]):return false
 var complete:=false
 for field in IDENTITY_FIELDS:
  if command.has(field):complete=true
 if complete:
  for field in IDENTITY_FIELDS:
   if not command.has(field) or command[field]!=receipt.get(field):return false
 # No identity fields is the old A client protocol, scoped to current receipts.
 return true
static func packet(identity,serial:int,point:Dictionary,origin:Dictionary,ack_required:bool)->Dictionary:
 var segment_id:String=identity.run_id+":"+str(serial)
 return {"type":"position","map_id":int(point.map_id),"cell":point.cell.duplicate(),"client":"quest_auto","quest_position_seq":serial,"quest_run_id":identity.run_id,"quest_step_id":identity.step_id,"quest_revision":identity.revision,"quest_segment_id":segment_id,"quest_segment_index":1,"quest_segment_done":true,"quest_ack_required":ack_required,"quest_segment":{"id":segment_id,"mode":"A","kind":"walk","from_map":int(origin.get("map_id",point.map_id)),"from_cell":origin.get("cell",point.cell).duplicate(),"cells":[{"map_id":int(point.map_id),"cell":point.cell.duplicate()}],"interval_seconds":0.2}}
