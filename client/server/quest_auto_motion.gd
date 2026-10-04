extends RefCounted
## Position receipts are acknowledgements of server moves, never move authority.
const IDENTITY_FIELDS=["quest_run_id","quest_step_id","quest_revision","quest_segment_id"]
static func tagged(command:Dictionary)->bool:
 if command.has("quest_position_seq"):return true
 for field in IDENTITY_FIELDS:
  if command.has(field):return true
 return false
static func integer(value:Variant)->Variant:
 if not (value is int or value is float):return null
 if not is_finite(float(value)) or float(value)!=floor(float(value)) or value<0 or value>2147483647:return null
 return int(value)
static func cell(value:Variant)->Array:
 if not value is Array or value.size()!=2:return []
 var x=integer(value[0])
 var y=integer(value[1])
 return [] if x==null or y==null else [x,y]
static func same_integer(first:Variant,second:Variant)->bool:
 var value=integer(first)
 return value!=null and value==integer(second)
static func matches(command:Dictionary,receipt:Dictionary,identity)->bool:
 if receipt.get("quest_run_id","")!=identity.run_id or receipt.get("quest_step_id","")!=identity.step_id or not same_integer(receipt.get("quest_revision"),identity.revision):return false
 var actual:Array=cell(command.get("cell"))
 if actual.is_empty() or actual!=cell(receipt.get("cell")) or not same_integer(command.get("quest_position_seq"),receipt.get("seq")) or not same_integer(command.get("map_id"),receipt.get("map_id")):return false
 var complete:=false
 for field in IDENTITY_FIELDS:
  if command.has(field):complete=true
 if receipt.get("quest_segment",{}).get("mode","A") in ["B","C"] and not complete:return false
 if complete:
  for field in IDENTITY_FIELDS:
   if not command.has(field):return false
   if field=="quest_revision":
    if not same_integer(command[field],receipt.get(field)):return false
   elif command[field]!=receipt.get(field):return false
 # No identity fields is the old A client protocol, scoped to current receipts.
 return true
static func packet(identity,serial:int,point:Dictionary,origin:Dictionary,ack_required:bool)->Dictionary:
 var map_id=integer(point.get("map_id"))
 var position:Array=cell(point.get("cell"))
 var from_map=integer(origin.get("map_id",point.get("map_id")))
 var from_cell:Array=cell(origin.get("cell",point.get("cell")))
 if map_id==null or from_map==null or position.is_empty() or from_cell.is_empty():return {}
 var segment_id:String=identity.run_id+":"+str(serial)
 return {"type":"position","map_id":map_id,"cell":position,"client":"quest_auto","quest_position_seq":serial,"quest_run_id":identity.run_id,"quest_step_id":identity.step_id,"quest_revision":identity.revision,"quest_segment_id":segment_id,"quest_segment_index":1,"quest_segment_done":true,"quest_ack_required":ack_required,"quest_segment":{"id":segment_id,"mode":"A","kind":"walk","from_map":from_map,"from_cell":from_cell,"cells":[{"map_id":map_id,"cell":position.duplicate()}],"interval_seconds":0.2}}
