extends RefCounted
## Same-map dream movement is bounded by the original rooms and warp source.
## Server battle settlement and host-owned party follow use their existing paths.
const Dream=preload("res://server/dream_cave_helper.gd")
const Clock=preload("res://server/original_world_clock.gd")
static func check(places,origin:int,cell:Vector2i,target:int,arrival)->String:
 if origin!=target or target not in [41,42]:return ""
 if places.info(target).is_empty() or not FileAccess.file_exists(places.file(target)) or not arrival is Array or arrival.size()!=2:return "梦幻洞窟位置无法核验，请重新进入原入口。"
 for value in arrival:
  if not (value is int or value is float) or not is_finite(float(value)) or float(value)!=floor(float(value)):return "梦幻洞窟位置无效。"
 var point:=Vector2i(int(arrival[0]),int(arrival[1]))
 var before:=Dream.region(origin,cell)
 var after:=Dream.region(target,point)
 if before<0 or after<0:return "梦幻洞窟位置不在可通行区域。"
 if before==after:return ""
 # Knowing an arrival coordinate is insufficient: the character must stand
 # on the actual active source warp, and its original target must match.
 var link:Dictionary=places.links(origin).get(cell,{})
 var landing:Array=link.get("target",[])
 if link.is_empty() or bool(link.get("disabled",false)) or int(link.get("to_map",-1))!=target or landing.size()!=2 or Vector2i(int(landing[0]),int(landing[1]))!=point:return "请沿梦幻洞窟原传送路线前进；不能瞬移跨过隔墙或终战守卫。"
 if link.has("requires_time") and not Clock.allows(str(link.requires_time),Clock.hour()):return "此刻原梦幻洞窟入口尚未开放。"
 return ""
