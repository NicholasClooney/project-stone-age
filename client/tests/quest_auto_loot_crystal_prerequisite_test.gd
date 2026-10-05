extends "res://tests/quest_auto_loot_state_test.gd"
# TMP ONLY. GM level60 + original public near travel, NOT original route or auto authority.
const Backend=preload("res://server/backend.gd")
const Session=preload("res://server/game_session.gd")
const Rules=preload("res://server/original_quests.gd")
const ProfileCompare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
const NumericSource=preload("res://server/quest_auto_source_actions.gd")
const SCHOLAR="extra/event/hougyoku@6000:58:44"
func arrival_record(b)->Dictionary:
 var a=b.quest_arrival
 return {"epoch":a._epoch,"serial":a._serial,"scope":a._scope,"map":a._map,"cell":a._cell,"marks":a._marks.duplicate(true),"stages":a._stages.duplicate(true),"action":a._action.duplicate(true),"approach":a._approach.duplicate(true),"warp":a._warp.duplicate(true),"battles":a._battles.duplicate(true),"wild":a._wild.duplicate(true)}
func identity_value(value:Variant)->Dictionary:
 var result:Dictionary={"typeof":typeof(value)}
 if value is Dictionary:
  var entries:Array=[]
  for key in value:entries.append({"key":identity_value(key),"value":identity_value(value[key])})
  result["entries"]=entries
 elif value is Array:
  var entries:Array=[]
  for item in value:entries.append(identity_value(item))
  result["entries"]=entries
 elif value is Object:
  result["valid"]=is_instance_valid(value)
  result["unexpected_object"]=true # Never dereference object properties in diagnostics.
 else:result["literal"]=var_to_str(value)
 return result
func print_scholar_identity(b,npc:Dictionary)->void:
 # Read only the already acquired NPC and existing catalog/override containers.
 var clauses:Dictionary={"nonempty":not npc.is_empty(),"map":npc.get("map_id")==6000,"cell":npc.get("cell")==[58,44],"source":npc.get("source_script")=="extra/event/hougyoku"}
 var raw:Array=[]
 for entry in b.quest_catalog.npcs:
  if entry is Dictionary and entry.get("id")==SCHOLAR:raw.append(identity_value(entry))
 print("CRYSTAL_IDENTITY ",JSON.stringify({"clauses":clauses,"npc":identity_value(npc),"enabled45":45 in b.quest_catalog.enabled_events,"enabled":identity_value(b.quest_catalog.enabled_events),"override":identity_value(b.quest_catalog.npc_overrides.get(SCHOLAR)),"records":identity_value(b.original_quests.npc_state.records.get(SCHOLAR)),"raw_catalog":raw}))
