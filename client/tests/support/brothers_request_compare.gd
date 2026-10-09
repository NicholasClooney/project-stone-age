extends RefCounted
static func first(actual:Variant,expected:Variant,path:String="",depth:int=0)->Dictionary:
	if depth>32:return {"path":path+"/@depth","actual":depth,"expected":"at most 32"}
	# Brothers proposal.cell is an int literal (plan:88), not a JSON copy.
	# branch_data is JSON on both sides; no cross-type exception is needed.
	# No global numeric or key coercion, even for numerically equal values.
	if typeof(actual)!=typeof(expected):return {"path":path,"actual":actual,"expected":expected}
	if actual is Dictionary:
		if actual.get_typed_key_builtin()!=expected.get_typed_key_builtin():return {"path":path+"/@key_builtin","actual":actual.get_typed_key_builtin(),"expected":expected.get_typed_key_builtin()}
		if actual.get_typed_value_builtin()!=expected.get_typed_value_builtin():return {"path":path+"/@value_builtin","actual":actual.get_typed_value_builtin(),"expected":expected.get_typed_value_builtin()}
		if actual.get_typed_key_class_name()!=expected.get_typed_key_class_name():return {"path":path+"/@key_class","actual":actual.get_typed_key_class_name(),"expected":expected.get_typed_key_class_name()}
		if actual.get_typed_value_class_name()!=expected.get_typed_value_class_name():return {"path":path+"/@value_class","actual":actual.get_typed_value_class_name(),"expected":expected.get_typed_value_class_name()}
		if actual.get_typed_key_script()!=expected.get_typed_key_script():return {"path":path+"/@key_script","actual":actual.get_typed_key_script(),"expected":expected.get_typed_key_script()}
		if actual.get_typed_value_script()!=expected.get_typed_value_script():return {"path":path+"/@value_script","actual":actual.get_typed_value_script(),"expected":expected.get_typed_value_script()}
		if actual.size()!=expected.size():return {"path":path+"/@size","actual":actual.size(),"expected":expected.size()}
		for key in expected:
			var found:bool=false
			for actual_key in actual:
				if typeof(actual_key)==typeof(key) and actual_key==key:found=true;break
			if not found:return {"path":path+"/@missing_exact_key","actual":"missing key with required native type","expected":key}
			var child:String=str(key) if path.is_empty() else path+"."+str(key)
			var difference:Dictionary=first(actual[key],expected[key],child,depth+1)
			if not difference.is_empty():return difference
		return {}
	if actual is Array:
		if actual.get_typed_builtin()!=expected.get_typed_builtin():return {"path":path+"/@builtin","actual":actual.get_typed_builtin(),"expected":expected.get_typed_builtin()}
		if actual.get_typed_class_name()!=expected.get_typed_class_name():return {"path":path+"/@class","actual":actual.get_typed_class_name(),"expected":expected.get_typed_class_name()}
		if actual.get_typed_script()!=expected.get_typed_script():return {"path":path+"/@script","actual":actual.get_typed_script(),"expected":expected.get_typed_script()}
		if actual.size()!=expected.size():return {"path":path+"/@size","actual":actual.size(),"expected":expected.size()}
		for index in range(expected.size()):
			var difference:Dictionary=first(actual[index],expected[index],path+"["+str(index)+"]",depth+1)
			if not difference.is_empty():return difference
		return {}
	return {} if actual==expected else {"path":path,"actual":actual,"expected":expected}

static func print_first(difference:Dictionary)->void:
	# One difference only; complete native values, escaped physical newlines.
	# No JSON conversion, truncation, mutation or second prepare invocation.
	print("PREPARE_DIFF path="+str(difference.path).c_escape())
	print("PREPARE_DIFF actual_type="+str(typeof(difference.actual))+" value="+var_to_str(difference.actual).c_escape())
	print("PREPARE_DIFF expected_type="+str(typeof(difference.expected))+" value="+var_to_str(difference.expected).c_escape())
