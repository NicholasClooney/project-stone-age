extends RefCounted
## Only the reviewed, uncapturable enemy1043/template545. C enemy.c leaves
## negative raw attributes intact. This validates its actual generation bounds;
## it neither clamps actors nor relaxes player/pet/save validation.
const Rules=preload("res://server/progression.gd")
static var source:Dictionary={}
static var template:Dictionary={}
static var loaded:=false
static func validation_shape(actor:Dictionary)->Dictionary:
 if not loaded:
  loaded=true
  var path:="res://assets/legacy/encounters/catalog.json"
  if FileAccess.file_exists(path):
   var catalog=JSON.parse_string(FileAccess.get_file_as_string(path))
   if catalog is Dictionary:
    source=catalog.get("enemies",{}).get("1043",{})
    template=catalog.get("templates",{}).get("545",{})
 if source.is_empty() or template.is_empty():return {}
 if int(source.get("template_id",-1))!=545 or int(source.get("pet_flag",-1))!=0 or not bool(source.get("wait_only",false)):return {}
 if not integer(actor.get("source_enemy_id"),1043,1043) or not integer(actor.get("template_id"),545,545) or str(actor.get("species",""))!="original_545":return {}
 if not actor.get("can_capture") is bool or actor.can_capture or not bool(actor.get("source_wait_only",false)):return {}
 if not integer(actor.get("level"),int(source.level_min),int(source.level_max)):return {}
 if not actor.get("growth_weights") is Array or actor.growth_weights.size()!=4 or not actor.get("base_stats") is Dictionary:return {}
 var factor:=int(template.initial)+(int(actor.level)-1)*int(template.wild_growth)
 if factor<=0:return {}
 var extra_total:=0
 for i in range(4):
  var weight=actor.growth_weights[i]
  var original:=int(template.weights[i])
  if not integer(weight,original-2,original+2):return {}
  var base=actor.base_stats.get(Rules.STATS[i])
  if not integer(base,(original-2)*factor,(original+12)*factor) or int(base)%factor!=0:return {}
  var extra:=int(base)/factor-int(weight)
  if extra<0 or extra>10:return {}
  extra_total+=extra
 if extra_total!=10:return {}
 var expected:=actor.duplicate(true)
 Rules.refresh(expected)
 for key in ["attack","defence","speed","max_hp"]:
  if not integer(actor.get(key),int(expected[key]),int(expected[key])):return {}
 # A validation-only copy allows the existing validator to check every other
 # field without widening its contract. Never return this as the battle actor.
 var shape:=actor.duplicate(true)
 for key in Rules.STATS:shape.base_stats[key]=maxi(0,int(shape.base_stats[key]))
 for i in range(4):shape.growth_weights[i]=maxi(0,int(shape.growth_weights[i]))
 return shape
static func integer(value,low:int,high:int)->bool:
 return (value is int or value is float) and float(value)==floor(float(value)) and value>=low and value<=high
