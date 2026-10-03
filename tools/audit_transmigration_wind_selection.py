"""Extract original C predicate and pet eligibility; no live server/save access."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
from audit_transmigration_conditions import function

ROOT=Path(__file__).resolve().parents[1]
REFERENCE=ROOT/'references/chenmingbiao-stone-age'

def run():
    spec=json.loads((ROOT/'tools/transmigration_foundation_sources.json').read_text())
    paths=['gmsv/util.c','gmsv/npc/npcutil.c','gmsv/npc/npc_exchangeman.c','gmsv/data/npc/sainasu/event/genou_2']
    sources={}
    for p in paths:
        raw=(REFERENCE/p).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=spec['sources'][p]:raise ValueError('Original bytes changed: '+p)
        sources[p]=raw.decode('gb18030',errors='replace')
    conditions=re.findall(r'^EVENT:(.*)$',sources[paths[3]],re.M)[:3]
    c=r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define BOOL int
#define TRUE 1
#define FALSE 0
#define IS_2BYTEWORD(x) ((unsigned char)(x)>127)
#define getStringFromIndexWithDelim(a,b,c,d,e) getStringFromIndexWithDelim_body(a,b,c,d,e,__FILE__,__LINE__)
#define NPC_UTIL_GETARGSTR_BUFSIZE 4096
#define CHAR_MAXPETHAVE 5
#define CHAR_PETID 1
#define CHAR_ENDEVENT 2
#define CHAR_LV 3
#define CHAR_WORKSHOPRELEVANTSEC 4
#define print printf
int level=80,bracelet=0,end4=0,end42=0,petlevel[5]={0},petevent[5]={0},petkind[5]={95,95,95,95,95};
void strcpysafe(char*b,int n,char*s){snprintf(b,n,"%s",s);}
void strncpysafe(char*b,int n,char*s,int z){int k=z<n-1?z:n-1;memcpy(b,s,k);b[k]=0;}
int CHAR_getCharPet(int talker,int i){return petlevel[i]?i:-1;}
int CHAR_getInt(int i,int key){return key==CHAR_PETID?petkind[i]:key==CHAR_ENDEVENT?petevent[i]:petlevel[i];}
int CHAR_getWorkInt(int i,int key){return 0;}
void CHAR_setWorkInt(int i,int key,int value){}
char* CHAR_getUseName(int i){return "renamed";}
char* NPC_Util_GetArgStr(int i,char*b,int n){return NULL;}
BOOL NPC_EventLevelCheck(int a,int b,int n,int op){return op==2?level>n:level==n;}
BOOL NPC_EventItemCheck(int a,int b,int n,int op){return n==2758 && bracelet;}
BOOL NPC_ENDEventNoCheck(int a,int b,int n,int op){return n==4?end4:n==42?end42:0;}
BOOL NPC_NOWEventNoCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_SavePointCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_TiemCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_ImageCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_EventReduce(int a,int b,char*s){return 0;}
'''
    names=[(paths[0],'ScanOneByte'),(paths[0],'getStringFromIndexWithDelim_body'),(paths[1],'NPC_Util_GetStrFromStrWithDelim'),
           (paths[2],'NPC_EventBigSmallLastCheck'),(paths[2],'NPC_PetLvCheck'),(paths[2],'NPC_PetLvCheckType2'),
           (paths[2],'NPC_EventFreeIfCheck'),(paths[2],'NPC_EventBigSmallCheck'),(paths[2],'NPC_ExChangeManEventCheck')]
    for p,name in names:c+='\n'+function(sources[p],name)+'\n'
    c+='\nchar *conditions[]={'+','.join(json.dumps('EVENT:'+s) for s in conditions)+'};\n'
    c+=r'''
int main(void){
 int levels[]={1,42,43,59,60,61};
 for(end4=0;end4<=1;end4++)for(end42=0;end42<=1;end42++)for(bracelet=0;bracelet<=1;bracelet++)
 for(int l=0;l<6;l++)for(int ev=0;ev<=1;ev++){
  petlevel[0]=levels[l];petevent[0]=ev?41:0;int selected=-1;
  for(int i=0;i<3;i++)if(NPC_ExChangeManEventCheck(0,0,conditions[i])!=-1){selected=i;break;}
  int expected=(!ev&&end4&&end42&&levels[l]>=61)?0:(!ev&&bracelet&&levels[l]>=43)?1:(!ev&&bracelet)?2:-1;
  if(selected!=expected){printf("MISMATCH %d %d %d %d %d: %d != %d\n",end4,end42,bracelet,levels[l],ev,selected,expected);return 1;}
 }
 petlevel[0]=60;petlevel[1]=61;petlevel[2]=70;petlevel[3]=59;petlevel[4]=61;
 petevent[0]=petevent[1]=petevent[3]=petevent[4]=0;petevent[2]=41;petkind[4]=94;
 end4=end42=1;bracelet=0;
 if(NPC_ExChangeManEventCheck(0,0,conditions[0])==-1)return 2;
 for(int i=0;i<5;i++)if(NPC_PetLvCheckType2(i,0,0,"PET>59-95*1",0)!=(i<2))return 3;
 puts("96 original C predicate cases; multi-pet deletion eligibility 60/61/nonzero-event/59/wrong-template: PASS");
}
'''
    with tempfile.TemporaryDirectory(prefix='wind-c-') as folder:
        path=Path(folder);(path/'probe.c').write_text(c)
        subprocess.run(['cc','-std=c99','-w',str(path/'probe.c'),'-o',str(path/'probe')],check=True)
        return subprocess.check_output([str(path/'probe')],text=True)
if __name__=='__main__':print(run(),end='')
