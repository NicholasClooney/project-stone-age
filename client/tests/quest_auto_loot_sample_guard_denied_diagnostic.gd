extends "res://tests/quest_auto_loot_sample_guard_test.gd"
## Passive diagnostic. NOT the five-fixture suite or a replacement PASS.
## No producer changes, callback result changes, clock/Wait/tick changes.
var diagnostic_failed:bool=false
func diagnostic_error(reason:String)->void:
 if diagnostic_failed:return
 diagnostic_failed=true
 print("DIAGNOSTIC ERROR: "+reason)
func diagnostic_value(value):
 match typeof(value):
  TYPE_DICTIONARY:
   var result:Dictionary={}
   for key in value:
    result[str(key)]=diagnostic_value(value[key])
    if diagnostic_failed:return result
   return result
  TYPE_ARRAY:
   var result:Array=[]
   for item in value:
    result.append(diagnostic_value(item))
    if diagnostic_failed:return result
   return result
  TYPE_OBJECT:
   if value==null:return null
   if not is_instance_valid(value):
    diagnostic_error("Invalid Object leaf; no property read")
    return {"invalid_object":true}
   # Leaf descriptor only: never traverse owner links or call snapshot/clock.
   var script=value.get_script()
   if script!=null and not is_instance_valid(script):
    diagnostic_error("Invalid Script leaf; no resource_path read")
    return {"invalid_script":true}
   return {"diagnostic_object_id":str(value.get_instance_id()),"class":value.get_class(),"script":script.resource_path if script is Script else ""}
  TYPE_CALLABLE:return {"diagnostic_callable":str(value)}
  TYPE_SIGNAL:return {"diagnostic_signal":str(value)}
  TYPE_VECTOR2I:return {"type":"Vector2i","x":value.x,"y":value.y}
  TYPE_VECTOR2:return {"type":"Vector2","x":value.x,"y":value.y}
  TYPE_PACKED_BYTE_ARRAY:return {"type":"PackedByteArray","hex":value.hex_encode()}
 return value
func diagnostic_script_fields(owner)->Dictionary:
 var values:Dictionary={}
 if not is_instance_valid(owner):
  diagnostic_error("Invalid script_fields owner; no property read")
  return {"invalid_owner":true}
 for property in owner.get_property_list():
  if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0:continue
  values[str(property.name)]=diagnostic_value(owner.get(property.name))
  if diagnostic_failed:return values
 return values
func diagnostic_guard(stage:String,name:String,weak_host:WeakRef)->void:
 var host=weak_host.get_ref()
 var record:Dictionary={"stage":stage,"guard":name,"armed":p2_armed,"mode":p2_mode,"visits":p2_visits,"parties":p2_parties,"clock":p2_clock_reads,"stack":get_stack(),"owner_alive":is_instance_valid(host)}
 if not is_instance_valid(host):
  print("P2 GUARD DIAGNOSTIC ",JSON.stringify(record))
  diagnostic_error("Guard observation has no live host")
  return
 if not is_instance_valid(host.quest_auto) or not is_instance_valid(host.quest_loot):
  print("P2 GUARD DIAGNOSTIC ",JSON.stringify(record))
  diagnostic_error("Guard observation has no live runner/timer")
  return
 if is_instance_valid(host):
  record.running=host.quest_auto.running;record.phase=host.quest_auto.phase
  record.attempt_call_present=host.quest_loot.attempt_call!=null
  record.depth=host._depth;record.process_depth=host._process_depth
  record.flush_depth=host._flush_depth;record.observer_depth=host._observer_depth
 print("P2 GUARD DIAGNOSTIC ",JSON.stringify(record))
func visit_probe(weak_host:WeakRef)->String:
 diagnostic_guard("before","visit",weak_host)
 var result:String=super.visit_probe(weak_host)
 if failures:return result
 if diagnostic_failed:failures+=1;return result
 diagnostic_guard("after","visit",weak_host)
 if diagnostic_failed:failures+=1
 return result
func party_probe(weak_host:WeakRef)->String:
 diagnostic_guard("before","party",weak_host)
 var result:String=super.party_probe(weak_host)
 if failures:return result
 if diagnostic_failed:failures+=1;return result
 diagnostic_guard("after","party",weak_host)
 if diagnostic_failed:failures+=1
 return result
