"""The four actually bound dream-cave AFTER TimeMan instances only."""
import re
BINDINGS={
 'genout/tman_400_95_120':([95,120],16203,16200),
 'genout/tman_400_98_120':([98,120],16202,16200),
 'genout/tman_400_85_102':([85,102],16202,16204),
 'genout/tman_400_88_102':([88,102],16201,16204),
}
def visuals(script,fields,texts):
 if script not in BINDINGS:raise ValueError('Unreviewed TimeMan instance')
 for path in ['gmsv/npc/npc_timeman.c','gmsv/handletime.c','gmsv/include/handletime.h','gmsv/data/npc/genout/npcgen.template']:
  if path not in texts:raise ValueError('TimeMan requires pinned source evidence')
 cell,graphic,alternate=BINDINGS[script]
 if fields.get('floorid')!='400' or fields.get('borncorner')!=','.join(map(str,cell+cell)) or fields.get('graphicname')!=str(graphic) or fields.get('dir')!='6':
  raise ValueError('Changed TimeMan source placement')
 source=texts['gmsv/data/npc/'+script]
 rows=[line.split(':',1) for line in source.splitlines() if line.strip() and not line.lstrip().startswith('#')]
 if any(len(row)!=2 for row in rows) or len(rows)!=4:raise ValueError('Unexpected TimeMan fields')
 args=dict(rows)
 if set(args)!={'time','main_msg','change_msg','change_no'} or args['time']!='AFTER' or args['change_no']!=str(alternate):raise ValueError('Unreviewed TimeMan behavior')
 if any(not args[k] or ',' in args[k] for k in ['main_msg','change_msg']):raise ValueError('Unreviewed randomized TimeMan dialogue')
 return dict(main=dict(graphic=graphic,text=args['main_msg']),changed=dict(graphic=alternate,text=args['change_msg']),
             rule='AFTER',source='gmsv/data/npc/'+script,source_rule='gmsv/npc/npc_timeman.c:50,130-146,173-195; 126 < hour < 300')
