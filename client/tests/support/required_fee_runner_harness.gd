extends SceneTree
## UNRUN. Independent full-profile and exact three-file oracle.
const Backend=preload("res://tests/support/required_fee_runner_backend.gd")
const Fault=preload("res://tests/support/required_fee_runner_session.gd")
const Fact=preload("res://server/required_fee_runner_fact.gd")
const ManualFact=preload("res://server/required_fee_fact.gd")
const SHOP="genout/ss_1100_86_107"
const GATE="genout/wpm_40_13_1@40:13:1"
var checks:int=0
var failures:int=0
var fixtures:int=0
var load_calls:int=0
var transactions:Dictionary={}
func _initialize()->void:call_deferred("run")
func run()->void:quit(1)
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;push_error(label)
func raw(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return {"exists":false,"bytes":PackedByteArray()}
 var file=FileAccess.open(path,FileAccess.READ)
 if file==null:check(false,"oracle read failed "+path);return {"unknown":true}
 var length:int=file.get_length();var bytes:PackedByteArray=file.get_buffer(length)
 var error:Error=file.get_error();file.close()
 check(error==OK and bytes.size()==length,"complete independent disk observation")
 return {"exists":true,"bytes":bytes}
func rows(c:Dictionary)->Array:return [raw(c.path),raw(c.path+".bak"),raw(c.path+".tmp")]
func setup(tag:String,kind:String="permit",owned:bool=false)->Dictionary:
 fixtures+=1;print("D0 FIXTURE ",fixtures," ",tag," begin")
 var b=Backend.new();b.set_process(false)
 var rng=RandomNumberGenerator.new();rng.seed=7319
 var s=Fault.new(func():return 1791504000,rng);s.host=weakref(b);b.session=s
 s.battle_pets_hook=b._live_battle_pets;s.capture_entry_hook=b._capture_entry
 s._profile.player.gold=1000;s._profile.travel_pass=owned;s._profile.no_random_encounters=true
 if not 46 in b.quest_catalog.enabled_events:b.quest_catalog.enabled_events.append(46)
 var map_id:int=40 if kind=="seimu" else 1100
 var cell:Vector2i=Vector2i(12,1) if kind=="seimu" else Vector2i(85,107)
 s.set_location(map_id,cell.x,cell.y);b.automation.position_changed(map_id,cell,true)
 b.save_path="user://d0-%03d-%s.json"%[fixtures,tag]
 for suffix in ["",".bak",".tmp"]:check(not FileAccess.file_exists(b.save_path+suffix),"fresh preserved fixture")
 check(b.save(),tag+": real initial save")
 load_calls+=1;check(b.load_profile(b.save_path),tag+": real canonical load")
 b.automation.position_changed(map_id,cell,true)
 check(b.save(),tag+": canonical resave")
 b.fee_attach(71)
 return {"b":b,"s":s,"tag":tag,"path":b.save_path,"kind":kind,"source":GATE if kind=="seimu" else SHOP}
func arm(c:Dictionary)->RefCounted:
 var q=c.b.quest_auto
 q.identity.begin();q.identity.select_step("d0:test-only-producer")
 q.running=true;q.internal=true;q.detached=false;q.connection=71;q.client="private-fixture";q.phase="travel"
 c.s.reads=0;c.s.trace=[]
 var cap:RefCounted=c.b.issue(c.kind,c.source)
 check(cap!=null,c.tag+": exact private fixture producer accepted (not a Start test)")
 return cap
func before(c:Dictionary)->Dictionary:
 return {"profile":c.s._profile.duplicate(true),"cache":c.b.last_saved_payload,"serial":c.b.quest_save_serial,"rows":rows(c),"pending":c.s._pending.duplicate(true),"map":c.b.automation.position_map,"cell":c.b.automation.position_cell}
func paid(value:Dictionary,kind:String)->Dictionary:
 var p:Dictionary=value.duplicate(true)
 p.player.gold-=200 if kind=="permit" else 300
 if kind=="permit":p.travel_pass=true
 else:p.location={"map_id":31301,"x":10,"y":104}
 return p
func expected_fact(c:Dictionary,p:Dictionary,tx:String,serial:int)->Dictionary:
 # Whole literal independent contract. Never calls production projection.
 var fact:Dictionary={"schema":1,"scope":"profile","origin":"automatic_required","owner":{"profile_id":p.profile_id,"character_id":p.character_id},"transaction_id":tx,"fee_kind":"undersea_permit200" if c.kind=="permit" else "seimu300","phase":"permit_purchase" if c.kind=="permit" else "gate_crossing","source_id":c.source,"currency":"stone","amount":200 if c.kind=="permit" else 300,"balance_before":p.player.gold+(200 if c.kind=="permit" else 300),"balance_after":p.player.gold,"status":"committed","durability":"disk","save_serial":serial,"candidate_sha256":JSON.stringify(p).sha256_text()}
 if c.kind=="permit":fact.entitlement="travel_pass"
 else:fact.destination={"map_id":31301,"cell":[10,104]}
 return fact
func tx(c:Dictionary)->String:
 var id:String=c.b.writer_observation.get("transaction_id","")
 check(id.length()==32 and id.is_valid_hex_number() and id==id.to_lower() and not transactions.has(id),c.tag+": fresh independent server transaction")
 transactions[id]=true
 return id
func finish(c:Dictionary)->void:
 check(c.b._required_fee_runner._op.is_empty() and c.b._fee_attempt_writer_call==null,c.tag+": operation released")
 c.b.after=Callable() # test hook only; never clear product authority.
 print("D0 FIXTURE ",fixtures," ",c.tag," end")
 c.b.free()
func summary(name:String)->void:
 print(name+": %d checks; %d failures; %d fixtures; %d real loads"%[checks,failures,fixtures,load_calls])
 quit(1 if failures else 0)
