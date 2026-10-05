extends RefCounted
## Test-only storage boundary. Never normalize live profiles, candidates or CAS.
## Preserve raw file bytes separately; this helper does not write or migrate.
static func validated_copy(session,text:String)->Dictionary:
 var parser:=JSON.new()
 if parser.parse(text)!=OK:return {"ok":false,"reason":"Malformed stored JSON"}
 var raw:Variant=parser.data
 if not raw is Dictionary or not session._valid_profile(raw):
  return {"ok":false,"reason":"Complete stored profile rejected before normalization"}
 return {"ok":true,"profile":session._normalize_numbers(raw)}
