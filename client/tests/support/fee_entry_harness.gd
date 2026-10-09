extends SceneTree
## Static candidate. Fixtures use genuine Start/source pages with synthetic
## fee_attach bindings and legal lobby placement; not authenticated WS.
const B=preload("res://tests/support/fee_entry_backend.gd")
const S=preload("res://tests/support/fee_entry_session.gd")
const E=preload("res://server/original_equipment.gd")
const ParentRouter=preload("res://tests/support/fee_entry_parent_router.gd")
var checks:int=0
var failures:int=0
var fixtures:int=0
var loads:int=0
func _initialize()->void:call_deferred("run")
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;push_error(label)
func raw(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"exists":false,"bytes":PackedByteArray()}
 var f=FileAccess.open(path,FileAccess.READ)
 if f==null:return {"exists":true,"unknown":true}
 var bytes:PackedByteArray=f.get_buffer(f.get_length());f.close()
 return {"exists":true,"bytes":bytes}
func rows(c:Dictionary)->Array:return [raw(c.path),raw(c.path+".bak"),raw(c.path+".tmp")]
func disk(c:Dictionary,primary:Dictionary,backup:Dictionary)->void:
 check(rows(c)==[{"exists":true,"bytes":JSON.stringify(primary).to_utf8_buffer()},{"exists":true,"bytes":JSON.stringify(backup).to_utf8_buffer()},{"exists":false,"bytes":PackedByteArray()}],c.tag+": complete independent three-disk bytes")
func command()->Dictionary:return {"type":"quest_auto_start","quest_id":2,"seq":91,"client":"entry-fixture","_quest_connection":71}
func setup(tag:String,level:int=35,map_id:int=811,manual:bool=false,parent:bool=false,legacy:bool=false)->Dictionary:
 fixtures+=1;print("ENTRY FIXTURE ",fixtures," ",tag," begin")
 var b=B.new();b.set_process(false)
 var rng=RandomNumberGenerator.new();rng.seed=991
 var s=S.new(func():return 1791504000,rng);b.session=s;s.host=weakref(b)
 s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
 s._profile.player.level=level;s._profile.player.gold=1000000;s._profile.no_random_encounters=true
 for key in s._profile.inventory:s._profile.inventory[key]=0
 var item:int=2757 if level>=70 else (2756 if level>=50 else 2755)
 var x:int=29 if level>=70 else (28 if level>=50 else 30)
 if manual:E.add(s._profile,item)
 if parent:
  b.original_quests=ParentRouter.new();b.original_quests.catalog=b.quest_catalog
  b.quest_auto=preload("res://tests/support/fee_entry_parent_runner.gd").new()
 b.start_enabled=not legacy;b.purchase_enabled=not legacy
 b.automation.position_changed(map_id,Vector2i(x,22),true)
 s.set_location(map_id,x,22)
 b.save_path="user://entry-%d-%03d-%s.json"%[Time.get_ticks_usec(),fixtures,tag]
 check(b.save(),tag+": seed save")
 loads+=1;check(b.load_profile(b.save_path),tag+": real normalizing load")
 b.automation.position_changed(map_id,Vector2i(x,22),true);check(b.save(),tag+": canonical seed")
 b.fee_attach(71)
 var c:Dictionary={"b":b,"s":s,"tag":tag,"path":b.save_path,"before":s._profile.duplicate(true),"serial":b.quest_save_serial,"item":item,"manual":manual,"legacy":legacy,"level":level,"map":map_id}
 var reply:Dictionary=b.handle(command())
 check(reply.get("ok")==true,tag+": true explicit Start "+str(reply.get("reason","")))
 if not reply.get("ok",false):c.bad=true;return c
 var expected:Dictionary=c.before.duplicate(true)
 if not legacy:
  expected["quest_auto_fee_lifecycle"]={"schema":1,"owner":{"profile_id":expected.profile_id,"character_id":expected.character_id},"current":{"run_id":reply.run_id,"run_status":"active","purchase":{"state":"manual_only" if manual else "none"}},"unresolved_attempt":{}}
  check(s._profile==expected and b.quest_save_serial==c.serial+1,tag+": full Start expected")
  disk(c,expected,expected)
 if not manual:
  s.writes=0;s.calls=[];b.purchase_turn()
  check(s.calls.size()==3 and b.facts.size()==1,tag+": actual purchase double attempt then commit")
  if s.calls.size()!=3:c.bad=true;return c
  var observed:Dictionary=s.calls[0].quest_auto_fee_lifecycle.current.purchase
  var amount:int=level*(20 if level<50 else 40)
  var attempt:Dictionary=expected.duplicate(true)
  attempt.quest_auto_fee_lifecycle.current.purchase={"state":"attempting","attempt_id":observed.attempt_id,"source_id":"quiz/uketuke2" if level>=70 else "quiz/uketuke","offer_id":"quiz/uketuke2@4020:18:13:0" if level>=70 else ("quiz/uketuke@2020:18:13:1" if level>=50 else "quiz/uketuke@2020:18:13:2"),"item_id":item,"amount":amount,"balance_before":expected.player.gold}
  expected=attempt.duplicate(true)
  expected.player.gold-=amount
  expected.original_items.append(item);expected.original_instances.append({"uid":expected.next_original_uid,"item_id":item,"durability":0})
  expected.quest_auto_fee_lifecycle.current.purchase.merge({"state":"ticket_committed","balance_after":expected.player.gold,"ticket_uid":expected.next_original_uid},true);expected.next_original_uid+=1
  check(s.calls==[attempt,attempt,expected] and s._profile==expected,tag+": independent entire purchase candidates")
  disk(c,expected,attempt)
 c.paid=expected.duplicate(true);c.purchase_facts=b.facts.duplicate(true)
 return c