func run()->void:
 var path:String="user://loot-crystal-success.json"
 if not fresh_paths(path):quit(1);return
 var host=Backend.new();host.set_process(false);host.save_path=path
 var b=host
 check(b.session.gm_raise_level(-1,60),"Disclosed original GM API raises only fixture level60")
 if failures:b.free();quit(1);return
 check(b.save(),"Initial complete profile saved before original dialogue")
 if failures:b.free();quit(1);return
 var npc:Dictionary=b.original_quests.npc_by_id(SCHOLAR)
 print_scholar_identity(b,npc)
 check(not npc.is_empty() and npc.map_id==6000 and NumericSource.same_source(npc.get("cell"),[58,44]) and npc.source_script=="extra/event/hougyoku","Pinned public scholar identity")
 if failures:b.free();quit(1);return
 var branch:Dictionary=npc.branches[1]
 check(branch.type=="REQUEST" and branch.source_branch_index==1 and branch.condition=="LV>59" and branch.actions=={"GetItem":"2764*1"},"Exact original request: no Warp/NpcWarp/target grant")
 if failures:b.free();quit(1);return
 var visit:Dictionary=b.handle({"type":"quest_visit","npc_id":SCHOLAR,"mode":"near"})
 if failures:b.free();quit(1);return
 check(visit.get("ok",false) and visit.has("target"),"Original public near command chooses safe ordinary point")
 if failures:b.free();quit(1);return
 var point:Dictionary=visit.target
 check(int(point.map_id)==6000 and b.automation.position_map==6000 and point.cell==[b.automation.position_cell.x,b.automation.position_cell.y] and maxi(absi(b.automation.position_cell.x-58),absi(b.automation.position_cell.y-44))<=2 and b.original_quests.allowed(b,npc),"Response and real authority satisfy original near rule")
 if failures:b.free();quit(1);return
 var checkpoint:Dictionary=b.handle({"type":"checkpoint","map_id":b.automation.position_map,"x":b.automation.position_cell.x,"y":b.automation.position_cell.y})
 if failures:b.free();quit(1);return
 check(checkpoint.get("ok",false),"Separate original checkpoint stores actual response position")
 if failures:b.free();quit(1);return
 if not archive_pair(b,"before_request"):b.free();quit(1);return
 var before:Dictionary=b.session.snapshot()
 check(not before.original_items.has(2764) and not before.original_items.has(2760) and not Rules.flag(before,"now",45) and not Rules.flag(before,"ended",45) and before.quest_loot==State.empty(),"Fresh precondition, no quest item or budget planted")
 if failures:b.free();quit(1);return
 var npc_before:Dictionary=b.original_quests.npc_by_id(SCHOLAR).duplicate(true)
 var records_before:Dictionary=b.original_quests.npc_state.records.duplicate(true)
 var authority:Vector2i=b.automation.position_cell
 var arrival:Dictionary=arrival_record(b)
 # Expected is computed before talk/yes from source GetItem and NOW semantics.
 var expected:Dictionary=before.duplicate(true)
 var uid:int=int(before.next_original_uid)
 var durability:int=int(Session.OriginalEquipment.ITEMS.get(2764,{}).get("durability",0))
 expected.original_items.append(2764)
 expected.original_instances.append({"uid":uid,"item_id":2764,"durability":durability})
 expected.next_original_uid=uid+1
 expected.original_events.now[45 >> 5]=int(expected.original_events.now[45 >> 5]) | (1 << (45 % 32))
 print("SOURCE_EXPECTED_BEFORE_REQUEST ",JSON.stringify(expected))
 var opened:Dictionary=b.handle({"type":"quest_talk","npc_id":SCHOLAR})
 if failures:b.free();quit(1);return
 check(opened.get("ok",false) and opened.has("dialogue") and b.original_quests.pending.phase=="REQUEST" and b.original_quests.pending.branch==branch,"Original request selected without service bypass")
 if failures:b.free();quit(1);return
 var old_token:String=opened.dialogue.token
 var accepted:Dictionary=b.handle({"type":"quest_choose","token":old_token,"choice":"yes"})
 if failures:b.free();quit(1);return
 check(accepted.get("ok",false) and accepted.has("dialogue") and b.original_quests.pending.phase=="end","Request yes commits, then actual end page")
 if failures:b.free();quit(1);return
 check(b.session.snapshot()==expected and b.last_saved_payload==JSON.stringify(expected),"Complete precomputed source result incl UID/NOW saved, no post-hoc expected")
 if failures:b.free();quit(1);return
 check(b.original_quests.npc_by_id(SCHOLAR)==npc_before and b.original_quests.npc_state.records==records_before and b.automation.position_map==6000 and b.automation.position_cell==authority and arrival_record(b)==arrival,"Request never moves NPC/player or grants arrival")
 if failures:b.free();quit(1);return
 if not archive_pair(b,"after_yes"):b.free();quit(1);return
 if not checked_complete_disk(b):b.free();quit(1);return
 var committed:Dictionary=read_disk(path)
 if failures:b.free();quit(1);return
 var backup:Dictionary=read_disk(path+".bak")
 if failures:b.free();quit(1);return
 var committed_cache:String=b.last_saved_payload
 var end_reply:Dictionary=b.handle({"type":"quest_choose","token":accepted.dialogue.token,"choice":"ok"})
 if failures:b.free();quit(1);return
 check(end_reply.get("ok",false) and b.original_quests.pending.is_empty(),"End ok only closes original page")
 if failures:b.free();quit(1);return
 if not unchanged_after_page(b,expected,committed_cache,committed,backup,npc_before,records_before,authority,arrival,"end_ok"):b.free();quit(1);return
 var stale:Dictionary=b.handle({"type":"quest_choose","token":old_token,"choice":"yes"})
 if failures:b.free();quit(1);return
 check(not stale.get("ok",true) and b.session.snapshot()==expected,"Old request token refuses without another UID/item")
 if failures:b.free();quit(1);return
 if not unchanged_after_page(b,expected,committed_cache,committed,backup,npc_before,records_before,authority,arrival,"old_token"):b.free();quit(1);return
 if not archive_pair(b,"after_stale"):b.free();quit(1);return
 # Independent copy load may migrate/write its own copy. Original is not used as load target.
 var copy_path:String=path+".evidence/reload.json"
 if not fresh_copy(copy_path,committed.bytes):b.free();quit(1);return
 # Freeze the isolated login time to the already saved day, not the live session.
 # No login roll is expected; all current-schema migration branches are idempotent.
 var expected_loaded:Dictionary=expected.duplicate(true)
 var login_time:int=int(expected.player.last_luck_time)
 check(expected.version==Session.SAVE_VERSION and expected.pets.is_empty() and expected.pet_storage.is_empty() and expected.player.has("charm_rules") and expected.has("rebirth"),"Exact current fresh profile load prerequisites")
 if failures:b.free();quit(1);return
 var loaded=Session.new(func():return login_time)
 var login_rng_before:int=loaded.login_rng.state
 var loaded_ok:bool=loaded.load_game(copy_path)
 check(loaded_ok,"New Session loads isolated actual saved bytes")
 if failures:b.free();quit(1);return
 var loaded_profile:Dictionary=loaded.snapshot()
 check(loaded._valid_profile(loaded_profile) and loaded_profile==expected_loaded and loaded.login_rng.state==login_rng_before,"Complete native loaded profile equals independent pre-request-derived expected; same-day login consumes no RNG")
 if failures:b.free();quit(1);return
 print("RELOAD_NATIVE ",JSON.stringify(loaded_profile))
 # Do not normalize actual Session or assume load has no login/migration changes.
 var after_primary:Dictionary=read_disk(path)
 if failures:b.free();quit(1);return
 var after_backup:Dictionary=read_disk(path+".bak")
 if failures:b.free();quit(1);return
 check(after_primary.bytes==committed.bytes and after_backup.bytes==backup.bytes,"New Session recovery writer cannot touch original primary/backup")
 if failures:b.free();quit(1);return
 var copy_after:Dictionary=read_disk(copy_path)
 if failures:b.free();quit(1);return
 var copy_validated:Dictionary=ProfileCompare.validated_copy(loaded,copy_after.bytes.get_string_from_utf8())
 check(copy_validated.get("ok",false),"Whole isolated stored profile validates before copy normalization")
 if failures:b.free();quit(1);return
 check(copy_after.bytes==committed.bytes and copy_validated.profile==expected_loaded and copy_validated.profile==loaded_profile,"Complete isolated primary/expected/native agree; no recovery rewrite for empty current ledger")
 if failures:b.free();quit(1);return
 for suffix in [".bak",".tmp",".resume.json",".resume.json.tmp",".resume.json.bak"]:
  check(not FileAccess.file_exists(copy_path+suffix) and not DirAccess.dir_exists_absolute(copy_path+suffix),"Current clean copy load creates no recovery side files")
  if failures:b.free();quit(1);return
 check(not b.battle_open and b.session._pending.is_empty() and b.session._profile.quest_loot==State.empty() and not b.quest_auto.running,"Stop after original stone, no loot admission or battle")
 if failures:b.free();quit(1);return
 print("CRYSTAL PREREQUISITE: 0 failures; level60 public near fixture; no original travel/loot/roll claim")
 b.free();quit(0)