func diagnostic_assertion(b,fields:int)->void:
 # Direct fields only. Do not call q.snapshot/_derived/projection here: those
 # would invoke source_entry and contaminate the counter being diagnosed.
 var clauses:Dictionary={"not_running":not b.quest_auto.running,"field_calls_equal":b.field_calls==fields,"visits_equal_one":p2_visits==1,"parties_equal_zero":p2_parties==0,"close_pending_empty":b.quest_loot.close_pending.is_empty(),"entry_closed":not b.session._profile.quest_loot.entries[KEY].open_span}
 var record:Dictionary={"clauses":clauses,"field_calls":b.field_calls,"initial_field_calls":fields,"visits":p2_visits,"parties":p2_parties,"clock":p2_clock_reads,"cache":b.last_saved_payload,"serial":b.quest_save_serial,"stack":get_stack(),"files":[]}
 for item in [["timer",b.quest_loot],["q",b.quest_auto],["identity",b.quest_auto.identity]]:
  record[item[0]]=diagnostic_script_fields(item[1])
  if diagnostic_failed:
   record.diagnostic_complete=false
   print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
   return
 for item in [["profile",b.session._profile],["pending",b.session._pending],["settlement",b.session._loot_settlement]]:
  record[item[0]]=diagnostic_value(item[1])
  if diagnostic_failed:
   record.diagnostic_complete=false
   print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
   return
 if diagnostic_failed:
  record.diagnostic_complete=false
  print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
  return
 for suffix in ["",".bak",".tmp"]:
  var path:String=b.save_path+suffix
  var file:Dictionary={"path":path,"directory":DirAccess.dir_exists_absolute(path),"file_exists":FileAccess.file_exists(path),"open_attempted":false,"open_error":null,"read_error":null,"declared_length":null,"actual_length":null,"valid_bytes":false}
  if file.file_exists:
   file.open_attempted=true
   var reader:FileAccess=FileAccess.open(path,FileAccess.READ)
   file.open_error=FileAccess.get_open_error()
   if reader==null:
    record.files.append(file);record.diagnostic_complete=false
    print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
    diagnostic_error("Disk open failed: "+path+" error="+str(file.open_error))
    return
   file.declared_length=reader.get_length()
   file.length_error=reader.get_error()
   if file.length_error!=OK:
    reader.close();record.files.append(file);record.diagnostic_complete=false
    print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
    diagnostic_error("Disk length read failed: "+path+" error="+str(file.length_error))
    return
   var bytes:PackedByteArray=reader.get_buffer(int(file.declared_length))
   file.read_error=reader.get_error();file.actual_length=bytes.size()
   reader.close()
   # Keep even incomplete bytes as evidence, never label them valid empty disk.
   file.hex=bytes.hex_encode()
   file.valid_bytes=file.open_error==OK and file.read_error==OK and file.actual_length==file.declared_length
   if not file.valid_bytes:
    record.files.append(file);record.diagnostic_complete=false
    print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
    diagnostic_error("Disk read failed/short: "+path+" error="+str(file.read_error)+" declared="+str(file.declared_length)+" actual="+str(file.actual_length))
    return
  record.files.append(file)
  if suffix=="" and not file.file_exists:
   record.diagnostic_complete=false
   print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
   diagnostic_error("Primary disk missing; no valid empty disk inferred")
   return
 record.diagnostic_complete=true
 print("P2 GUARD DENIED BEFORE ORIGINAL ASSERTION ",JSON.stringify(record))
func run()->void:
 var mode:String="guard_denied"
 reset_probe(mode)
 var b=SampleBackend.new();var time:Array=[1000]
 if not await reopen_fixture(b,"user://loot-p2-guard-"+mode+".json",time):b.free();quit(1);return
 var fields:int=b.field_calls
 time[0]=b.quest_loot.anchor_ms+1000
 if not await one_normal_tick(b):b.free();quit(1);return
 diagnostic_assertion(b,fields)
 if diagnostic_failed:failures+=1
 if failures:b.free();quit(1);return
 check(not b.quest_auto.running and b.field_calls==fields and p2_visits==1 and p2_parties==0 and b.quest_loot.close_pending.is_empty() and not b.session._profile.quest_loot.entries[KEY].open_span,"Same-owner denied guard retains original real close policy")
 if failures:b.free();quit(1);return
 if not complete_disk(b):b.free();quit(1);return
 print("P2 GUARD COMPLETE ",mode," visits=",p2_visits," parties=",p2_parties," clock=",p2_clock_reads)
 b.free()
 print("QUEST AUTO LOOT SAMPLE GUARD DENIED DIAGNOSTIC: 0 failures; one original equivalent fixture ONLY")
 quit(0)
