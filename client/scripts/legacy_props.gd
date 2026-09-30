extends Node
## Keep nearby original objects as Y-sorted sprites, not every tree on an island.
var world: Node2D
var buckets: Dictionary = {}
var visible_props: Dictionary = {}
var center := Vector2i(-99999,-99999)
var radius := -1
const CHUNK := 16
func _ready() -> void:
 var objects: PackedInt32Array = world.data.objects
 for i in range(objects.size()/3):
  var key := Vector2i(objects[i*3]/CHUNK,objects[i*3+1]/CHUNK)
  if not buckets.has(key):buckets[key] = []
  buckets[key].append(i)
func _process(_delta: float) -> void:
 var next := Vector2i(world.unproject(world.camera.get_screen_center_position()).round())
 var view: Vector2 = world.get_viewport_rect().size/world.camera.zoom.x
 var reach := ceili(view.x/128+view.y/96)+12
 if center==next and radius==reach:return
 center=next;radius=reach
 var wanted: Dictionary = {}
 var objects: PackedInt32Array = world.data.objects
 for y in range(maxi(0,(center.y-radius)/CHUNK),(center.y+radius)/CHUNK+1):
  for x in range(maxi(0,(center.x-radius)/CHUNK),(center.x+radius)/CHUNK+1):
   for i in buckets.get(Vector2i(x,y),[]):
    var entry := Vector3i(objects[i*3],objects[i*3+1],objects[i*3+2])
    if absi(entry.x-center.x)>radius or absi(entry.y-center.y)>radius:continue
    wanted[i]=true
    if visible_props.has(i):continue
    var id := str(entry.z)
    var metadata: Dictionary = world.data.images[id]
    var pivot := Node2D.new()
    # map.cpp3896: priority3 with nonzero hit always goes behind characters.
    if int(metadata.get("priority",0))==3 and int(metadata.hit)!=0:pivot.z_index=-1
    pivot.position = world.project(Vector2(entry.x,entry.y))
    var art := Sprite2D.new()
    art.texture=world.texture(id);art.centered=false
    art.position=Vector2(metadata.x,metadata.y)
    pivot.add_child(art)
    world.actors.add_child(pivot)
    visible_props[i]=pivot
 for i in visible_props.keys():
  if not wanted.has(i):
   visible_props[i].queue_free()
   visible_props.erase(i)
