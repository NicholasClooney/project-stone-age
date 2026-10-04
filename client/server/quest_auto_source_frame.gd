extends RefCounted
## Dormant in-memory call/page ownership. No backend, save, RNG or RPC access.
const Motion=preload("res://server/quest_auto_motion.gd")
const Source=preload("res://server/quest_auto_source_actions.gd")
var identity:Dictionary={}
var connection:=-1
var npc_id:=""
var source_id:=""
var page:Dictionary={}
var consumed:Dictionary={}
var produced:Dictionary={}
var _call:RefCounted
var _publication_depth:=0
var _saved_serial:=-1
var _save_open:=false
var _cancelled:=false
var _detached:=false

static func valid_identity(value:Dictionary)->bool:
 return Source.exact_keys(value,["run_id","step_id","revision"]) and value.get("run_id") is String and value.run_id.length()==32 and value.run_id.is_valid_hex_number() and value.get("step_id") is String and not value.step_id.is_empty() and Motion.integer(value.get("revision"))!=null
func configure(value:Dictionary,peer:int,npc:String,source:String)->bool:
 if not identity.is_empty() or not valid_identity(value) or peer<0 or npc.is_empty() or source.is_empty():return false
 identity=value.duplicate(true);connection=peer;npc_id=npc;source_id=source
 return true
func matches(value:Dictionary,peer:int)->bool:
 return not _cancelled and not _detached and not identity.is_empty() and Source.same_source(value,identity) and peer==connection
func begin_call(value:Dictionary,peer:int)->RefCounted:
 if _call!=null or not matches(value,peer):return null
 _call=RefCounted.new()
 _saved_serial=-1;_save_open=true;_publication_depth=0
 return _call
## Only the core's original save boundary may call this, before any emit/flush.
## Passing a later serial from a generic before/after comparison is forbidden.
func record_saved(call:RefCounted,serial:int)->bool:
 if call==null or call!=_call or not _save_open or _publication_depth!=0 or serial<0:return false
 _saved_serial=serial;_save_open=false
 return true
func enter_publication(call:RefCounted)->void:
 if call!=null and call==_call:_publication_depth+=1
func leave_publication(call:RefCounted)->void:
 if call!=null and call==_call:_publication_depth=maxi(0,_publication_depth-1)
func close_save_window(call:RefCounted)->void:
 if call!=null and call==_call:_save_open=false
func complete_call(call:RefCounted,value:Dictionary,peer:int)->Dictionary:
 if call==null or call!=_call:return {"ok":false,"committed":false,"continued":false}
 var result:Dictionary={"ok":true,"committed":_saved_serial>=0,"continued":matches(value,peer),"save_serial":_saved_serial}
 _call=null;_save_open=false;_publication_depth=0
 return result

static func public_page(value:Dictionary)->bool:
 if not value.get("token") is String or value.token.is_empty() or not value.get("npc_id") is String or not value.get("text") is String or not value.get("choices") is Array:return false
 if not value.get("input","choice") in ["choice","text"]:return false
 for key in value:
  if key not in ["token","npc_id","name","text","choices","input","kind"]:return false
 var ids:Dictionary={}
 for choice in value.choices:
  if not choice is Dictionary or not Source.exact_keys(choice,["id","text"]) or not choice.id is String or choice.id.is_empty() or not choice.text is String or ids.has(choice.id):return false
  ids[choice.id]=true
 return not ids.is_empty()
## Mark each page made by this call, even when cancellation occurred in save's
## publication. Cleanup later compares the exact token and never clears a newer
## manual page. The core must not pass unrelated pending state as this reply.
func receive_page(call:RefCounted,value:Dictionary,pending_token:String)->bool:
 if call==null or call!=_call or not public_page(value) or value.npc_id!=npc_id or value.token!=pending_token or consumed.has(value.token) or produced.has(value.token):return false
 produced[value.token]=true
 if _cancelled:return false
 page=value.duplicate(true)
 return not _detached
func take_choice(value:Dictionary,peer:int,token:String,choice:String,text:String="")->Dictionary:
 if not matches(value,peer) or page.is_empty() or page.token!=token or consumed.has(token):return {}
 if not page.choices.any(func(option):return option.id==choice):return {}
 if text.length()>120 or (page.get("input","choice")!="text" and not text.is_empty()):return {}
 # Reserve before invoking the original service. Failure consumes this token;
 # only a genuinely new public reply may ever be attempted again.
 consumed[token]=true
 page.clear()
 return {"token":token,"choice":choice,"text":text}
func cancel()->void:
 _cancelled=true
 page.clear()
func detach()->void:
 _detached=true
func rebind(value:Dictionary,peer:int,pending_token:String)->bool:
 if _cancelled or not _detached or _call!=null or peer<0 or not valid_identity(value) or page.is_empty() or page.token!=pending_token or consumed.has(pending_token):return false
 if value.run_id!=identity.run_id or value.step_id!=identity.step_id or int(value.revision)<=int(identity.revision):return false
 identity=value.duplicate(true);connection=peer;_detached=false
 return true
func owns_pending(token:String)->bool:
 return not token.is_empty() and produced.has(token)
