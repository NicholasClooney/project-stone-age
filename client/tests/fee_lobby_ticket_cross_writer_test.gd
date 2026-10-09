extends "res://tests/fee_lobby_ticket_purchase_test.gd"
## UNRUN. Actual public entry points; no raw-write double used as writer proof.
## Loot/transmigration use Session public transaction APIs, not complete gameplay
## admission. Battle uses the existing begin_battle development command, no WS.
const Loot=preload("res://server/quest_auto_loot_state.gd")
const Rebirth=preload("res://server/transmigration_state.gd")
const SessionBase=preload("res://server/game_session.gd")
const Required=preload("res://server/required_fee_transaction.gd")
const BUDGET="0123456789abcdef0123456789abcdef"
const LOOTRUN="fedcba9876543210fedcba9876543210"
func hold(c:Dictionary)->bool:
 if start(c).is_empty():return false
 c.s.at=3;c.s.mode="unknown";c.b.purchase_turn()
 check(c.s.writes==3 and c.b._fee_lobby_ticket.held(c.b) and not c.s._fee_purchase_hold.is_empty(),c.tag+": real unknown IO creates both protections")
 c.s.mode="";c.s.at=0
 return failures==0
func natural_candidate(before:Dictionary)->Dictionary:
 var p:Dictionary=before.duplicate(true)
 p.player.transmigration=1;p.player.level=1;p.player.xp=0
 p.player.allocated_stats={"vitality":0,"strength":0,"toughness":0,"dexterity":0}
 p.player.base_stats={"vitality":150,"strength":250,"toughness":350,"dexterity":450}
 p.player.erase("legacy_stat_offset");p.player.stat_points=10
 p.rebirth={"schema":1,"rules":Rebirth.RULES,"history":"natural","equation":(20<<16)|120,"inherited_base":p.player.base_stats.duplicate(),"developer_base_delta":{"vitality":0,"strength":0,"toughness":0,"dexterity":0},"round_points":10,"consumed_gm_points":0,"last_transaction":"cross-natural-1"}
 SessionBase.Progression.refresh(p.player);p.player.hp=p.player.max_hp
 return p
func prepare(c:Dictionary,kind:String)->void:
 if kind=="generic":c.s._profile.player.gold+=7
 if kind=="equipment":c.s._profile.inventory.club=1
 if kind in ["permit","seimu"]:
  if kind=="seimu":
   c.s._profile.travel_pass=true
   if not 46 in c.b.quest_catalog.enabled_events:c.b.quest_catalog.enabled_events.append(46)
  var map_id:int=40 if kind=="seimu" else 1100
  var cell:Vector2i=Vector2i(12,1) if kind=="seimu" else Vector2i(85,107)
  check(c.s.set_location(map_id,cell.x,cell.y),c.tag+": legitimate source-near fixture placement")
  c.b.automation.position_changed(map_id,cell,true)
 if kind=="battle_settings":
  c.saved_before_battle=c.s._profile.duplicate(true)
  check(JSON.stringify(c.saved_before_battle)==c.b.last_saved_payload,c.tag+": independently retained pre-battle saved full profile")
  c.b.admin=true # Explicit development-battle fixture privilege, not player authorization.
  var opened:Dictionary=c.b.handle({"type":"begin_battle","enemy_count":1})
  check(opened.get("ok",false) and not c.s._pending.is_empty(),c.tag+": actual development battle creates pending; no fabricated pending")
func expected_ledger()->Dictionary:
 return {"version":1,"recovery_blocked":false,"entries":{Loot.STEP:{"budget_id":BUDGET,"origin_run_id":LOOTRUN,"generation":0,"revision":0,"limit_ms":1800000,"used_ms":0,"existing_items":0,"saved_battles":0,"new_items":0,"issued_seq":0,"settled_seq":0,"open_span":false,"recovery_blocked":false}}}
