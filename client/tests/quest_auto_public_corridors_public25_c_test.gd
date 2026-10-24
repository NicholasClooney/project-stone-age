extends "res://tests/support/quest_auto_public25_support.gd"
## Explicit player walk back to Jaja after24, then a fresh manual25 start.
## Not continuous25 acceleration. No event/proof/position injection after24.
## Observe only actual packets; no extra planning, refresh or RNG changes.
func drive(b,mode:String,job:int)->bool:
 var previous:Dictionary={"map_id":b.automation.position_map,"cell":[b.automation.position_cell.x,b.automation.position_cell.y]}
 var moves:Array=[]
 var counts:Dictionary={"stride_packets":0,"prefix_max":0,"protected_packets":0}
 var first_field:int=b.field_calls.size()
 var observer:Callable=func(event:Dictionary):
  if event.get("type")!="position" or not event.has("quest_segment_id"):return
  var map_id:int=int(event.map_id)
  var cell:Vector2i=point(event.cell)
  var old:Vector2i=point(previous.cell)
  var old_map:int=previous.map_id
  var segment:Dictionary=event.get("quest_segment",{})
  var kind:String=str(segment.get("kind","walk"))
  if old_map==map_id and old!=cell:
   check(absi(old.x-cell.x)+absi(old.y-cell.y)==1,"C actual committed movement is one adjacent original logical cell")
   moves.append({"map_id":map_id,"cell":[cell.x,cell.y]})
  if walk_protected(old_map,old) or walk_protected(map_id,cell):
   check(kind not in ["public_stride","public_jump"],"Every actual protected position uses original walk/portal, never fast movement")
   counts.protected_packets+=1
  if kind=="public_stride":
   counts.stride_packets+=1
   var prefix:Array=segment.get("cells",[])
   counts.prefix_max=maxi(counts.prefix_max,prefix.size())
   check(not prefix.is_empty() and prefix.size()<=3,"C actual full published prefix contains one to three logical cells")
   var preceding:Vector2i=point(segment.get("from_cell",[]))
   check(int(segment.get("from_map",-1))==map_id,"C prefix stays in its original map")
   for entry in prefix:
    var next:Vector2i=point(entry.cell)
    check(int(entry.map_id)==map_id and absi(next.x-preceding.x)+absi(next.y-preceding.y)==1,"Every C prefix cell is adjacent from the actual segment origin")
    check(not walk_protected(map_id,next) and not b.quest_helper.places.links(map_id).has(next),"Every C prefix cell stays outside protection and original portals")
    preceding=next
   check(preceding==cell,"Actual C prefix ends exactly at reported authority")
  previous.map_id=map_id
  previous.cell=[cell.x,cell.y]
 b.event.connect(observer)
 var completed:bool=await super.drive(b,mode,job)
 b.event.disconnect(observer)
 var fields:Array=[]
 for index in range(first_field,b.field_calls.size()):
  var actual:Dictionary=b.field_calls[index]
  fields.append({"map_id":int(actual.map_id),"cell":Motion.cell(actual.cell)})
 check(fields==moves,"Complete actual original field_step sequence equals all same-map C task commits including protected walk")
 check(counts.protected_packets>0,"C real task includes protected original movement")
 if not summaries.is_empty():
  summaries[-1].c_observation=counts
  summaries[-1].c_actual_same_map_commits=moves.size()
  summaries[-1].c_field_sequence_matches=fields==moves
  summaries[-1].c_committed_cells=moves
  summaries[-1].c_original_field_cells=fields
 return completed
func run()->void:
 deadline=Clock.ticks_msec()+170000
 var b=fixture("C")
 var completed24:bool=await drive(b,"C",24)
 var returned:=false
 var completed25:=false
 if completed24:returned=await return_to_jaja(b)
 if returned:completed25=await drive(b,"C",25)
 check(completed24 and returned and completed25,"Actual24, player original exit/public walk, then independent25 all finish")
 check(Clock.ticks_msec()<deadline,"Independent public25 C remains inside condition budget")
 var output=FileAccess.open("user://public-corridors-public25-c-results.json",FileAccess.WRITE)
 if output!=null:
  output.store_string(JSON.stringify({"summaries":summaries,"actual24_portals":outbound_portals,"assertions":assertions,"failures":failures}))
  output.close()
 check(output!=null,"Retain independent public25 evidence separately from continuous25")
 b.free()
 print("QUEST AUTO PUBLIC CORRIDORS PUBLIC25 C: %d assertions, %d failures; wall_ms=%d"%[assertions,failures,Clock.ticks_msec()-began])
 quit(0 if failures==0 else 1)
