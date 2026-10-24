extends "res://tests/fee_lobby_ticket_cross_writer_test.gd"
const Clock=preload("res://scripts/clock.gd")
## Reuse independent original public-writer expected values, not product helpers.
## Only held origin changes from purchase unknown to true entry unknown.
func setup(tag:String,level:int=35,ticket:bool=false)->Dictionary:
 fixtures+=1;print("LOBBY FIXTURE ",fixtures," ",tag," begin")
 var b=preload("res://tests/support/fee_entry_backend.gd").new();b.set_process(false)
 var luck=RandomNumberGenerator.new();luck.seed=7319
 var s=preload("res://tests/support/fee_entry_session.gd").new(func():return 1791504000,luck);s.host=weakref(b);b.session=s
 s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
 s._profile.player.level=level;s._profile.player.gold=1000000;s._profile.no_random_encounters=true
 for key in s._profile.inventory:s._profile.inventory[key]=0
 if ticket:
  var id:int=2757 if level>=70 else (2756 if level>=50 else 2755)
  preload("res://server/original_equipment.gd").add(s._profile,id)
 b.automation.position_changed(851 if level>=70 else 811,Vector2i(29 if level>=70 else (28 if level>=50 else 30),22),true)
 b.save_path="user://lobby-shutdown.json" if tag=="shutdown" else "user://lobby-%d-%03d-%s.json"%[Clock.ticks_usec(),fixtures,tag]
 s.set_location(b.automation.position_map,b.automation.position_cell.x,b.automation.position_cell.y)
 check(s._valid_profile(s.snapshot()) and b.save(),tag+": original setup saved")
 load_calls+=1
 check(b.load_profile(b.save_path),tag+": real fixture normalization load")
 b.automation.position_changed(851 if level>=70 else 811,Vector2i(29 if level>=70 else (28 if level>=50 else 30),22),true)
 check(b.save(),tag+": canonical fixture resave")
 b.fee_attach(71)
 return {"b":b,"s":s,"tag":tag,"path":b.save_path,"before":s._profile.duplicate(true),"serial":b.quest_save_serial,"ticket":ticket,"level":level,"purchase_facts":[]}
func hold(c:Dictionary)->bool:
 if start(c).is_empty():return false
 c.b.purchase_turn()
 check(c.b.facts.size()==1,c.tag+": genuine purchase before entry")
 c.purchase_facts=c.b.facts.duplicate(true)
 c.b.source_turn()
 check(c.b.quest_auto.phase=="source_dialogue",c.tag+": original confirm page")
 c.s.entry_read_mode="post_unknown";c.b.source_turn();c.s.entry_read_mode=""
 check(c.b.entry_writes==1 and c.b._fee_lobby_ticket.held(c.b),c.tag+": real entry IO creates hold")
 return failures==0
func one(kind:String,mode:String,parent_body:bool=false)->Dictionary:
 var c:Dictionary=setup("cross-"+kind+"-"+mode+"-"+str(parent_body))
 if mode!="empty" and not hold(c):finish(c);return {}
 if mode=="gatefalse":c.b.purchase_enabled=false
 c.s.use_parent_writer=parent_body
 prepare(c,kind)
 if failures:finish(c);return {}
 var before:Dictionary=c.s._profile.duplicate(true)
 var pending:Dictionary=c.s._pending.duplicate(true)
 var cache:String=c.b.last_saved_payload
 var serial:int=c.b.quest_save_serial
 var frozen:Array=rows(c)
 var calls:int=c.s.shared_calls
 var rejection_count:int=c.b._fee_lobby_ticket.rejected_saves
 var expected:Dictionary=before.duplicate(true)
 var disk_expected:Dictionary=before.duplicate(true)
 match kind:
  "equipment":expected.equipped=true
  "permit":expected.player.gold-=200;expected.travel_pass=true
  "seimu":expected.player.gold-=300;expected.location={"map_id":31301,"x":10,"y":104}
  "battle_settings":expected.automation_settings={"training":{"hp":43}}
  "loot_idle":expected.quest_loot=expected_ledger()
  "transmigration":expected=natural_candidate(before)
 disk_expected=expected.duplicate(true)
 if kind=="battle_settings":
  # The original settings writer reads the saved JSON baseline (numbers are floats).
  # Keep a separate native oracle above; match full disk bytes without normalizing them.
  disk_expected=JSON.parse_string(JSON.stringify(c.saved_before_battle))
  disk_expected.automation_settings={"training":{"hp":43}}
 var ok:bool=invoke(c,kind)
 var refused:bool=mode=="held"
 check(ok!=refused,c.tag+": real public return")
 if refused:
  check(c.b._fee_lobby_ticket.rejected_saves>rejection_count,c.tag+": volatile rejected-save count, not disk fact")
  check(c.s._profile==before and c.s._pending==pending and c.b.last_saved_payload==cache and c.b.quest_save_serial==serial and rows(c)==frozen,c.tag+": whole native/cache/serial/main/bak/tmp unchanged through original failure")
  check(not c.s._fee_purchase_hold.is_empty() and c.b.facts==c.purchase_facts and c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty(),c.tag+": protection retained; no cap or committed fact")
  if kind not in ["generic","equipment"]:check(c.s.shared_calls>calls,c.tag+": real Session physical seam reached, not only upper admission refusal")
 else:
  check(c.s._profile==expected and c.s._pending==pending,c.tag+": independent full native profile including rewards/gold/UID")
  check(rows(c)==[{"exists":true,"bytes":JSON.stringify(disk_expected).to_utf8_buffer()},frozen[0],{"exists":false,"bytes":PackedByteArray()}],c.tag+": independent complete three-file bytes")
  if kind in ["loot_idle","transmigration"]:
   check(c.b.last_saved_payload==cache and c.b.quest_save_serial==serial,c.tag+": Session transaction does not claim Backend cache update")
  else:check(c.b.last_saved_payload==JSON.stringify(disk_expected) and c.b.quest_save_serial==serial+1,c.tag+": original Backend cache/serial")
 if kind=="loot_idle":check(c.callback.count==(0 if refused else 1) and c.callback.payload==("" if refused else JSON.stringify(disk_expected)),c.tag+": original callback boundary")
 var result:Dictionary={"ok":ok,"profile":c.s._profile.duplicate(true),"pending":c.s._pending.duplicate(true),"cache":c.b.last_saved_payload,"serial_delta":c.b.quest_save_serial-serial,"rows":rows(c)}
 # Generated fee run/attempt IDs make separately prepared held fixtures unequal;
 # those paths use full independent oracles above, not cross-fixture equality.
 finish(c)
 return result
func run()->void:
 for kind in ["generic","equipment","permit","seimu","battle_settings","loot_idle","transmigration"]:
  one(kind,"empty")
  one(kind,"empty",true)
  one(kind,"held")
 print("LOBBY ENTRY CROSS SUMMARY checks=",checks," failures=",failures," fixtures=",fixtures," real_loads=",load_calls," Wait=0")
 quit(1 if failures else 0)
