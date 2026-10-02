extends RefCounted
## Geometry only; authority validates the actual range and quest conditions.

static func offsets() -> Array[Vector2i]:
 var result: Array[Vector2i]=[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
 for y in range(-2,3):
  for x in range(-2,3):
   var cell:=Vector2i(x,y)
   if cell!=Vector2i.ZERO and cell not in result:result.append(cell)
 return result
