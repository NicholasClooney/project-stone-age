extends "res://tests/quest_auto_loot_state_test.gd"
# TMP UNRUN. Public ordinary-cell + gold fixture, not original travel or authentication.
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Fee=preload("res://server/required_fee_transaction.gd")
const Compare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const SHOP="genout/ss_1100_86_107"
func disk(path:String)->PackedByteArray:
 var f=FileAccess.open(path,FileAccess.READ)
 if f==null:check(false,"read open "+str(FileAccess.get_open_error()));return PackedByteArray()
 var n:int=f.get_length();var e:int=f.get_error()
 if e!=OK:check(false,"read length");f.close();return PackedByteArray()
 var bytes:PackedByteArray=f.get_buffer(n);e=f.get_error();f.close()
 check(e==OK and n>0 and bytes.size()==n,"Complete actual disk read")
 if failures:return PackedByteArray()
 print("FEE_DISK ",path," size=",n," sha=",bytes.get_string_from_utf8().sha256_text())
 return bytes
func backup_record(path:String)->Dictionary:
 if DirAccess.dir_exists_absolute(path):
  check(false,"Backup path is a directory");return {}
 var exists:bool=FileAccess.file_exists(path)
 if not exists:
  var probe=FileAccess.open(path,FileAccess.READ)
  var open_error:int=FileAccess.get_open_error()
  if probe!=null:
   probe.close();check(false,"Backup appeared during absence check");return {}
  check(open_error==ERR_FILE_NOT_FOUND,"Backup absence must be actual file-not-found")
  if failures:return {}
  return {"exists":false,"bytes":PackedByteArray()}
 var bytes:PackedByteArray=disk(path)
 if failures:return {}
 return {"exists":true,"bytes":bytes}
func setup(b,kind:String,tag:String,gold:int)->bool:
 b.set_process(false);b.fee_attach(71);b.save_path="user://required-fee-"+tag+".json"
 for suffix in ["",".bak",".tmp",".resume.json",".resume.json.bak",".resume.json.tmp"]:
  check(not FileAccess.file_exists(b.save_path+suffix) and not DirAccess.dir_exists_absolute(b.save_path+suffix),"Fresh isolated fixture")
  if failures:return false
 b.session._profile.player.gold=gold
 if kind=="seimu":
  b.session._profile.travel_pass=true # disclosed legacy permit fixture, not a purchased entity
  if not 46 in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(46)
 var map_id:int=40 if kind=="seimu" else 1100
 var cell:Vector2i=Vector2i(12,1) if kind=="seimu" else Vector2i(85,107)
 check(b.session.set_location(map_id,cell.x,cell.y),"Disclosed ordinary source-near starting fixture")
 if failures:return false
 b.automation.position_changed(map_id,cell,true)
 # The second same-payload save may deduplicate; it does not promise a backup.
 check(b.save() and b.save(),"Initial save and repeated save call succeed")
 return failures==0
func permit_command(b,command:Dictionary,connection:int=71)->Dictionary:
 var sent:Dictionary=command.duplicate(true)
 sent._quest_connection=connection;sent._fee_binding=b._fee_bindings.get(connection)
 return b.handle(sent)
func open_fee(b,kind:String)->Dictionary:
 return b.handle({"type":"quest_talk","npc_id":Fee.GATE}) if kind=="seimu" else permit_command(b,{"type":"permit_shop_open","source_id":SHOP,"open_id":"fixture-"+str(b.original_quests.serial)})
func choose_fee(b,kind:String,r:Dictionary)->Dictionary:
 var command:Dictionary={"type":"quest_choose" if kind=="seimu" else "permit_shop_choose","token":r.dialogue.token,"choice":"yes" if kind=="seimu" else "buy_one"}
 return b.handle(command) if kind=="seimu" else permit_command(b,command)
