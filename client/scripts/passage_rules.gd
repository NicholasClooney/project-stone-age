extends RefCounted
## Both directions of all three Seimu sea routes share the profile permit.
## Fixed original map pairs also protect servers with an older imported manifest.
static func requires_permit(origin: int, target: int) -> bool:
	return (origin==40 and target in [31301,31401,31501]) or (target==40 and origin in [31301,31401,31501])
