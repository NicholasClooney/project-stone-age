extends RefCounted
## Reviewed delivery jobs only; shared by authority and read-only helper UI.
const JOB_EVENTS={1:4,11:2,30:1}
const JOB_MAPS={1:[10202,10204],11:[1000,2000],30:[3110,20105]}
static func supports(job_id:int,event_id:int) -> bool:
 return JOB_EVENTS.get(job_id,-1)==event_id
