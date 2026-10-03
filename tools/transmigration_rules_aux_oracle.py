"""Verbatim C flags/quest/pet/birth selection oracle; storage-only stubs."""
import hashlib
import itertools
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path


def build(root, source, extract, cc):
    archive=root/'references/anson1788-stoneage/石器时代服务器端最新完整源代码/Serv.zip'
    archive_hash='3d2f809b025259ee5da4cc419245f2c11cf27300b2940f3666b16c4b1c195e50'
    member_hash='311dcd5eadea9933caf92689bec268a06801238f6fba478db790101e4a07d581'
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==archive_hash
    with zipfile.ZipFile(archive) as z:raw=z.read('gmsv/npc/npc_transmigration.c')
    assert hashlib.sha256(raw).hexdigest()==member_hash
    table=re.search(r'static int questTbl\[20\]\s*=\s*\{[^}]+\};',raw.decode('gb18030',errors='replace')).group()
    code=r'''
#include <stdio.h>
#include <stdint.h>
#define BOOL int
#define TRUE 1
#define FALSE 0
#define _PET_TRANS
#define _NEWEVENT
#define CHAR_MAXPETHAVE 5
enum {CHAR_ENDEVENT,CHAR_ENDEVENT2,CHAR_ENDEVENT3,CHAR_ENDEVENT4,CHAR_ENDEVENT5,CHAR_ENDEVENT6,
CHAR_NOWEVENT,CHAR_NOWEVENT2,CHAR_NOWEVENT3,CHAR_NOWEVENT4,CHAR_NOWEVENT5,CHAR_NOWEVENT6,
CHAR_TRANSMIGRATION,CHAR_SAVEPOINT,CHAR_PETID};
static uint32_t actor[15]; static int pets[5],removed[4],nremoved;
int CHAR_getInt(int index,int field){return field==CHAR_PETID?pets[index-1]:(int)actor[field];}
void CHAR_setInt(int index,int field,int value){actor[field]=(uint32_t)value;}
int NPC_EventCheckFlg(int index,int event){return !!(actor[event/32]&(UINT32_C(1)<<(event%32)));}
int NPC_NowEventCheckFlg(int index,int event){return !!(actor[6+event/32]&(UINT32_C(1)<<(event%32)));}
void NPC_EventSetFlg(int index,int event){actor[event/32]|=UINT32_C(1)<<(event%32);}
void s_eventsetend(int index,int event){NPC_EventSetFlg(index,event);}
void NPC_NowEventSetFlg(int index,int event){actor[6+event/32]|=UINT32_C(1)<<(event%32);}
void AddFMAdv(int index,int event){}
int CHAR_getCharPet(int index,int slot){return pets[slot]<0?-1:slot+1;}
int NPC_TransmigrationDelPetDel(int me,int index,int slot){removed[nremoved++]=slot;return 1;}
'''+table
    for name in ['NPC_TransmigrationQuestCheck','NPC_TransmigrationFlg_CLS','NPC_StartpointCheck','NPC_TransmigrationDelPet']:
        code+='\n'+extract(source['npc/npc_transmigration.c'],name)+'\n'
    code+=r'''
int main(void){char mode;int n;
while(scanf(" %c %d",&mode,&n)==2){
 actor[CHAR_TRANSMIGRATION]=n;
 if(mode=='E'){
  for(int j=0;j<12;j++)scanf("%u",&actor[j]);
  printf("%d",NPC_TransmigrationQuestCheck(0));NPC_TransmigrationFlg_CLS(0,0);
  for(int j=0;j<12;j++)printf(" %u",actor[j]);puts("");
 }else if(mode=='P'){
  for(int j=0;j<5;j++)scanf("%d",&pets[j]);nremoved=0;
  int ok=NPC_TransmigrationDelPet(0,0);printf("%d",ok);
  for(int j=0;j<nremoved;j++)printf(" %d",removed[j]);puts("");
 }else {actor[CHAR_SAVEPOINT]=n;printf("%d\n",NPC_StartpointCheck(0,0));}
}}
'''
    events=[]
    for n in range(1,6):
        for words in [[0]*12,[4294967295]*12]:events.append({'new_count':n,'words':words})
    for bit in range(384):
        words=[0]*12;words[bit//32]=1<<(bit%32)
        events.append({'new_count':1+bit%5,'words':words})
    pets=[]
    for n in range(1,6):
        for row in itertools.product([-1,693,694,695,696],repeat=5):
            pets.append({'new_count':n,'templates':list(row)})
    commands=['E '+str(v['new_count'])+' '+' '.join(map(str,v['words'])) for v in events]
    commands+=['P '+str(v['new_count'])+' '+' '.join(map(str,v['templates'])) for v in pets]
    commands+=['V '+str(bits) for bits in range(32)]
    outputs=[]
    with tempfile.TemporaryDirectory(prefix='transmigration-aux-c-') as folder:
        path=Path(folder);(path/'oracle.c').write_text(code)
        for optimization in ['-O0','-O2']:
            subprocess.run([cc,'-std=c99',optimization,str(path/'oracle.c'),'-o',str(path/'oracle')],check=True)
            outputs.append(subprocess.check_output([str(path/'oracle')],input='\n'.join(commands)+'\n',text=True))
    assert outputs[0]==outputs[1]
    rows=iter(outputs[0].splitlines())
    for v in events:
        row=list(map(int,next(rows).split()));v['quests']=row[0];v['after']=row[1:]
    # Retain every distinct slot/result shape, covering exhaustive 5-slot domain.
    representatives={}
    for v in pets:
        row=list(map(int,next(rows).split()));v['ok']=bool(row[0]);v['indices']=row[1:]
        representatives.setdefault((v['new_count'],v['ok'],tuple(v['indices'])),v)
    villages=[]
    for line in source['data/npc/777/ten.arg'].splitlines()[:4]:
        match=re.search(r'Present=([\d.]+),Warp=([\d.]+)',line)
        villages.append(([int(v) for v in match[1].split('.')],[int(v) for v in match[2].split('.')]))
    enemies={}
    for line in source['data/enemy.txt'].splitlines():
        fields=line.split(',')
        if len(fields)>4 and fields[3] in ['1377','1378','1379','1380','1381']:enemies[int(fields[3])]=int(fields[4])
    rewards=[]
    for bits in range(32):
        village=int(next(rows))
        for n in range(1,6):
            v={'bits':bits,'new_count':n,'village':village}
            if village>=0:
                presents,location=villages[village];enemy=presents[n-1]
                v.update(enemy_id=enemy,template_id=enemies[enemy],location=location)
            rewards.append(v)
    return {'anson_archive_sha256':archive_hash,'anson_member_sha256':member_hash,'events':events,
            'sacrifices':list(representatives.values()),'sacrifices_exhaustive_count':len(pets),'rewards':rewards}