func unchanged_after_page(b,expected:Dictionary,cache:String,primary:Dictionary,backup:Dictionary,npc:Dictionary,records:Dictionary,cell:Vector2i,arrival:Dictionary,stage:String)->bool:
 check(b.session.snapshot()==expected and b.last_saved_payload==cache,"Complete native/cache unchanged after "+stage)
 if failures:return false
 var disk:Dictionary=read_disk(b.save_path)
 if failures:return false
 var bak:Dictionary=read_disk(b.save_path+".bak")
 if failures:return false
 check(disk.bytes==primary.bytes and bak.bytes==backup.bytes,"Exact primary/backup unchanged after "+stage)
 if failures:return false
 check(b.original_quests.npc_by_id(SCHOLAR)==npc and b.original_quests.npc_state.records==records and b.automation.position_map==6000 and b.automation.position_cell==cell and arrival_record(b)==arrival,"Complete NPC/arrival/authority unchanged after "+stage)
 return failures==0
func fresh_copy(path:String,bytes:PackedByteArray)->bool:
 for suffix in ["", ".bak", ".tmp", ".resume.json", ".resume.json.tmp", ".resume.json.bak"]:
  check(not FileAccess.file_exists(path+suffix) and not DirAccess.dir_exists_absolute(path+suffix),"Isolated reload target never reused")
  if failures:return false
 var file=FileAccess.open(path,FileAccess.WRITE)
 if file==null:check(false,"Copy open error "+str(FileAccess.get_open_error()));return false
 file.store_buffer(bytes);file.flush();var error:int=file.get_error();file.close()
 check(error==OK,"Copy flush successful")
 if failures:return false
 var copied:Dictionary=read_disk(path)
 if failures:return false
 check(copied.get("ok",false) and copied.bytes==bytes,"Copy equals exact actual committed bytes before load")
 return failures==0

