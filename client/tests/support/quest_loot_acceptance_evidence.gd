extends RefCounted
## Test-only lossless content-addressed evidence. No gameplay calls.
## SHA names refer to exact unnormalized UTF-8/raw bytes, never cropped fields.
const PROFILE_BYTES:=262144 # Disclosed test insurance, not a product limit.
const PROFILE_TOTAL:=939524096 # 896 MiB
const STATE_BYTES:=1048576
const STATE_TOTAL:=268435456 # 256 MiB
const STREAM_TOTAL:=536870912 # 512 MiB
const EVENT_BYTES:=16384
const EVENT_COUNT:=1500000
const BLOB_COUNT:=65536
var error:=""
var directory:=""
var stream:FileAccess
var index:Dictionary={}
var packs:Dictionary={}
var charged:Dictionary={"profile":0,"state":0}
var event_bytes:=0
var event_count:=0
var unflushed:=0
var aliases:Dictionary={}
func open(path:String)->bool:
 directory=path.get_base_dir()+"/blobs"
 if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(directory) or DirAccess.dir_exists_absolute(directory):return fail("existing evidence destination")
 if DirAccess.make_dir_recursive_absolute(directory)!=OK:return fail("blob directory creation failed")
 for kind in ["profile","state"]:
  var pack:=FileAccess.open(directory+"/"+kind+".pack",FileAccess.WRITE)
  if pack==null or FileAccess.get_open_error()!=OK:return fail("blob pack open failed")
  packs[kind]=pack
 stream=FileAccess.open(path,FileAccess.WRITE)
 if stream==null or FileAccess.get_open_error()!=OK:return fail("event stream open failed")
 return true
func fail(reason:String)->bool:
 if error.is_empty():error=reason
 return false
func blob(bytes:PackedByteArray,kind:String="state",encoding:String="raw")->Dictionary:
 if not error.is_empty():return {}
 var limit:int=PROFILE_BYTES if kind=="profile" else STATE_BYTES
 var total:int=PROFILE_TOTAL if kind=="profile" else STATE_TOTAL
 if bytes.size()>limit:fail("complete "+kind+" blob exceeds per-blob insurance");return {}
 var digest:String="" # Raw-byte SHA, never text conversion.
 var hash:=HashingContext.new()
 if hash.start(HashingContext.HASH_SHA256)!=OK or hash.update(bytes)!=OK:fail("blob hash failed");return {}
 digest=hash.finish().hex_encode()
 if digest.length()!=64:fail("blob hash length failed");return {}
 if index.has(digest):
  if int(index[digest].bytes)!=bytes.size():fail("blob identity mismatch");return {}
  return {"cas_sha256":digest,"bytes":bytes.size(),"encoding":encoding,"pack":index[digest].kind,"offset":index[digest].offset}
 if index.size()>=BLOB_COUNT or int(charged[kind])+bytes.size()>total:fail("complete "+kind+" evidence capacity exhausted");return {}
 var file:FileAccess=packs[kind]
 var offset:int=file.get_position()
 file.store_buffer(bytes);file.flush()
 if file.get_error()!=OK:fail("blob pack write failed");return {}
 var reader:=FileAccess.open(directory+"/"+kind+".pack",FileAccess.READ)
 if reader==null:fail("blob readback open failed");return {}
 reader.seek(offset)
 var readback:PackedByteArray=reader.get_buffer(bytes.size())
 var status:int=reader.get_error();reader.close()
 if status!=OK or readback!=bytes:fail("blob complete byte readback mismatch");return {}
 index[digest]={"bytes":bytes.size(),"kind":kind,"offset":offset}
 charged[kind]=int(charged[kind])+bytes.size()
 return {"cas_sha256":digest,"bytes":bytes.size(),"encoding":encoding,"pack":kind,"offset":offset}
func externalize(value:Variant,field:String="",depth:int=0)->Variant:
 if depth>64:fail("evidence nesting exceeds bound");return null
 if value is PackedByteArray:return blob(value,"profile","raw")
 if value is String:
  if value.length()>1024:
   var profile:bool=value.begins_with("{") and value.contains('"original_instances"') and value.contains('"player"')
   return blob(value.to_utf8_buffer(),"profile" if profile else "state","utf8")
  return value
 if value is Dictionary:
  if value.has("player") and value.has("version") and value.has("original_instances"):
   return blob(JSON.stringify(value).to_utf8_buffer(),"profile","json")
  var copy:Dictionary={}
  for key in value:copy[key]=externalize(value[key],str(key),depth+1)
  var encoded:PackedByteArray=JSON.stringify(copy).to_utf8_buffer()
  if encoded.size()>4096:return blob(encoded,"state","json-with-cas-references")
  return copy
 if value is Array:
  var copy:Array=[]
  for child in value:copy.append(externalize(child,field,depth+1))
  var encoded:PackedByteArray=JSON.stringify(copy).to_utf8_buffer()
  if encoded.size()>4096:return blob(encoded,"state","json-with-cas-references")
  return copy
 if value is Object:fail("unexpected Object in evidence");return null
 return value
func append(label:String,value:Variant)->bool:
 if not error.is_empty():return false
 var projected:Variant=externalize(value)
 if not error.is_empty():return false
 var bytes:PackedByteArray=(JSON.stringify({"event":label,"value":projected})+"\n").to_utf8_buffer()
 if stream==null or event_count>=EVENT_COUNT or bytes.size()>EVENT_BYTES or event_bytes+bytes.size()>STREAM_TOTAL:return fail("complete event stream capacity exhausted")
 stream.store_buffer(bytes)
 if stream.get_error()!=OK:return fail("event stream write failed")
 event_bytes+=bytes.size();event_count+=1;unflushed+=bytes.size()
 # Full blobs flush once on their first write. Scalar events batch at 64 KiB;
 # terminal/failed checkpoints always flush, without ever saving gameplay state.
 if unflushed>=65536 or label in ["ACCEPTANCE_RETIRED_FULL","ACCEPTANCE_RESULT","ACCEPTANCE_FAILURE","ACCEPTANCE_E1_HANDLER"]:return flush()
 return true
func flush()->bool:
 if stream==null:return fail("event stream absent")
 stream.flush();unflushed=0
 return stream.get_error()==OK or fail("event stream flush failed")
func archive(name:String,bytes:PackedByteArray,expected_sha:String)->Dictionary:
 if aliases.has(name):fail("archive alias reused");return {"ok":false}
 var reference:Dictionary=blob(bytes,"profile","raw")
 if reference.is_empty() or reference.get("cas_sha256","")!=expected_sha:fail("archive full SHA mismatch");return {"ok":false}
 aliases[name]=reference
 if not append("ACCEPTANCE_DISK_ARCHIVE",{"name":name,"blob":reference}):return {"ok":false}
 return {"ok":true,"path":directory+"/"+str(reference.pack)+".pack","offset":reference.offset,"sha256":expected_sha,"declared":bytes.size(),"actual":bytes.size()}
