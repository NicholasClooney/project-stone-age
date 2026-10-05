extends SceneTree
# TMP UNPARSED/UNRUN; requires committed core fee + complete UI union.
const Base=preload("res://server/backend.gd")
const Equipment=preload("res://server/original_equipment.gd")
const Server=preload("res://server/ws_server.gd")
const Game=preload("res://scripts/game.gd")
const Wait=preload("res://tests/support/wait.gd")
const Compare=preload("res://tests/support/quest_auto_loot_profile_compare.gd")
class TraceBackend extends "res://server/backend.gd":
 var commands:Array=[]
 func handle(command:Dictionary)->Dictionary:
  var copy:Dictionary=command.duplicate(true)
  copy.erase("_fee_binding") # Native capability never serialized as evidence.
  var reply:Dictionary=super.handle(command)
  commands.append({"command":copy,"reply":reply.duplicate(true)})
  print("FEE COMMAND ",JSON.stringify(commands.back()))
  return reply
var host
var server
var worlds:Array=[]
var views:Array=[]
var events:Array=[]
var path:=""
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->bool:
 print(("PASS: " if ok else "FAIL: ")+label)
 if not ok:failures+=1;quit(1)
 return ok
func ready(predicate:Callable,label:String)->bool:
 if failures>0:return false
 var arrived:bool=await Wait.until(self,predicate)
 if failures>0:return false
 return check(arrived,label)
func fresh(file_path:String,label:String)->bool:
 if not check(not DirAccess.dir_exists_absolute(file_path),label+" is not an existing directory"):return false
 var probe=FileAccess.open(file_path,FileAccess.READ)
 var error:int=FileAccess.get_open_error()
 if probe!=null:probe.close();return check(false,label+" refuses existing file")
 return check(error==ERR_FILE_NOT_FOUND,label+" confirmed absent")
func fresh_save(file_path:String)->bool:
 for suffix in ["",".bak",".tmp"]:
  if not fresh(file_path+suffix,"New isolated SAVE"+suffix):return false
 return true
func record(event:Dictionary)->void:
 if event.get("type")=="quest_result":events.append(event.duplicate(true));print("FEE FACT ",JSON.stringify(event))
func rpc(link,command:Dictionary)->Dictionary:
 var result:Array=[]
 link.request(command,func(reply:Dictionary):result.append(reply.duplicate(true)))
 if not await ready(func():return not result.is_empty(),"Actual command ACK"):return {}
 if failures>0:return {}
 return result[0]
func scene(port:int,primary:bool=false):
 Game.server_url_override="ws://127.0.0.1:%d"%port
 var w=load("res://scenes/main.tscn").instantiate();Game.server_url_override=""
 w.profile_persistence=false;w.viewer_prefs_path="user://fee-view-%s-%d.cfg"%[path.get_file(),worlds.size()]
 if not fresh(w.viewer_prefs_path,"Viewer preference output"):w.free();return null
 if primary:
  root.add_child(w);current_scene=w
 else:
  var viewport=SubViewport.new();viewport.size=Vector2i(1280,720);root.add_child(viewport)
  views.append(viewport);viewport.add_child(w)
 worlds.append(w)
 return w
func click(control:Control)->bool:
 if not check(is_instance_valid(control) and control.is_visible_in_tree() and not control.disabled,"Actual visible enabled control"):return false
 var viewport=control.get_viewport();var point:Vector2=control.get_global_rect().get_center()
 var hover=InputEventMouseMotion.new();hover.position=point;viewport.push_input(hover,true)
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;viewport.push_input(event,true)
 return true
func setup_case(map_id:int,cell:Vector2i,gold:int,label:String)->bool:
 host=TraceBackend.new();host.set_process(false)
 host.session._profile.player.gold=gold;host.session._profile.no_random_encounters=true
 var located:bool=host.session.set_location(map_id,cell.x,cell.y)
 if not check(located,"Original fixture location accepted"):return false
 host.automation.position_changed(map_id,cell,true)
 path="user://permit-%s.json"%label;host.save_path=path
 if not fresh_save(path):return false
 if not check(host.save(),"Isolated public vendor-adjacent initial profile saved"):return false
 root.add_child(host);host.set_process(false);host.event.connect(record)
 server=Server.new(host,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"Actual port0 server"):return false
 for index in range(2):
  var w=scene(server.port)
  if failures>0:return false
  if not await ready(func():return w.link.online and not w.data.is_empty() and not w.area_transition_busy,"Production scene ready"):return false
  if not check(w.backend==null and await Wait.settle(self,w),"Remote backend=null and natural reports settled"):return false
 return true
func open_vendor(w,source:String)->bool:
 var ui=w.world_travel;var index:=-1
 for i in range(ui.entries.size()):
  if ui.entries[i].get("dialogue_source","")=="gmsv/data/npc/"+source:index=i
 if not check(index>=0,"Exact original resident source present"):return false
 # Original actor input; standing adjacent is fixture, not an arrival proof.
 var sprite=ui.sprites[index]
 var point:Vector2=sprite.get_global_transform_with_canvas()*sprite.get_rect().get_center()
 for pressed in [true,false]:
  var event=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;w.get_viewport().push_input(event,true)
 return await ready(func():return ui.permit_active and not ui.permit_busy and not ui.permit_token.is_empty(),"Original open ACK exposes frozen token")
