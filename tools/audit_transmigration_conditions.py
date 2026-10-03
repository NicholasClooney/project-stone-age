"""Compile the pinned original C condition parser in a minimal character harness.

Only character queries are stubbed. Token splitting, predicate dispatch and OR /
AND iteration are extracted verbatim from the local original files. This is not
an original server build and does not exercise pet deletion/reward delivery.
"""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / 'references/chenmingbiao-stone-age'


def function(text, name):
    match = re.search(r'^(?:BOOL|int|char\s*\*)\s*' + name + r'\([^;]+?\)\s*\{', text, re.M)
    if not match:
        raise ValueError(name)
    start = text.index('{', match.start())
    depth = 1
    end = start + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[match.start():end]


def run():
    spec = json.loads((ROOT/'tools/transmigration_foundation_sources.json').read_text())
    paths = ['gmsv/util.c', 'gmsv/npc/npcutil.c', 'gmsv/npc/npc_exchangeman.c',
             'gmsv/data/npc/sainasu/event/genou_2']
    source = {}
    for path in paths:
        raw = (REFERENCE/path).read_bytes()
        if hashlib.sha256(raw).hexdigest() != spec['sources'][path]:
            raise ValueError('Original source changed: '+path)
        source[path] = raw.decode('gb18030', errors='replace')
    conditions = re.findall(r'^EVENT:(.*)$', source[paths[3]], re.M)[:3]
    c = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define BOOL int
#define TRUE 1
#define FALSE 0
#define IS_2BYTEWORD(x) ((unsigned char)(x)>127)
#define getStringFromIndexWithDelim(a,b,c,d,e) getStringFromIndexWithDelim_body(a,b,c,d,e,__FILE__,__LINE__)
void strcpysafe(char*b,int n,char*s){snprintf(b,n,"%s",s);}
void strncpysafe(char*b,int n,char*s,int z){int k=z<n-1?z:n-1;memcpy(b,s,k);b[k]=0;}
int level=80,petlevel=61,bracelet=0,flags=1;
BOOL NPC_PetLvCheck(int a,int b,char*s,int m){char*q=strchr(s,'>');return q && petlevel>atoi(q+1) && strstr(s,"-95");}
BOOL NPC_EventLevelCheck(int a,int b,int n,int op){return op==2?level>n:level==n;}
BOOL NPC_EventItemCheck(int a,int b,int n,int op){return n==2758 && bracelet;}
BOOL NPC_ENDEventNoCheck(int a,int b,int n,int op){return flags && (n==4||n==42);}
BOOL NPC_NOWEventNoCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_SavePointCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_TiemCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_ImageCheck(int a,int b,int n,int op){return 0;}
BOOL NPC_EventReduce(int a,int b,char*s){return 0;}
'''
    for path, name in [(paths[0],'ScanOneByte'),(paths[0],'getStringFromIndexWithDelim_body'),
                       (paths[1],'NPC_Util_GetStrFromStrWithDelim'),
                       (paths[2],'NPC_EventFreeIfCheck'),(paths[2],'NPC_EventBigSmallCheck'),
                       (paths[2],'NPC_ExChangeManEventCheck')]:
        c += '\n'+function(source[path], name)+'\n'
    c += '\nchar *conditions[]={' + ','.join(json.dumps('EVENT:'+s) for s in conditions) + '};\n'
    c += r'''
int main(void){
 char buf[128];
 getStringFromIndexWithDelim("&ITEM=2758LV>0&PET>59-95&ITEM=2758","&",1,buf,sizeof(buf));
 printf("leading-empty token=[%s] predicate=%d\n",buf,NPC_EventBigSmallCheck(0,0,buf));
 printf("glued predicate=%d\n",NPC_EventBigSmallCheck(0,0,"ITEM=2758LV>0"));
 for(flags=0;flags<=1;flags++) for(bracelet=0;bracelet<=1;bracelet++)
  for(petlevel=42;petlevel<=61;petlevel+=(petlevel==42?1:petlevel==43?17:1)){
   int selected=-1,alternative=-1;
   for(int i=0;i<3;i++){int r=NPC_ExChangeManEventCheck(0,0,conditions[i]);if(r!=-1){selected=i;alternative=r;break;}}
   printf("flags=%d bracelet=%d pet=%d -> branch=%d alternative=%d\n",flags,bracelet,petlevel,selected,alternative);
  }
}
'''
    with tempfile.TemporaryDirectory(prefix='transmigration-c-') as folder:
        path = Path(folder)
        (path/'probe.c').write_text(c)
        subprocess.run(['cc','-std=c99','-w',str(path/'probe.c'),'-o',str(path/'probe')],check=True)
        return subprocess.check_output([str(path/'probe')], text=True)


if __name__ == '__main__':
    print(run(), end='')
