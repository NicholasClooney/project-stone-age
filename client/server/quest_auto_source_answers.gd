extends RefCounted
## Pure auto-only lookup. No backend, service instance, RNG or action authority.
const DATA_PATH="res://server/quest_auto_source_answers.json"
const DATA_SHA256="34d7013e2e67d2bca606993d7b32915f135ef04cc1d8cf5045424e637c16faef"
var _data:Dictionary={}
var _questions:Dictionary={}
var _load_error:=""

func _init()->void:
 _load(FileAccess.get_file_as_string(DATA_PATH) if FileAccess.file_exists(DATA_PATH) else "")

func _load(raw:String)->void:
 _data={};_questions={};_load_error="原源答案表校验失败。"
 if raw.sha256_text()!=DATA_SHA256:return
 var parsed=JSON.parse_string(raw)
 if not parsed is Dictionary:return
 _data=parsed
 for question in _data.questions:_questions[int(question.id)]=question
 _load_error=""

static func _manual(reason:String)->Dictionary:
 return {"status":"manual","reason":reason}

static func _width(text:String)->String:
 var result:=""
 for index in range(text.length()):
  var code:=text.unicode_at(index)
  result+=String.chr(code-0xfee0) if code>=0xff01 and code<=0xff5e else " " if code==0x3000 else String.chr(code)
 return result.replace("\r\n","\n")

static func _choices(dialogue:Dictionary)->Dictionary:
 var result:Dictionary={}
 if not dialogue.get("choices") is Array:return result
 for choice in dialogue.choices:
  if not choice is Dictionary or not choice.get("id") is String or not choice.get("text") is String:return {}
  if choice.id.is_empty() or result.has(choice.id):return {}
  result[choice.id]=choice.text
 return result

static func _same_set(actual:Array,expected:Array,fold:bool)->bool:
 var left:Array=[];var right:Array=[]
 for value in actual:left.append(_width(str(value)) if fold else str(value))
 for value in expected:right.append(_width(str(value)) if fold else str(value))
 left.sort();right.sort()
 return left==right

func _evidence(source:String,ids:Array=[])->Dictionary:
 var file:="gmsv/data/npc/"+source
 var result:Dictionary={"source":file,"source_sha":_data.sources[file],"table_sha":DATA_SHA256}
 if not ids.is_empty():
  result.question_ids=ids.duplicate()
  result.question_source=_data.question_source
  result.question_sha=_data.sources[_data.question_source]
 return result

func resolve_quiz(source:String,dialogue:Dictionary)->Dictionary:
 if not _load_error.is_empty():return _manual(_load_error)
 if not _data.services.has(source):return _manual("题目来源未审核。")
 var rule:Dictionary=_data.services[source]
 if dialogue.get("npc_id")!=rule.npc_id or dialogue.get("kind")!="golden_bui_quiz" or not dialogue.get("text") is String:return _manual("原题对白来源不匹配。")
 var choices:=_choices(dialogue)
 var form:=0
 if dialogue.get("input")=="text" and choices.size()==2 and choices.get("submit")=="回答" and choices.get("cancel")=="取消":form=4
 elif dialogue.get("input")=="choice" and choices.get("cancel")=="取消":
  if choices.size()==3 and choices.has("1") and choices.has("2"):form=1
  elif choices.size()==4 and choices.has("1") and choices.has("2") and choices.has("3"):form=2
 if form==0:return _manual("原题输入或完整选项不匹配。")
 var header:=RegEx.new()
 header.compile("^猜谜 第 ([0-9]+) / ([0-9]+) 题\\r?\\n")
 var match=header.search(dialogue.text)
 if match==null or int(match.get_string(1))<1 or int(match.get_string(1))>int(rule.count) or int(match.get_string(2))!=int(rule.count):return _manual("原题组次序不匹配。")
 var prompt:String=dialogue.text.substr(match.get_end())
 # Exact lookup first; a width fallback is accepted only with unanimous output.
 for fold in [false,true]:
  var candidates:Array=[]
  for ident in rule.question_ids:
   var question:Dictionary=_questions[int(ident)]
   if int(question.answer_type)!=form:continue
   var expected:String=str(question.text).replace("\\n","\n")
   if (_width(prompt)==_width(expected)) if fold else (prompt==expected):candidates.append(question)
  if candidates.is_empty():continue
  var result:=_resolve_candidates(candidates,choices,form,fold)
  if result.status=="missing":continue
  if result.status=="answer":
   result.evidence=_evidence(source,result.erase_ids)
   result.erase("erase_ids")
  return result
 return _manual("原源表没有一致的题目。")

static func _resolve_candidates(candidates:Array,choices:Dictionary,form:int,fold:bool)->Dictionary:
 var resolved:Array=[];var ids:Array=[]
 for question in candidates:
  var answer:Dictionary={"choice":"submit","text":str(question.options[0])}
  if form!=4:
   var count:=2 if form==1 else 3
   var displayed:Array=[]
   for index in range(count):displayed.append(choices[str(index+1)])
   if not _same_set(displayed,question.options.slice(0,count),fold):continue
   var expected:String=str(question.options[int(question.answer)])
   var matches:Array=[]
   for index in range(count):
    var value:String=choices[str(index+1)]
    if (_width(value)==_width(expected)) if fold else (value==expected):matches.append(str(index+1))
   if matches.size()!=1:return _manual("选项宽度匹配存在歧义。")
   answer={"choice":matches[0]}
  if not resolved.is_empty() and resolved[0]!=answer:return _manual("原源题目答案存在歧义。")
  resolved.append(answer);ids.append(int(question.id))
 if resolved.is_empty():return {"status":"missing"}
 var result:Dictionary=resolved[0].duplicate()
 result.status="answer";result.erase_ids=ids
 return result

func resolve_keyword(source:String,dialogue:Dictionary)->Dictionary:
 if not _load_error.is_empty():return _manual(_load_error)
 if not _data.keywords.has(source):return _manual("口令来源未审核。")
 var rule:Dictionary=_data.keywords[source]
 var choices:=_choices(dialogue)
 if dialogue.get("npc_id")!=rule.npc_id or dialogue.get("kind")!="original_keyword" or dialogue.get("input")!="text":return _manual("口令对白来源不匹配。")
 if choices!={"submit":"说出口令","no":"取消"} or not dialogue.get("text") is String:return _manual("口令输入选项不匹配。")
 if _width(dialogue.text)!=_width(rule.prompt):return _manual("口令原提示不匹配。")
 return {"status":"answer","choice":"submit","text":rule.answer,"evidence":_evidence(source)}
