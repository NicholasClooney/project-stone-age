extends "res://tests/permit_shop_remote_ui_test.gd"
# TMP UNRUN: public ProfileHub auth plus real scenes, no fabricated epoch.
const Hub=preload("res://server/profile_hub.gd")
var hub
var account_a:=""
var account_b:=""
func login(w,name:String)->bool:
 if not await ready(func():return w.link.awaiting_login,"Real login-needed arrived"):return false
 var answer:Array=[]
 w.link.login({"type":"login","name":name,"pin":"1234"},func(reply):answer.append(reply.duplicate(true)))
 if not await ready(func():return not answer.is_empty(),"Actual PIN login ACK"):return false
 if not check(answer[0].get("ok",false),"Production accounts accept actual credentials"):return false
 return await ready(func():return w.link.online and w.backend==null and not w.data.is_empty() and not w.area_transition_busy,"Authenticated remote scene ready")
func account_fixture(name:String)->String:
 if not fresh(hub.accounts.path+".tmp","Account database temporary path"):return ""
 var made:Dictionary=hub.accounts.create(name,"1234")
 if not check(made.get("ok",false),"Real isolated account created"):return ""
 var id:String=made.entry.id
 if not fresh_save(hub.accounts.save_path(made.entry)):return ""
 if not check(hub.open_profile(id).is_empty(),"Profile backend opens before clients"):return ""
 var backend=hub.backends[id]
 # open_profile may have created a new initial save; whole account root was absent before hub.start.
 # Refuse a pending temporary writer rather than overwriting any evidence.
 if not fresh(backend.save_path+".tmp","Account preparation tmp"):return ""
 backend.session._profile.player.gold=500;backend.session._profile.no_random_encounters=true
 var located:bool=backend.session.set_location(1100,85,107)
 if not check(located,"Original account fixture location accepted"):return ""
 backend.automation.position_changed(1100,Vector2i(85,107),true)
 if not check(backend.save(),"Ordinary vendor-adjacent initial profile saved"):return ""
 return id
