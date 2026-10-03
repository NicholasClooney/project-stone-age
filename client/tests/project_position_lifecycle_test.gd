extends "res://tests/lan_party_test.gd"
class Shell extends Node:
 var data:Dictionary={"map_id":41}
 var cell:=Vector2i(34,42)
 var _follow:Array=[41,Vector2i(35,42)]
 var _followed:Array=[]
 var moving:=true
 var area_transition_busy:=false
 var checkpoints:=0
 var paused_input:=true
 var message:=Label.new()
 func checkpoint()->void:checkpoints+=1
 func clear_input()->void:pass
 func _exit_tree()->void:message.free()
class Menu extends "res://scripts/dev_map_overview.gd":
 func _ready()->void:pass
func run()->void:
 var w=Shell.new();root.add_child(w)
 var menu=Menu.new();menu.world=w;menu.note=Label.new();menu.add_child(menu.note);root.add_child(menu)
 menu._project_travel_ticket=1;menu._project_travel_pending=true
 menu._finish_project_move({"ok":true},41,Vector2i(35,42),1)
 w._follow=[41,Vector2i(36,42)]
 await process_frame;await process_frame
 check(w.checkpoints==0 and not menu._project_travel_pending,"second device supersedes awaited target without checkpoint or closing menu")
 menu._project_travel_ticket=2;menu._project_travel_pending=true;w._follow=[41,Vector2i(35,42)]
 menu._finish_project_move({"ok":true},41,Vector2i(35,42),2)
 menu._cancel_project_wait();menu.show()
 w.cell=Vector2i(35,42);w.moving=false
 await process_frame;await process_frame
 check(w.checkpoints==0 and menu.visible,"stale callback cannot close later panel or checkpoint")
 menu._project_travel_ticket=3;menu._project_travel_pending=true;w.moving=true
 menu._finish_project_move({"ok":true},41,Vector2i(35,42),3)
 w.queue_free();await process_frame;await process_frame
 menu._finish_project_move({"ok":false,"reason":"late"},41,Vector2i(35,42),3)
 check(is_instance_valid(menu),"scene freed during wait and late reply avoid invalid world access")
 menu.queue_free();await process_frame
 dir="user://project-party-%d"%OS.get_process_id();remove_tree(dir);DirAccess.make_dir_recursive_absolute(dir)
 var hub=ProfileHub.new(dir+"/accounts.json");root.add_child(hub);check(hub.start(),"real profile hub starts")
 check(hub.handle(1,{"type":"create_profile","name":"Alice","pin":"1111"}).ok,"leader profile created")
 check(hub.handle(2,{"type":"create_profile","name":"Bob","pin":"2222"}).ok,"member profile created")
 report(hub,1,1000,Vector2i(81,90));report(hub,2,1000,Vector2i(80,90))
 check(hub.handle(2,{"type":"party_join","facing":EAST}).ok,"real party joined")
 for connection in [1,2]:
  var b=hub.backend_of(connection);var before:Vector2i=b.automation.position_cell
  var result:Dictionary=hub.handle(connection,{"type":"project_position","map_id":1000,"cell":[82,90]})
  check(not result.ok and str(result.get("reason","")).contains("组队") and b.automation.position_cell==before,"new command cannot bypass leader or member party travel restriction")
 hub.queue_free();await process_frame;remove_tree(dir)
 print("PROJECT POSITION LIFECYCLE: %d failures"%failures);quit(1 if failures else 0)