func raw_read(file_path:String,allow_missing:bool)->Dictionary:
 if not check(not DirAccess.dir_exists_absolute(file_path),"Raw path is not a directory"):return {}
 var file=FileAccess.open(file_path,FileAccess.READ)
 var opened:int=FileAccess.get_open_error()
 if file==null:
  if not check(allow_missing and opened==ERR_FILE_NOT_FOUND,"Only backup ERR_FILE_NOT_FOUND may be absent"):return {}
  return {"exists":false}
 var size:int=file.get_length();var length_error:int=file.get_error()
 if length_error!=OK:
  file.close();check(false,"Raw length query succeeds");return {}
 var bytes:PackedByteArray=file.get_buffer(size);var error:int=file.get_error();file.close()
 if not check(bytes.size()==size and error==OK,"Complete raw evidence reads"):return {}
 return {"exists":true,"bytes":bytes}
func raw_record(stage:String)->Dictionary:
 var result:Dictionary={}
 for suffix in ["",".bak"]:
  var item:Dictionary=raw_read(path+suffix,suffix==".bak")
  if failures>0:return {}
  result[suffix]=item
  if not item.exists:continue
  var archive_path:String="user://%s-%s%s.raw"%[path.get_file(),stage,suffix]
  if not fresh(archive_path,"Evidence archive"):return {}
  var archive=FileAccess.open(archive_path,FileAccess.WRITE)
  if not check(archive!=null,"Evidence archive opens"):return {}
  archive.store_buffer(item.bytes);var written:int=archive.get_error();archive.close()
  if not check(written==OK,"Evidence archive writes"):return {}
  var readback:Dictionary=raw_read(archive_path,false)
  if failures>0:return {}
  if not check(readback.bytes==item.bytes,"Closed archive readback complete bytes equal"):return {}
 print("FEE DISK ",stage," primary/cache_equal=",result[""].bytes==host.last_saved_payload.to_utf8_buffer())
 return result
func full_saved(expected:Dictionary,stage:String)->bool:
 var record:Dictionary=raw_record(stage)
 if failures>0:return false
 var copy:Dictionary=Compare.validated_copy(host.session,record[""].bytes.get_string_from_utf8())
 if not check(copy.get("ok",false),"Complete raw profile validates"):return false
 var native:Dictionary=host.session._profile.duplicate(true)
 return check(copy.profile==expected and native==expected and record[""].bytes==host.last_saved_payload.to_utf8_buffer(),"Full native/cache/validated raw primary agree: "+stage)
func dispose()->bool:
 var retired:Array=[]
 for w in worlds:
  retired.append(w.get_instance_id());w.link.close();w.stop_sounds();w.queue_free()
 if not await ready(func():return retired.all(func(id):return not is_instance_id_valid(id)),"Remote scenes retired"):return false
 for view in views:view.queue_free()
 worlds.clear();views.clear();server.stop();server.queue_free();host.queue_free();events.clear()
 return true
func purchase_case(map_id:int,cell:Vector2i,source:String,gold:int,blocked:bool)->bool:
 if not await setup_case(map_id,cell,gold,"%d-%d-%s"%[map_id,gold,blocked]):return false
 if not await open_vendor(worlds[0],source):return false
 for w in worlds:
  if not check(await Wait.settle(self,w),"Before transaction natural checkpoint barrier"):return false
 var before:Dictionary=host.session._profile.duplicate(true);var expected:Dictionary=before.duplicate(true)
 if gold>=200 and not blocked:
  expected.player.gold-=200;Equipment.add(expected,2422)
 var disk_before:Dictionary=raw_record("before")
 if failures>0:return false
 if blocked:
  if not fresh(path+".tmp","Actual tmp blocker path"):return false
  if not check(DirAccess.make_dir_absolute(path+".tmp")==OK,"Own actual tmp writer blocker"):return false
 var start:int=host.commands.size()
 if not await click(worlds[0].world_travel.choice):return false
 if not await ready(func():return host.commands.slice(start).any(func(row):return row.command.get("type")=="permit_shop_choose"),"Production button sends actual choose"):return false
 for w in worlds:
  if not check(await Wait.settle(self,w),"Transaction final ACK/event barrier"):return false
 var choices:Array=host.commands.slice(start).filter(func(row):return row.command.get("type")=="permit_shop_choose")
 if not check(choices.size()==1,"One real UI choice, no automatic replay"):return false
 var reply:Dictionary=choices[0].reply
 var success:bool=gold>=200 and not blocked
 if not check(bool(reply.get("ok",false))==success and bool(reply.get("committed",false))==success,"Only actual committed ACK is successful"):return false
 if not full_saved(expected,"after"):return false
 for w in worlds:
  if not check(w.state.full_profile()==expected,"Both production clients consume full authoritative profile"):return false
 if success:
  if not check(events.size()==1 and str(events[0].text).contains("扣除200石币") and str(events[0].text).contains("提交后余额%d"%int(expected.player.gold)),"Exact committed fee fact"):return false
 else:
  var failure_disk:Dictionary=raw_record("failure")
  if failures>0:return false
  if not check(events.is_empty() and failure_disk==disk_before and not str(reply.get("reason","")).is_empty(),"Rejected fee has no fact and preserves complete primary/backup"):return false
  if not check(worlds[0].world_travel.body.text==str(reply.reason),"Actual failure reason is shown"):return false
 # No cleanup of blocker; terminal fixture evidence survives failure or success.
 return await dispose()
func run()->void:
 root.gui_embed_subwindows=true
 for row in [[1100,Vector2i(85,107),"genout/ss_1100_86_107",500,false],[4000,Vector2i(98,85),"genout/ss_4000_99_85",500,false],[1100,Vector2i(85,107),"genout/ss_1100_86_107",199,false],[1100,Vector2i(85,107),"genout/ss_1100_86_107",500,true]]:
  if not await purchase_case(row[0],row[1],row[2],row[3],row[4]):return
 print("PERMIT SHOP REMOTE UI: PASS (public vendor fixture, no route proof)");quit(0)
