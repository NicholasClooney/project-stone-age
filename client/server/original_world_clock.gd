extends RefCounted
## One authoritative server clock, shared by every character. Never a client field.
## handletime.c RealTimeToLSTime/getLSTime; npc_timeman.c AFTER is separate.
const ERA:=912771809
static var clock:Callable=func():return Time.get_unix_time_from_system()
static func hour_at(unix_seconds:int)->int:
 # GDScript integer remainder/division, like original C, truncate toward zero.
 return ((unix_seconds-ERA)%5400)*1024/5400
static func hour()->int:return hour_at(int(clock.call()))
static func phase_at(value:int)->String:
 if value>700 and value<=930:return "M"
 if value>200 and value<=300:return "E"
 if value>300 and value<=700:return "N"
 return "A"
static func allows(event:String,value:int)->bool:
 var phase:=phase_at(value)
 match event:
  "A":return phase in ["A","E"]
  "M":return phase=="M"
  "N":return phase=="N"
 return false
static func after_at(value:int)->bool:return value>126 and value<300
