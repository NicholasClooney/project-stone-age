extends RefCounted
## Reviewed quest jobs only; shared by authority and read-only helper UI.
const JOB_EVENTS={2:44,1:4,11:2,30:1,12:3,13:5,24:7,25:8,5:37,9:38}
const JOB_MAPS={1:[10202,10204],11:[1000,2000],30:[3110,200,20101,20102,20103,20104,20105]}
static func supports(job_id:int,event_id:int) -> bool:
 return JOB_EVENTS.get(job_id,-1)==event_id
