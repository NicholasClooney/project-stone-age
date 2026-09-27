extends Node
## Keep nearby original objects as Y-sorted sprites, not every tree on an island.
var world: Node2D
var buckets: Dictionary = {}
var visible_props: Dictionary = {}
var center := Vector2i(-99999,-99999)
var radius := -1
const CHUNK := 16
func _ready() -> void:
 for i in range(world.data.objects.size()):
  var entry: Array = world.data.objects[i]
  var key := Vector2i(int(entry[0])/CHUNK,int(entry[1])/CHUNK)
  if not buckets.has(key):buckets[key] = []
  buckets[key].append(i)
func _process(_delta: float) -> void:
 var next := Vector2i(world.unproject(world.camera.get_screen_center_position()).round())
 var view: Vector2 = world.get_viewport_rect().size/world.camera.zoom.x
 var reach := ceili(view.x/128+view.y/96)+12
 if center==next and radius==reach:return
 center=next;radius=reach
 var wanted: Dictionary = {}
 for y in range(maxi(0,(center.y-radius)/CHUNK),(center.y+radius)/CHUNK+1):
  for x in range(maxi(0,(center.x-radius)/CHUNK),(center.x+radius)/CHUNK+1):
   for i in buckets.get(Vector2i(x,y),[]):
    var entry: Array = world.data.objects[i]
    if absi(int(entry[0])-center.x)>radius or absi(int(entry[1])-center.y)>radius:continue
    wanted[i]=true
    if visible_props.has(i):continue
    var id := str(int(entry[2]))
    var metadata: Dictionary = world.data.images[id]
    var pivot := Node2D.new()
    # map.cpp3896: priority3 with nonzero hit always goes behind characters.
    if int(metadata.get("priority",0))==3 and int(metadata.hit)!=0:pivot.z_index=-1
    pivot.position = world.project(Vector2(entry[0],entry[1]))
    var art := Sprite2D.new()
    art.texture=world.textures[id];art.centered=false
    art.position=Vector2(metadata.x,metadata.y)
    pivot.add_child(art)
    world.actors.add_child(pivot)
    visible_props[i]=pivot
 for i in visible_props.keys():
  if not wanted.has(i):
   visible_props[i].queue_free()
   visible_props.erase(i)
