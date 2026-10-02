extends RefCounted
## Labels only. Never applies magic, resistances or unsupported stats to combat.
const Equipment=preload("res://server/original_equipment.gd")
static func resolve(item:Dictionary)->Array:
 var result:Array=item.get("effects",[]).duplicate(true)
 var definition:Dictionary=Equipment.ITEMS.get(int(item.get("id",0)),{})
 for source in item.get("stats_source",[]):
  var entry:Dictionary=source.duplicate(true)
  var low:=int(entry.raw.min);var high:=int(entry.raw.max)
  entry.active=not definition.is_empty() and str(entry.stat) in Equipment.STATS and low==high and int(definition.get(str(entry.stat),0))==low
  entry.reason="装备时生效" if entry.active else ("原随机属性尚未接入装备实例" if low!=high else "此原装备属性尚未实现")
  result.append(entry)
 return result
static func lines(item:Dictionary,only_inactive:=true)->Array[String]:
 var result:Array[String]=[]
 for effect in resolve(item):
  if only_inactive and bool(effect.get("active",false)):continue
  var detail:=""
  var raw:Dictionary=effect.get("raw",{})
  if raw.has("min"):
   detail="%+d"%int(raw.min) if int(raw.min)==int(raw.max) else "%+d～%+d"%[int(raw.min),int(raw.max)]
  elif str(effect.type)=="magic":detail="编号%s / 概率%s / 气力%s"%[str(raw.get("magicid","")),str(raw.get("magicprob","")),str(raw.get("magicusemp",""))]
  elif str(effect.type)=="use":detail=str(raw.get("function",""))+" "+str(raw.get("argument",""))
  elif raw.has("item_type"):detail="type="+str(raw.item_type)
  result.append("【%s】%s %s"%["装备/使用时生效" if bool(effect.get("active",false)) else "未生效",str(effect.label),detail])
 return result
static func evidence(item:Dictionary)->String:
 var result:Array[String]=[]
 for effect in resolve(item):
  var source:Dictionary=effect.get("source",{})
  result.append("%s：%s；%s:%s 零基列%s；%s"%[str(effect.label),JSON.stringify(effect.get("raw",{})),str(source.get("path","")),str(source.get("line","")),JSON.stringify(source.get("columns",[])),str(effect.get("reason",""))])
 return "\n".join(result)