func record(b)->Dictionary:
 var bytes:PackedByteArray=disk(b.save_path)
 if failures:return {}
 var bak:Dictionary=backup_record(b.save_path+".bak")
 if failures:return {}
 return {"profile":b.session.snapshot(),"pending":b.session._pending.duplicate(true),"page":b.original_quests.pending.duplicate(true),"cache":b.last_saved_payload,"serial":b.quest_save_serial,"disk":bytes,"bak":bak,"map":b.automation.position_map,"cell":b.automation.position_cell,"arrival":Fee.arrival(b),"identity":b.quest_auto.identity.snapshot(),"q_state":{"running":b.quest_auto.running,"phase":b.quest_auto.phase,"connection":b.quest_auto.connection,"client":b.quest_auto.client,"internal":b.quest_auto.internal,"detached":b.quest_auto.detached,"owns_battle":b.quest_auto.owns_battle,"message":b.quest_auto.message,"pause_reason":b.quest_auto.pause_reason},"nav":b.quest_auto.navigation.key,"auto":b.automation.settings.duplicate(true),"auto_token":b.automation.start_lifetime,"stationary":{"running":b.stationary.running,"reason":b.stationary.reason,"elapsed":b.stationary.elapsed,"lease":b.stationary.lease,"connection":b.stationary.connection,"map":b.stationary.map_id,"cell":b.stationary.cell,"battle_id":b.stationary.battle_id,"saved_win":b.stationary.saved_win,"encounters":b.stationary.encounters}}
func run()->void:
 for kind in ["permit","seimu"]:
  var cost:int=200 if kind=="permit" else 300
  for mode in ["success","insufficient","savefail"]:
   var b=Backend.new()
   if not setup(b,kind,kind+"-"+mode,cost-1 if mode=="insufficient" else cost):b.free();quit(1);return
   var opened:Dictionary=open_fee(b,kind)
   check(opened.get("ok",false) and opened.has("dialogue"),"Actual source confirmation")
   if failures:b.free();quit(1);return
   var before:Dictionary=record(b)
   if failures:b.free();quit(1);return
   before.page={} # original one-use confirmation is consumed even on refusal
   var expected:Dictionary=before.profile.duplicate(true)
   if kind=="permit":expected.travel_pass=true
   else:expected.location={"map_id":31301,"x":10,"y":104}
   expected.player.gold-=cost
   if mode=="savefail":
    check(DirAccess.make_dir_absolute(b.save_path+".tmp")==OK,"Own genuine writer blocker")
    if failures:b.free();quit(1);return
   var reply:Dictionary=choose_fee(b,kind,opened)
   if failures:b.free();quit(1);return
   if mode=="success":
    check(reply.get("ok",false) and reply.get("committed",false) and b.session.snapshot()==expected and b.last_saved_payload==JSON.stringify(expected),"Exact full fee candidate committed")
    if failures:b.free();quit(1);return
    var bytes:PackedByteArray=disk(b.save_path)
    if failures:b.free();quit(1);return
    var parsed:Dictionary=Compare.validated_copy(b.session,bytes.get_string_from_utf8())
    check(parsed.get("ok",false) and parsed.profile==expected,"Full validated persisted candidate")
    if failures:b.free();quit(1);return
    var committed:Dictionary=record(b)
    if failures:b.free();quit(1);return
    check(committed.bak.exists and committed.bak.bytes==before.disk,"Actual successful writer preserves previous primary as backup")
    if failures:b.free();quit(1);return
    check(not choose_fee(b,kind,opened).get("ok",true),"Consumed token rejects second charge")
    if failures:b.free();quit(1);return
    check(record(b)==committed,"Replay cannot alter complete native/cache/disk/authority")
   else:
    check(not reply.get("ok",true) and record(b)==before,"Failure retains exact pre-transaction profile/cache/disks/authority")
   if failures:b.free();quit(1);return
   print("FEE COMPLETE ",kind,"/",mode)
   b.free()
 print("REQUIRED FEES: 0 failures; six internal ordinary-cell fixtures")
 quit(0)
