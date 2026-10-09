extends "res://tests/support/fee_entry_harness.gd"
const Fact=preload("res://server/fee_lobby_ticket_entry_fact.gd")
func good(level:int,map_id:int,mode:String="",different:bool=false)->void:
 var c:Dictionary=setup("good-%d-%d-%s-%s"%[level,map_id,mode,different],level,map_id)
 if c.get("bad",false):finish(c);return
 if different:
  # Fixture privilege: valid inventory substitution through real equipment
  # mutators + real save, not a claim that storage/discard is allowed mid-run.
  var v:Dictionary=c.paid.duplicate(true);var index:int=v.original_items.find(c.item)
  v.original_items.remove_at(index);v.original_instances.remove_at(index)
  v.original_items.append(c.item);v.original_instances.append({"uid":v.next_original_uid,"item_id":c.item,"durability":0});v.next_original_uid+=1
  E.remove(c.s._profile,c.item);E.add(c.s._profile,c.item)
  check(c.b.save() and c.s._profile==v,c.tag+": independent valid replacement inventory")
  c.paid=v
 if not open_page(c):finish(c);return
 var expected:Dictionary=expected_entry(c)
 c.b.entry_mode=mode;c.b.source_turn()
 check(c.b.entry_writes==1 and c.b.entry_candidates==[expected],c.tag+": real original candidate plus entry journal only")
 disk(c,expected,c.before_entry)
 var live:Dictionary=expected.duplicate(true)
 if mode in ["owner_after_mark","position_successor"]:live.character_id="100005"
 check(c.s._profile==live and c.b.last_saved_payload==JSON.stringify(expected) and c.b.quest_save_serial==c.before_serial+1,c.tag+": complete live/cache/serial")
 check(c.b.facts.size()==2 and c.b.facts[0]==c.purchase_facts[0],c.tag+": purchase unchanged, one independent entry fact")
 if c.b.facts.size()==2:
  var observed:Dictionary=c.b.facts[1]
  var purchase:Dictionary=c.before_entry.quest_auto_fee_lifecycle.current.purchase
  var source:String="genout/wpm_%d_%d_20"%[map_id,29 if level>=70 else (28 if level>=50 else 30)]
  var fact:Dictionary={"schema":1,"scope":"profile","origin":"explicit_start","owner":{"profile_id":expected.profile_id,"character_id":expected.character_id},"transaction_id":observed.transaction_id,"fee_kind":"golden44_ticket_entry","phase":"ticket_entry","run_id":expected.quest_auto_fee_lifecycle.current.run_id,"step_id":"golden44:entry:"+source,"attempt_id":purchase.attempt_id,"source_id":source,"currency":"stone","amount":0,"balance_before":c.before_entry.player.gold,"balance_after":c.before_entry.player.gold,"item_id":c.item,"ticket_uid":purchase.ticket_uid,"consumed_ticket_uid":c.consumed,"destination":expected.location.duplicate(true),"status":"committed","durability":"disk","save_serial":c.before_serial+1,"candidate_sha256":JSON.stringify(expected).sha256_text()}
  check(observed==fact and Fact.valid(fact),c.tag+": whole independent zero-amount fact")
  check(observed.transaction_id!=c.purchase_facts[0].transaction_id and observed.transaction_id!=purchase.attempt_id and observed.transaction_id!=fact.run_id,c.tag+": independent transaction id")
  if different:check(observed.consumed_ticket_uid!=observed.ticket_uid,c.tag+": actual consumed UID may differ")
  for key in fact:
   for bad in [null,false,[],{},1.0]:
    var invalid:Dictionary=fact.duplicate(true);invalid[key]=bad
    check(not Fact.valid(invalid),c.tag+": strict malformed "+key)
  for field in ["profile_id","character_id"]:
   for bad in [null,false,1,[],{}]:
    var invalid:Dictionary=fact.duplicate(true);invalid.owner[field]=bad
    check(not Fact.valid(invalid),c.tag+": strict owner")
  for field in ["map_id","x","y"]:
   for bad in [null,false,[],1.0,-1]:
    var invalid:Dictionary=fact.duplicate(true);invalid.destination[field]=bad
    check(not Fact.valid(invalid),c.tag+": strict destination")
 if mode not in ["owner_after_mark","source_after_mark"]:
  check(c.b.automation.position_map==expected.location.map_id and c.b.automation.position_cell==Vector2i(14,26),c.tag+": true Warp publication")
  var position:Array=c.b.events.slice(c.events_before).filter(func(v):return v.get("type")=="position")
  check(position.size()==1 and position[0].map_id==expected.location.map_id and position[0].cell==[14,26],c.tag+": exactly one original destination event")
 elif mode=="owner_after_mark":check(c.b.automation.position_map==map_id and c.b.successor.profile==live,c.tag+": postmark successor not warped")
 else:check(c.b.automation.position_map==map_id and c.b._quest_source_call=={"successor":true} and c.b.original_quests.pending=={"token":"successor-page"},c.tag+": old source cannot clear successor registry/page")
 var frozen:Array=rows(c);var profile:Dictionary=c.s._profile.duplicate(true);var serial:int=c.b.quest_save_serial
 var replay:Dictionary=c.b.source_repeat({"token":c.token,"choice":"yes","text":""})
 check(not replay.get("ok",false) and rows(c)==frozen and c.s._profile==profile and c.b.quest_save_serial==serial and c.b.facts.size()==2,c.tag+": used real token cannot reenter")
 finish(c)
