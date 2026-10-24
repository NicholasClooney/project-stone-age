extends "res://tests/quest_auto_public_corridors_execution_test.gd"
const Clock=preload("res://scripts/clock.gd")
## Diagnostic A/C only, original uncontrolled NPC births. No B repetition.
## Full sequence assertions remain strict even when inputs prove unequal.
func controlled_world()->bool:return false
func trace_label()->String:return "uncontrolled-inputs"
func planned_calls(result:Dictionary)->Array:
 var calls:Array=[]
 for entry in result.local_calls:
  if entry.in_plan:calls.append(entry)
 return calls
func compare_inputs(a:Dictionary,c:Dictionary)->Dictionary:
 var left:Array=planned_calls(a)
 var right:Array=planned_calls(c)
 var differences:Array=[]
 for index in range(maxi(left.size(),right.size())):
  if index>=left.size() or index>=right.size():
   differences.append({"index":index,"reason":"different actual local_path call counts"})
   continue
  var l:Dictionary=left[index]
  var r:Dictionary=right[index]
  var changes:Dictionary={}
  for field in ["map_id","origin","goal"]:
   if l[field]!=r[field]:changes[field]={"A":l[field],"C":r[field]}
  for field in ["occupied","occupied_sha256","npc_version","npc_snapshot","enabled_events"]:
   if l.inputs[field]!=r.inputs[field]:changes[field]={"A":l.inputs[field],"C":r.inputs[field]}
  if not changes.is_empty():differences.append({"index":index,"changes":changes})
 return {"equal":differences.is_empty(),"A_call_count":left.size(),"C_call_count":right.size(),"differences":differences}
func run()->void:
 deadline=Clock.ticks_msec()+55000
 var results:Dictionary={}
 for mode in ["A","C"]:
  results[mode]=await route(mode)
  if results[mode].is_empty() or not in_time():break
 if results.has("C") and not results.A.is_empty() and not results.C.is_empty():
  var input_comparison:Dictionary=compare_inputs(results.A,results.C)
  var differences:Dictionary={"positions":first_difference(results.A.cells,results.C.cells),"field_steps":first_difference(results.A.field_cells,results.C.field_cells)}
  var path:String="user://public-corridors-"+trace_label()+".json"
  var output=FileAccess.open(path,FileAccess.WRITE)
  if output!=null:
   output.store_string(JSON.stringify({"controlled_npc_birth":controlled_world(),"input_comparison":input_comparison,"sequence_differences":differences,"modes":results}))
   output.close()
  check(output!=null,"Retain complete actual world inputs and full sequences")
  print("WORLD INPUT COMPARISON ",JSON.stringify(input_comparison))
  print("WORLD SEQUENCE DIFFERENCES ",JSON.stringify(differences))
  print("WORLD INPUT TRACE ",ProjectSettings.globalize_path(path))
  if controlled_world():check(input_comparison.equal,"Controlled normal births yield identical complete occupied inputs, NPC projections, enabled sets and actual search origins/goals")
  check(results.A.cells==results.C.cells,"New corridor complete actual A/C movement sequence including original portal is identical")
  check(results.A.field_cells==results.C.field_cells,"A/C call original field_step on the identical full logical cell sequence")
  check(results.C.seconds>0.0 and absf(results.A.seconds/results.C.seconds-2.0)<0.05,"C simulated public cadence is approximately twice A")
 else:check(false,"Both actual A/C routes finish; no partial diagnostic success")
 check(in_time(),"A/C input diagnostic deadline not exceeded")
 print("QUEST AUTO PUBLIC CORRIDORS WORLD INPUTS controlled=%s: %d assertions, %d failures; wall_ms=%d"%[controlled_world(),assertions,failures,Clock.ticks_msec()-suite_started])
 quit(1 if failures else 0)
