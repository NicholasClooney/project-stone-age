extends SceneTree
const Backend=preload("res://server/backend.gd")
const WsServer=preload("res://server/ws_server.gd")
const Wait=preload("res://tests/support/wait.gd")
const Rules=preload("res://server/original_quests.gd")
const GIRL="jaruga/event/event01_1"
const DOCTOR="jaruga/event/event01_2"
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,note:String) -> bool:
 print(("PASS: " if ok else "FAIL: ")+note)
 if not ok:failures+=1
 return ok
func click(control:Control) -> bool:
 if not check(is_instance_valid(control),"viewport click target exists"):return false
 if not check(await Wait.until(self,func():return control.is_visible_in_tree() and control.size.x>0 and control.size.y>0),"click layout ready"):return false
 var point:Vector2=control.get_global_transform_with_canvas()*(control.size/2)
 var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
 root.push_input(motion,true)
 if not check(await Wait.until(self,func():return root.gui_get_hovered_control()==control),"actual viewport hover reaches target"):return false
 for pressed in [true,false]:
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point
  root.push_input(event,true)
 return true
func trade(b,id:String) -> void:
 if not b.original_quests.pending.is_empty():b.handle({"type":"quest_close","token":b.original_quests.pending.token})
 check(b.handle({"type":"quest_visit","npc_id":id,"mode":"near"}).ok,"source herb visit")
 var r:Dictionary=b.handle({"type":"quest_talk","npc_id":id})
 r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"yes"})
 if r.has("dialogue"):r=b.handle({"type":"quest_choose","token":r.dialogue.token,"choice":"ok"})
 check(r.ok,"source herb transaction")
func helper(world,id:String) -> bool:
 for quest in world.state.derived.quest_helper.quests:
  if int(quest.event)==1:return quest.steps.any(func(step):return step.id=="herb:"+id and step.current and step.actionable)
 return false
func run() -> void:
 var b=Backend.new();b.session._profile.default_companions_claimed=true;root.add_child(b)
 b.session.gm_raise_level(-1,30);b.session.gm_set_base_stat(-1,"vitality",150);b.session.gm_grant_pet(74)
 var uid:String=b.session._profile.pets[0].pet_id;b.session._profile.pets[0].hp=0
 trade(b,GIRL);trade(b,DOCTOR)
 b.session._profile.player.hp=b.session._profile.player.max_hp
 var server=WsServer.new(b,0,"127.0.0.1");root.add_child(server)
 check(server.start()==OK,"herb server uses ephemeral port")
 var script=load("res://scripts/game.gd");script.server_url_override="ws://127.0.0.1:%d"%server.port
 var world=load("res://scenes/main.tscn").instantiate();script.server_url_override=""
 world.profile_persistence=false;world.viewer_prefs_path="user://herb-use-ui-remote.cfg";root.add_child(world)
 check(await Wait.until(self,func():return not world.data.is_empty() and world.link.online) and await Wait.settle(self,world),"real remote herb world connects")
 check(world.backend==null,"remote herb UI has no authority backend")
 var menu=world.adventure_menu
 menu.open_menu("inventory")
 await click(menu.panel.get_node("OriginalItemSlot_0"))
 check(await Wait.until(self,func():return menu.panel.has_node("OriginalItemUse")),"actual slot click reveals original herb use action")
 var description:Label=menu.panel.find_child("OriginalItemDescription",true,false)
 if not check(is_instance_valid(description),"field herb description exists in scroll content"):
  quit(1);return
 check(description.text.contains("野外回复90～110（原标示100）") and description.text.contains("自己或随身宠物") and description.text.contains("满血仍消耗"),"description states precise field recovery, owned targets and full-HP consumption")
 check(description.text.contains("零HP宠物可回复") and description.text.contains("香草战斗使用未接入"),"description preserves zero-HP pet recovery and herb-specific battle limitation")
 check(await Wait.until(self,func():return description.position.y+description.size.y<=404),"description fits above use controls")
 check(not menu.panel.get_node("OriginalItemUse").disabled and world.session.snapshot().player.hp==world.session.snapshot().player.max_hp,"full owner HP keeps original consumption action enabled")
 await click(menu.panel.get_node("OriginalItemUse"))
 check(await Wait.until(self,func():return world.session.snapshot().original_items.is_empty() and not menu.original_item_busy) and await Wait.settle(self,world),"true viewport full-HP click consumes one herb remotely")
 check(helper(world,"medicine") and not Rules.flag(world.session.snapshot(),"ended",1),"consumption returns remote helper to original doctor")
 trade(b,DOCTOR);b.publish();await Wait.settle(self,world)
 menu.open_menu("inventory");await click(menu.panel.get_node("OriginalItemSlot_0"))
 await click(menu.panel.get_node("OriginalItemTarget"))
 check(await Wait.until(self,func():return menu.panel.has_node("OriginalRecoveryTargets")),"viewport target click opens inventory selector")
 var target_button:Button=menu.panel.find_child("OriginalRecoveryTarget_"+uid,true,false)
 check(target_button.tooltip_text==uid and target_button.text.ends_with("0/%d"%b.session.snapshot().pets[0].max_hp),"selector binds actual carried UID including zero-HP pet")
 await click(target_button)
 check(await Wait.until(self,func():return menu.original_use_pet_id==uid and not menu.panel.has_node("OriginalRecoveryTargets")),"actual target viewport click selects exact UID")
 await click(menu.panel.get_node("OriginalItemUse"))
 check(await Wait.until(self,func():return world.session.snapshot().original_items.is_empty() and world.session.snapshot().pets[0].hp>0 and not menu.original_item_busy) and await Wait.settle(self,world),"actual remote use button recovers zero-HP carried pet")
 trade(b,DOCTOR);b.session._profile.player.hp=1;b.publish();await Wait.settle(self,world)
 menu.open_menu("inventory");await click(menu.panel.get_node("OriginalItemSlot_0"))
 menu.original_use_pet_id="";menu.rebuild()
 var before:Dictionary=world.session.snapshot();var server_before:Dictionary=b.session.snapshot();b.save_path="user://missing-herb-ui/save.json"
 await click(menu.panel.get_node("OriginalItemUse"))
 check(await Wait.until(self,func():return not menu.original_item_busy and world.session.last_error=="save_failed") and await Wait.settle(self,world),"remote save refusal clears pending use state")
 check(world.session.snapshot()==before and b.session.snapshot()==server_before and menu.panel.has_node("OriginalItemUse"),"failed remote click retains HP, herb and usable inventory")
 b.save_path=""
 await click(menu.panel.get_node("OriginalItemUse"))
 check(await Wait.until(self,func():return world.session.snapshot().original_items.is_empty() and world.session.snapshot().player.hp>=91 and not menu.original_item_busy),"next actual click succeeds with source recovery after disk issue removed")
 world.link.close();world.music.stop();world.effect.stop();world.queue_free();server.stop();server.queue_free();b.queue_free()
 await process_frame;await process_frame
 DirAccess.remove_absolute(ProjectSettings.globalize_path("user://herb-use-ui-remote.cfg"))
 print("ORIGINAL HERB USE UI: %d failures"%failures)
 quit(1 if failures else 0)