func failed(mode:String,read_mode:String="")->void:
 var c:Dictionary=setup("failed-"+mode+"-"+read_mode)
 if not open_page(c):finish(c);return
 var expected:Dictionary=expected_entry(c)
 c.b.entry_mode=mode;c.s.entry_read_mode=read_mode;c.b.source_turn()
 var wrote:bool=not mode in ["false_before","forged_raw","forged_ok","unrelated"] and read_mode!="pre_unknown"
 check(c.b.facts==c.purchase_facts,c.tag+": no manufactured entry fact")
 if wrote:disk(c,expected,c.before_entry)
 else:check(rows(c)==c.before_rows,c.tag+": complete no-write oracle")
 var memory:Dictionary=expected if mode=="false_after" else c.before_entry
 if mode=="owner" or read_mode=="read_owner":memory=memory.duplicate(true);memory.character_id="100005"
 check(c.s._profile==memory,c.tag+": independent full memory, never inferred from terminal disk")
 check(c.b.automation.position_map==c.map and c.b.automation.position_cell==Vector2i(30,22),c.tag+": no Warp after unconfirmed write")
 var expected_serial:int=c.before_serial+(1 if mode=="false_after" else (7 if mode=="serial" else 0))
 check(c.b.quest_save_serial==expected_serial and c.b.last_saved_payload==JSON.stringify(expected if mode=="false_after" else c.before_entry),c.tag+": exact cache/serial")
 if mode=="pending":check(c.b.original_quests.pending=={"token":"successor-page"},c.tag+": late old reply does not clear successor page")
 if read_mode=="post_unknown":
  check(c.b._fee_lobby_ticket.held(c.b) and c.b._fee_lobby_ticket.HOLD_TEXT=="入场结果未确认，请重新进入存档",c.tag+": actual entry unknown precise hold")
  var frozen:Array=rows(c);var snapshots:int=c.s.snapshot_calls
  check(not c.b.save() and c.s.snapshot_calls==snapshots and rows(c)==frozen,c.tag+": generic rejected before snapshot")
  check(not c.s.save_game(c.path) and rows(c)==frozen and c.s.last_error=="入场结果未确认，请重新进入存档",c.tag+": real shared writer refused")
  c.s.entry_read_mode="";loads+=1
  check(c.b.load_profile(c.path) and not c.b._fee_lobby_ticket.held(c.b),c.tag+": genuine primary load clears hold")
  check(c.s._profile==expected and rows(c)==frozen,c.tag+": full reload memory/disk independent")
 if read_mode=="pre_unknown":check(not c.b._fee_lobby_ticket.held(c.b) and c.b.entry_writes==0,c.tag+": no IO is not hold authority")
 finish(c)
func writer_pre_unknown()->void:
 var c:Dictionary=setup("writer-pre-IO-unknown")
 if not open_page(c):finish(c);return
 c.s.entry_read_mode="writer_pre_unknown";c.b.source_turn()
 var observations:Array=[]
 for n in range(4,10):
  observations.append({"read":n,"path":c.path+(["",".bak",".tmp"][(n-4)%3]),"io_entered":false,"physical_ran":false})
 check(c.b.entry_writes==1 and c.s.entry_reads==9 and c.s.entry_unknown_observations==observations,c.tag+": exact last-preflight R4-R6 and post-return R7-R9, no physical IO")
 check(rows(c)==c.before_rows,c.tag+": independent full primary/backup/tmp unchanged")
 check(c.s._profile==c.before_entry and c.b.last_saved_payload==c.before_cache and c.b.quest_save_serial==c.before_serial,c.tag+": independent full profile/cache/serial unchanged")
 check(not c.b._fee_lobby_ticket.held(c.b) and c.s._fee_purchase_hold.is_empty() and c.b.facts==c.purchase_facts,c.tag+": no IO cannot create hold or entry fact")
 check(c.b.automation.position_map==c.map and c.b.automation.position_cell==Vector2i(30,22),c.tag+": no Warp")
 finish(c)
func original(manual:bool,parent:bool,gatefalse:bool=false)->void:
 var c:Dictionary=setup("original-%s-%s-%s"%[manual,parent,gatefalse],35,811,true,parent,not manual)
 if gatefalse:c.b.purchase_enabled=false
 if not open_page(c):finish(c);return
 var expected:Dictionary=expected_entry(c,false)
 c.b.source_turn()
 check(c.s._profile==expected and c.b.entry_writes==0 and c.b.facts.is_empty(),c.tag+": whole original profile, no invented attempt/fact")
 disk(c,expected,c.before_entry)
 check(c.b.quest_save_serial==c.before_serial+1 and c.b.last_saved_payload==JSON.stringify(expected),c.tag+": parent-compatible serial/cache")
 check(c.b.automation.position_map==800 and c.b.automation.position_cell==Vector2i(14,26) and c.b.quest_auto.phase=="landing",c.tag+": original return/publication behavior")
 finish(c)