func fresh_paths(path:String)->bool:
 for suffix in ["", ".bak", ".tmp", ".resume.json", ".resume.json.tmp", ".resume.json.bak", ".evidence"]:
  check(not FileAccess.file_exists(path+suffix) and not DirAccess.dir_exists_absolute(path+suffix),"New isolated user fixture refuses reused path: "+suffix)
  if failures:return false
 var error:int=DirAccess.make_dir_absolute(path+".evidence")
 check(error==OK,"Create own evidence directory")
 return failures==0
func read_disk(path:String)->Dictionary:
 var file=FileAccess.open(path,FileAccess.READ)
 var opened:int=FileAccess.get_open_error()
 if file==null:
  print("DISK_READ ",path," open_error=",opened)
  check(false,"Actual evidence file open failed");return {"ok":false}
 var declared:int=file.get_length()
 var length_error:int=file.get_error()
 if length_error!=OK:
  file.close();print("DISK_LENGTH ",path," error=",length_error," declared=",declared)
  check(false,"Actual evidence length query failed");return {"ok":false}
 var bytes:PackedByteArray=file.get_buffer(declared)
 var error:int=file.get_error();file.close()
 var context=HashingContext.new();var begun:int=context.start(HashingContext.HASH_SHA256)
 if begun!=OK:check(false,"SHA begin");return {"ok":false}
 var updated:int=context.update(bytes)
 if updated!=OK:check(false,"SHA update");return {"ok":false}
 var digest_bytes:PackedByteArray=context.finish()
 check(digest_bytes.size()==32,"SHA256 finish returns exactly32 bytes")
 if failures:return {"ok":false}
 var digest:String=digest_bytes.hex_encode()
 print("DISK_READ ",path," open=",opened," read=",error," declared=",declared," actual=",bytes.size()," sha256=",digest)
 check(opened==OK and error==OK and declared>0 and bytes.size()==declared,"Whole disk read has explicit valid length and no I/O error")
 if failures:return {"ok":false}
 return {"ok":true,"bytes":bytes,"sha256":digest,"declared":declared,"actual":bytes.size()}
func checked_bytes(path:String)->PackedByteArray:
 var result:Dictionary=read_disk(path)
 return result.bytes if result.get("ok",false) else PackedByteArray()
func archive_pair(b,stage:String)->bool:
 if failures:return false
 for suffix in ["", ".bak"]:
  var result:Dictionary=read_disk(b.save_path+suffix)
  if failures or not result.get("ok",false):return false
  var destination:String=b.save_path+".evidence/"+stage+(".primary" if suffix.is_empty() else ".backup")
  check(not FileAccess.file_exists(destination) and not DirAccess.dir_exists_absolute(destination),"Evidence phase cannot overwrite previous bytes")
  if failures:return false
  var output=FileAccess.open(destination,FileAccess.WRITE)
  if output==null:check(false,"Evidence write open error "+str(FileAccess.get_open_error()));return false
  output.store_buffer(result.bytes);output.flush()
  var error:int=output.get_error();output.close()
  check(error==OK,"Evidence flush status")
  if failures:return false
  var copied:Dictionary=read_disk(destination)
  if failures:return false
  check(copied.get("ok",false) and copied.bytes==result.bytes and copied.sha256==result.sha256,"Evidence copy exact bytes/SHA")
  if failures:return false
 print("ARCHIVED ",stage," blocker=",DirAccess.dir_exists_absolute(b.save_path+".tmp"))
 return true
func checked_complete_disk(b)->bool:
 var raw:Dictionary=read_disk(b.save_path)
 if failures:return false
 var copied:Dictionary=ProfileCompare.validated_copy(b.session,raw.bytes.get_string_from_utf8())
 check(copied.get("ok",false),"Whole stored profile validates before copy normalization")
 if failures:return false
 check(copied.profile==b.session.snapshot(),"Complete native/UID/ledger equals validated stored copy")
 return failures==0