func run()->void:
 root.gui_embed_subwindows=true
 if not fresh("user://permit-lifecycle","Account root"):return
 hub=Hub.new("user://permit-lifecycle/accounts.json");hub.tick=false;hub.share_dir="user://permit-lifecycle/share";root.add_child(hub)
 if not check(hub.start(),"Real ProfileHub starts isolated accounts"):return
 account_a=account_fixture("PermitA")
 if failures>0 or account_a.is_empty():return
 account_b=account_fixture("PermitB")
 if failures>0 or account_b.is_empty():return
 host=hub.backends[account_a];path=host.save_path
 server=Server.new(hub,0,"127.0.0.1");root.add_child(server)
 if not check(server.start()==OK,"ProfileHub real port0 server"):return
 var first=scene(server.port,true)
 if failures>0:return
 if not await login(first,"PermitA"):return
 var second=scene(server.port)
 if failures>0:return
 if not await login(second,"PermitA"):return
 for w in worlds:
  if not check(await Wait.settle(self,w),"Natural initial reports/checkpoints settle"):return
 var before:Dictionary=host.session._profile.duplicate(true)
 if not await open_vendor(first,"genout/ss_1100_86_107"):return
 var page:Dictionary=host.original_quests.pending.duplicate(true)
 var owner_peer:int=page.permit_connection
 print("FEE PAGE OWNER ",owner_peer," epoch=",page.permit_binding.get_instance_id()," open_id=",page.open_id)
 var stolen:Dictionary=await rpc(second.link,{"type":"permit_shop_choose","token":page.token,"choice":"buy_one"})
 if failures>0:return
 if not check(not stolen.get("ok",true) and host.original_quests.pending==page and host.session._profile.duplicate(true)==before,"Other actual device cannot consume original page"):return
 var canceled:Dictionary=await rpc(second.link,{"type":"permit_shop_cancel","open_id":page.open_id})
 if failures>0:return
 if not check(not canceled.get("ok",true) and host.original_quests.pending==page,"Other device cannot cancel original page"):return
 # Real close immediately after an open request, with no awaited response.
 first.world_travel._close()
 if not check(await Wait.settle(self,first) and host.original_quests.pending.is_empty(),"Actual close retires original pending"):return
 first.world_travel._permit_open(first.world_travel.entries[first.world_travel.selected])
 var canceled_open:String=first.world_travel.permit_open_id
 if not check(first.world_travel.permit_busy,"Open is actually in flight before close"):return
 first.world_travel._close()
 if not check(await Wait.settle(self,first) and host.original_quests.pending.is_empty() and not first.world_travel.permit_active,"Same-channel open/cancel finishes without resurrecting UI"):return
 print("FEE CANCELED OPEN ",canceled_open)
 if not await open_vendor(first,"genout/ss_1100_86_107"):return
 page=host.original_quests.pending.duplicate(true)
 first.link.close()
 if not await ready(func():return not host._fee_bindings.has(owner_peer) and host.original_quests.pending.is_empty(),"Actual socket close retires page and epoch"):return
 first.link.connect_now()
 if not await ready(func():return first.link.online,"Original device reconnects using production credentials"):return
 if not check(await Wait.settle(self,first),"Reconnect natural report barrier"):return
 if not await open_vendor(first,"genout/ss_1100_86_107"):return
 var rebound:Dictionary=host.original_quests.pending.duplicate(true)
 if not check(rebound.permit_binding!=page.permit_binding and rebound.open_id!=page.open_id,"New actual connection has new capability and new page"):return
 # Public game_remote hook; keep the endpoint for the genuine main.tscn reload.
 var old_scene_id:int=first.get_instance_id()
 Game.server_url_override="ws://127.0.0.1:%d"%server.port
 first._remote.switch_profile()
 if not check(first.world_travel.permit_auth_retired and not first.world_travel.permit_active,"Logout starts by revoking local page, before async ACK"):return
 if not await ready(func():return not is_instance_id_valid(old_scene_id) and current_scene!=null,"Real successful logout reloads original main scene"):return
 Game.server_url_override=""
 var replacement=current_scene;worlds[0]=replacement
 if not await login(replacement,"PermitB"):return
 var next_host=hub.backends[account_b]
 if not check(host.original_quests.pending.is_empty() and host.session._profile.duplicate(true)==before,"Old page retired without fee across actual logout"):return
 if not await open_vendor(replacement,"genout/ss_1100_86_107"):return
 var next_page:Dictionary=next_host.original_quests.pending.duplicate(true)
 # An old open_id cancel from new authentication is rejected, never clears B.
 var stale:Dictionary=await rpc(replacement.link,{"type":"permit_shop_cancel","open_id":rebound.open_id})
 if failures>0:return
 if not check(not stale.get("ok",true) and next_host.original_quests.pending==next_page,"Old page ID has no authority in later authentication"):return
 var next_id:int=replacement.get_instance_id();replacement.stop_sounds();replacement.queue_free()
 if not await ready(func():return not is_instance_id_valid(next_id) and next_host.original_quests.pending.is_empty(),"Actual scene exit cancels exact B page while its link is still original"):return
 worlds.remove_at(0)
 if not full_saved(before,"lifecycle-A"):return
 # Keep server/hub alive until remaining original client closes naturally.
 second.link.close();var second_id:int=second.get_instance_id();second.stop_sounds();second.queue_free()
 if not await ready(func():return not is_instance_id_valid(second_id),"Second real scene retired"):return
 worlds.clear()
 for view in views:view.queue_free()
 views.clear();server.stop();server.queue_free();hub.queue_free()
 print("PERMIT SHOP REMOTE LIFECYCLE: PASS (F1 only; no general auth/F2 claim)");quit(0)