func invoke(c:Dictionary,kind:String)->bool:
 match kind:
  "generic":return c.b.save()
  "equipment":return c.b.handle({"type":"equip_item","item":"club"}).get("ok",false)
  "permit","seimu":
   var opened:Dictionary
   if kind=="permit":opened=c.b.handle({"type":"permit_shop_open","source_id":"genout/ss_1100_86_107","open_id":"cross-entry","_quest_connection":71,"_fee_binding":c.b._fee_bindings.get(71)})
   else:opened=c.b.handle({"type":"quest_talk","npc_id":Required.GATE})
   check(opened.get("ok",false) and opened.has("dialogue"),c.tag+": actual source page reached")
   if not opened.has("dialogue"):return false
   if kind=="permit":return c.b.handle({"type":"permit_shop_choose","token":opened.dialogue.token,"choice":"buy_one","_quest_connection":71,"_fee_binding":c.b._fee_bindings.get(71)}).get("ok",false)
   return c.b.handle({"type":"quest_choose","token":opened.dialogue.token,"choice":"yes"}).get("ok",false)
  "battle_settings":return c.b.handle({"type":"set_automation_settings","settings":{"training":{"hp":43}}}).get("ok",false)
  "loot_idle":
   c.callback={"count":0,"payload":""}
   var observed:Dictionary=c.callback
   var result:Dictionary=c.s.commit_loot_idle_transition(c.s._profile.duplicate(true),c.s._profile.quest_loot.duplicate(true),"acquire",{"step_id":Loot.STEP,"budget_id":BUDGET,"run_id":LOOTRUN,"minutes":30,"existing_items":0},c.path,func(payload):observed.count+=1;observed.payload=payload)
   return result.get("ok",false)
  "transmigration":return c.s.commit_transmigration_candidate(natural_candidate(c.s._profile),c.path)
 return false
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
  check(not c.s._fee_purchase_hold.is_empty() and c.b.facts.is_empty() and c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty(),c.tag+": protection retained; no cap or committed fact")
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
func seed_source(path:String,value:Dictionary)->void:
 # Explicit storage fixture only, never counted as a production writer call.
 var f=FileAccess.open(path,FileAccess.WRITE)
 check(f!=null,"loader fixture source open")
 if f!=null:f.store_string(JSON.stringify(value));f.close()
func recovery(mode:String)->void:
 var c:Dictionary=setup("recovery-"+mode)
 if not hold(c):finish(c);return
 var source:Dictionary=paid(c,attempt(c))
 source.quest_loot=expected_ledger()
 source.quest_loot.entries[Loot.STEP].open_span=true
 source.quest_loot.entries[Loot.STEP].issued_seq=1
 source.quest_loot.entries[Loot.STEP].revision=1
 var expected:Dictionary=source.duplicate(true)
 expected.quest_loot.entries[Loot.STEP].open_span=false
 expected.quest_loot.entries[Loot.STEP].settled_seq=1
 expected.quest_loot.entries[Loot.STEP].revision=2
 if mode=="foreign_run":
  source.quest_auto_fee_lifecycle.current.run_id="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  expected.quest_auto_fee_lifecycle.current.run_id=source.quest_auto_fee_lifecycle.current.run_id
 if mode=="backup":
  DirAccess.remove_absolute(ProjectSettings.globalize_path(c.path))
  seed_source(c.path+".bak",source)
 else:seed_source(c.path,source)
 var prior:Array=rows(c);var native:Dictionary=c.s._profile.duplicate(true)
 var cache:String=c.b.last_saved_payload;var serial:int=c.b.quest_save_serial
 c.s.loader_fault=mode
 if mode=="unknown":c.s.mode="unknown";c.s.at=c.s.writes
 load_calls+=1
 var ok:bool=c.b.load_profile(c.path)
 var failed:bool=mode in ["before","after","backup","foreign_run"]
 check(ok!=failed,c.tag+": real Backend/Session load return")
 var expected_rows:Array=[{"exists":true,"bytes":JSON.stringify(expected).to_utf8_buffer()},prior[0],{"exists":false,"bytes":PackedByteArray()}]
 if mode in ["before","backup","foreign_run"]:expected_rows=prior
 check(rows(c)==expected_rows,c.tag+": full original loot retirement disk result, including false after actual write")
 check(c.s._fee_purchase_loader_write.is_empty(),c.tag+": loader-only exception released on success/failure")
 if failed:
  check(c.s._profile==native and c.b.last_saved_payload==cache and c.b.quest_save_serial==serial and c.b._fee_lobby_ticket.held(c.b),c.tag+": failed real load restores native/cache/serial and retains hold")
  check(not c.b.save() and rows(c)==expected_rows,c.tag+": failed load cannot wash protection")
 else:
  check(c.s._profile==expected and c.b.last_saved_payload==JSON.stringify(expected) and c.b.quest_save_serial==serial,c.tag+": exact successful load memory/cache; no invented save serial")
  if mode=="unknown":
   check(c.b._fee_lobby_ticket.held(c.b) and not c.s._fee_purchase_hold.is_empty(),c.tag+": public successful load is not unknown readback clearance")
  else:check(not c.b._fee_lobby_ticket.held(c.b) and c.s._fee_purchase_hold.is_empty(),c.tag+": verified receipt clears both holds only after actual loader")
  if mode=="nested":check(c.s.loader_nested_rejected,c.tag+": copied candidate not granted real loader exception")
 check(c.b._fee_start_intent.take_purchase(c.b,c.b._fee_lobby_ticket).is_empty() and c.b.facts.is_empty(),c.tag+": load grants no purchase or payment fact")
 finish(c)
