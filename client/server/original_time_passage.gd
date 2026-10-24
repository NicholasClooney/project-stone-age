extends RefCounted
const WorldClock=preload("res://server/original_world_clock.gd")
## Only imported, explicitly reviewed time gates constrain a destination.
static func check(places,origin:int,cell:Vector2i,target:int,arrival:Array=[])->String:
 if origin==target or target not in [41,42]:return ""
 var guarded:=false
 for links in places.portals.values():
  for link in links.values():
   if int(link.to_map)==target and link.has("requires_time"):guarded=true
 if not guarded:return ""
 var link:Dictionary=places.links(origin).get(cell,{})
 if link.is_empty() or int(link.to_map)!=target:return "请从原梦幻洞窟入口进入。"
 if not arrival.is_empty() and (arrival.size()!=2 or int(arrival[0])!=int(link.target[0]) or int(arrival[1])!=int(link.target[1])):return "梦幻洞窟落点与原入口不一致。"
 if link.has("requires_time") and not WorldClock.allows(str(link.requires_time),WorldClock.hour()):return "此刻原梦幻洞窟入口尚未开放。"
 return ""