func open_page(c:Dictionary)->bool:
 if c.get("bad",false):return false
 c.b.source_turn()
 check(c.b.quest_auto.phase=="source_dialogue" and not c.b.original_quests.pending.is_empty(),c.tag+": real source confirm page")
 if c.b.quest_auto.source_frame==null or c.b.quest_auto.source_frame.page.is_empty():return false
 c.token=c.b.quest_auto.source_frame.page.token
 c.before_entry=c.s._profile.duplicate(true);c.before_rows=rows(c);c.before_cache=c.b.last_saved_payload;c.before_serial=c.b.quest_save_serial;c.events_before=c.b.events.size()
 return true
func expected_entry(c:Dictionary,tracked:bool=true)->Dictionary:
 var v:Dictionary=c.before_entry.duplicate(true)
 var index:int=-1
 for i in range(v.original_instances.size()):
  if v.original_instances[i].item_id==c.item:
   if index<0:index=i
   if v.original_equipment.values().has(v.original_instances[i].uid):index=i;break
 check(index>=0,c.tag+": independent actual consumption selection")
 if index<0:return {}
 c.consumed=v.original_instances[index].uid
 for slot in v.original_equipment:
  if v.original_equipment[slot]==c.consumed:v.original_equipment[slot]=0
 v.original_items.remove_at(index);v.original_instances.remove_at(index)
 v.location={"map_id":840 if c.level>=70 else (820 if c.level>=50 else 800),"x":14,"y":26}
 if tracked:v.quest_auto_fee_lifecycle.current.purchase.merge({"state":"entry_committed","consumed_ticket_uid":c.consumed},true)
 return v
func finish(c:Dictionary)->void:
 check(c.b._fee_attempt_writer_call==null and c.b._fee_lobby_ticket_entry._op.is_empty() and c.b._fee_lobby_ticket_entry._reply.is_empty(),c.tag+": all own claims released")
 var module_ref:WeakRef=weakref(c.b._fee_lobby_ticket_entry)
 c.b.free()
 check(module_ref.get_ref()==null,c.tag+": backend-owned entry module released without private-field clearing")
 print("ENTRY FIXTURE ",fixtures," ",c.tag," end")
func run()->void:pass
