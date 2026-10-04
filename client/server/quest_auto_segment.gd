extends RefCounted
## Local execution cursor, not geometry authority. Navigation must revalidate
## the entire proposal before every move; only core commits executed points.
const Motion=preload("res://server/quest_auto_motion.gd")
const Settings=preload("res://server/quest_auto_settings_rules.gd")
var proposal:Dictionary={}
var committed:Array=[]
var mode:="A"
var segment_id:=""
var owner:Dictionary={}
func clear()->void:
 proposal={};committed=[];owner={};segment_id="";mode="A"
static func shape_error(value:Dictionary,selected_mode:String,origin:Dictionary)->String:
 if selected_mode not in ["A","B","C"]:return "unknown mode"
 var kind=value.get("kind")
 var points=value.get("points")
 if kind not in ["walk","public_jump","public_stride"] or not points is Array or points.is_empty():return "invalid segment"
 if value.has("remaining"):return "navigation cannot supply execution cursor"
 if kind=="walk" and points.size()!=1:return "walk is one logical step"
 if kind=="public_jump" and (selected_mode!="B" or points.size()!=1):return "jump requires B and one endpoint"
 if kind=="public_stride" and (selected_mode!="C" or points.size()>Settings.C_MAX_CELLS):return "stride requires C and bounded cells"
 if kind!="walk" and (not value.get("audit_id") is String or value.audit_id.is_empty()):return "missing public audit"
 if not value.get("navigation_key") is String or value.navigation_key.is_empty():return "missing navigation key"
 var from_cell:Array=Motion.cell(value.get("from_cell"))
 if from_cell.is_empty() or from_cell!=Motion.cell(origin.get("cell")) or not Motion.same_integer(value.get("from_map"),origin.get("map_id")):return "stale segment origin"
 var previous:Array=from_cell
 for point in points:
  if not point is Dictionary:return "invalid point"
  # Original permit gates may omit target: fixed target authority lives in backend.
  if kind=="walk" and point.has("gate"):continue
  var cell:Array=Motion.cell(point.get("cell"))
  if cell.is_empty() or Motion.integer(point.get("map_id"))==null:return "invalid point coordinates"
  if kind!="walk":
   if point.has("portal") or point.has("gate") or not Motion.same_integer(point.map_id,value.from_map):return "fast segment cannot cross a gate or map"
   if kind=="public_stride" and absi(cell[0]-previous[0])+absi(cell[1]-previous[1])!=1:return "stride must follow adjacent cells"
   if cell==previous:return "segment must move"
  previous=cell
 return ""
func begin(value:Dictionary,selected_mode:String,origin:Dictionary,identity,serial:int)->bool:
 clear()
 if serial<1 or identity.run_id.is_empty() or identity.step_id.is_empty() or not shape_error(value,selected_mode,origin).is_empty():return false
 proposal=value.duplicate(true)
 mode=selected_mode
 owner=identity.checkpoint().duplicate(true)
 segment_id=identity.run_id+":"+str(serial)
 return true
func active(identity)->bool:
 return not proposal.is_empty() and owner==identity.checkpoint()
func complete()->bool:
 return not proposal.is_empty() and committed.size()==proposal.points.size()
func remaining()->Array:
 return [] if proposal.is_empty() else proposal.points.slice(committed.size()).duplicate(true)
func next_point(b,npc:Dictionary,navigation,identity)->Dictionary:
 if not active(identity) or complete():clear();return {}
 var expected:Dictionary=proposal.duplicate(true)
 var candidate:Dictionary=proposal.duplicate(true)
 candidate.remaining=remaining()
 if not navigation.has_method("validate_segment") or not navigation.validate_segment(b,npc,candidate):clear();return {}
 if not active(identity) or proposal!=expected or complete():clear();return {}
 # Never let a validator's mutation rewrite the retained execution proposal.
 return proposal.points[committed.size()].duplicate(true)
func commit(point:Dictionary,identity)->bool:
 if not active(identity) or complete() or point!=proposal.points[committed.size()]:return false
 committed.append(point.duplicate(true))
 return true
func interval()->float:
 return 0.2/Settings.C_SPEED_MULTIPLIER if mode=="C" and proposal.get("kind")=="public_stride" else 0.2
func packet(identity,serial:int,ack_required:bool)->Dictionary:
 if not active(identity) or committed.is_empty():return {}
 var result:Dictionary=Motion.packet(identity,serial,committed[-1],{"map_id":proposal.from_map,"cell":proposal.from_cell},ack_required)
 if result.is_empty():return {}
 var prefix:Array=[]
 for point in committed:
  var cell:Array=Motion.cell(point.get("cell"))
  var map_id=Motion.integer(point.get("map_id"))
  if cell.is_empty() or map_id==null:return {}
  prefix.append({"map_id":map_id,"cell":cell})
 result.quest_segment_id=segment_id
 result.quest_segment_index=committed.size()
 result.quest_segment_done=complete()
 result.quest_segment={"id":segment_id,"mode":mode,"kind":proposal.kind,"from_map":Motion.integer(proposal.from_map),"from_cell":Motion.cell(proposal.from_cell),"cells":prefix,"interval_seconds":interval()}
 return result