func successor(mode:String)->void:
 var c:Dictionary=setup("hold-scope-"+mode)
 if not hold(c):finish(c);return
 var frozen:Array=rows(c);var before:Dictionary=c.s._profile.duplicate(true)
 var serial:int=c.b.quest_save_serial;var cache:String=c.b.last_saved_payload
 match mode:
  "retired_run":c.b.quest_auto.identity.begin()
  "old_path":c.b.save_path=c.path+".new-path"
  "new_session":
   var replacement=SessionBase.new(func():return 1791504000)
   replacement._profile=before.duplicate(true);c.b.session=replacement
  "foreign_owner":
   c.s._profile=c.s._profile.duplicate(true);c.s._profile.character_id="100005"
   c.s._profile.erase("quest_auto_fee_lifecycle") # Legal independent owner fixture, not a continuation.
 var allowed:bool=mode=="foreign_owner"
 var live:Dictionary=c.s._profile.duplicate(true)
 check(c.s.save_game(c.path)==allowed,c.tag+": public Session save exact captured path/owner")
 if allowed:check(rows(c)==[{"exists":true,"bytes":JSON.stringify(live).to_utf8_buffer()},frozen[0],{"exists":false,"bytes":PackedByteArray()}],c.tag+": different owner normal writer")
 else:check(rows(c)==frozen,c.tag+": old Session/path stays protected even host successor")
 check(c.s._profile==live and c.b.last_saved_payload==cache and c.b.quest_save_serial==serial,c.tag+": Session call never invents Backend cache or serial")
 if mode=="new_session":
  var new_before:Dictionary=c.b.session._profile.duplicate(true)
  check(c.b.session.save_game(c.path+".independent") and c.b.session._profile==new_before,c.tag+": unrelated new Session has no inherited guard")
 finish(c)
func run()->void:
 for kind in ["generic","equipment","permit","seimu","battle_settings","loot_idle","transmigration"]:
  var actual:Dictionary=one(kind,"empty")
  if failures:quit(1);return
  var parent:Dictionary=one(kind,"empty",true)
  check(actual==parent,kind+": exact parent physical body control in candidate environment, not whole-parent runtime")
  if failures:quit(1);return
  for mode in ["held","gatefalse"]:
   one(kind,mode)
   if failures:quit(1);return
 for mode in ["success","before","after","nested","unknown","backup","foreign_run"]:
  recovery(mode)
  if failures:quit(1);return
 for mode in ["retired_run","old_path","new_session","foreign_owner"]:
  successor(mode)
  if failures:quit(1);return
 print("LOBBY CROSS WRITER: %d checks; %d failures; %d fixtures; %d real loads"%[checks,failures,fixtures,load_calls])
 quit(1 if failures else 0)