func non_authority(kind:String)->void:
 var c:Dictionary=setup("non-authority-"+kind)
 if not open_page(c):finish(c);return
 match kind:
  "wrong_consumer":c.b._fee_lobby_ticket_entry.accept_purchase(c.b,RefCounted.new(),RefCounted.new())
  "wrong_call":c.b._fee_lobby_ticket_entry.accept_purchase(c.b,c.b._fee_lobby_ticket,RefCounted.new())
  "detach":c.b.fee_detach(71)
  "revoke":c.b._fee_lobby_ticket_entry.revoke()
  "record_only":c.b._fee_lobby_ticket_entry.revoke();c.b._fee_lobby_ticket_entry.accept_purchase(c.b,c.b._fee_lobby_ticket,RefCounted.new())
 if kind in ["wrong_consumer","wrong_call"]:
  var expected:Dictionary=expected_entry(c);c.b.source_turn();disk(c,expected,c.before_entry)
  check(c.b.entry_writes==1 and c.b.facts.size()==2,c.tag+": wrong request does not consume genuine cap")
 else:
  var denied:Dictionary=c.b._persist_lobby_ticket_entry(RefCounted.new(),{})
  check(denied=={"ok":false},c.tag+": private entry cannot be reconstructed after revocation")
  check(c.b.entry_writes==0 and rows(c)==c.before_rows and c.s._profile==c.before_entry and c.b.facts==c.purchase_facts,c.tag+": journal/diagnostic/rebinding cannot grant")
 finish(c)
func load_failure()->void:
 var c:Dictionary=setup("real-failed-load")
 if not open_page(c):finish(c);return
 var expected:Dictionary=expected_entry(c)
 c.s.entry_read_mode="post_unknown";c.b.source_turn();c.s.entry_read_mode=""
 disk(c,expected,c.before_entry)
 var frozen:Array=rows(c);var memory:Dictionary=c.s._profile.duplicate(true);var cache:String=c.b.last_saved_payload;var serial:int=c.b.quest_save_serial
 for suffix in ["",".bak"]:
  var f=FileAccess.open(c.path+suffix,FileAccess.WRITE)
  check(f!=null,c.tag+": fixture corrupt source open")
  if f==null:finish(c);return
  f.store_string("not-json");f.flush();f.close()
 var broken:Array=[{"exists":true,"bytes":"not-json".to_utf8_buffer()},{"exists":true,"bytes":"not-json".to_utf8_buffer()},{"exists":false,"bytes":PackedByteArray()}]
 loads+=1
 check(not c.b.load_profile(c.path),c.tag+": actual loader rejects both bad sources")
 check(c.b._fee_lobby_ticket.held(c.b) and c.s._profile==memory and c.b.last_saved_payload==cache and c.b.quest_save_serial==serial and rows(c)==broken,c.tag+": complete failed load unchanged authority/memory/cache/disk")
 check(not c.b.save() and rows(c)==broken,c.tag+": failed load cannot wash hold")
 for i in range(2):
  var f=FileAccess.open(c.path+("" if i==0 else ".bak"),FileAccess.WRITE)
  if f==null:check(false,c.tag+": fixture restore open");finish(c);return
  f.store_buffer(frozen[i].bytes);f.flush();f.close()
 loads+=1
 check(c.b.load_profile(c.path) and not c.b._fee_lobby_ticket.held(c.b),c.tag+": real primary receipt clears only current hold")
 check(c.s._profile==expected and rows(c)==frozen,c.tag+": full successful load and retained bytes")
 check(c.b._fee_lobby_ticket_entry._live.is_empty(),c.tag+": reload does not revive entry capability")
 finish(c)
func run()->void:
 for pair in [[30,811],[49,831],[50,811],[69,831],[70,851]]:good(pair[0],pair[1])
 for mode in ["outer_false","owner_after_mark","position_successor","source_after_mark","wrong_handle","nested"]:good(35,811,mode)
 good(35,811,"",true)
 for mode in ["false_before","false_after","forged_raw","forged_ok","unrelated","owner","serial","path","binding","run","ref","pending","router"]:failed(mode)
 for mode in ["pre_unknown","post_unknown","read_owner"]:failed("",mode)
 for manual in [false,true]:
  for parent in [false,true]:original(manual,parent)
 for parent in [false,true]:original(true,parent,true)
 for kind in ["wrong_consumer","wrong_call","detach","revoke","record_only"]:non_authority(kind)
 load_failure()
 writer_pre_unknown()
 print("LOBBY ENTRY SUMMARY checks=",checks," failures=",failures," fixtures=",fixtures," real_loads=",loads," Wait=0")
 quit(1 if failures else 0)
