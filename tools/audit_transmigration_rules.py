"""Build pinned ORIGINAL C functions, never derive expectations from GDScript.

Only character storage/notifications are stubbed. Source functions remain verbatim;
_TRANS_6 is intentionally not defined (the supported profile is human turns 1–5).
Requires cc; writes no imported assets, saves, or live state. --write replaces only
client/tests/fixtures/transmigration-rules.json. Default checks that fixture.
"""
import argparse
import hashlib
import json
from pathlib import Path
import random
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / 'tools/transmigration_rules_sources.json'
FIXTURE = ROOT / 'client/tests/fixtures/transmigration-rules.json'


def function(text, name):
    match = re.search(r'^(?:BOOL|int|float)\s+' + re.escape(name) + r'\([^;]+?\)\s*\{', text, re.M)
    if not match:
        raise ValueError('missing function ' + name)
    start = text.index('{', match.start())
    depth, end = 1, start + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[match.start():end]


def sources():
    spec = json.loads(SPEC.read_text())
    result = {}
    for path, expected in spec['sources'].items():
        raw = (ROOT / 'references/chenmingbiao-stone-age/gmsv' / path).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError('Original source changed: ' + path)
        result[path] = raw.decode('gb18030', errors='replace')
    return spec, result


def harness(source):
    c = r'''
#include <stdio.h>
#include <math.h>
#include <float.h>
#include <limits.h>
#define BOOL int
#define TRUE 1
#define FALSE 0
enum {CHAR_VITAL,CHAR_STR,CHAR_TOUGH,CHAR_DEX,CHAR_LV,CHAR_TRANSEQUATION,
      CHAR_TRANSMIGRATION,CHAR_SKILLUPPOINT};
static int actor[8], completed;
int CHAR_getInt(int index,int field){return actor[field];}
void CHAR_setInt(int index,int field,int value){actor[field]=value;}
void CHAR_Skillupsend(int index){}
int NPC_TransmigrationQuestCheck(int index){return completed;}
'''
    for name in ['NPC_TransCalculation', 'Rounding', 'NPC_TransmigrationStatus']:
        c += '\n' + function(source['npc/npc_transmigration.c'], name) + '\n'
    c += r'''
int main(void){
 if(sizeof(float)!=4 || FLT_RADIX!=2 || FLT_MANT_DIG!=24 || FLT_EVAL_METHOD!=0
    || sizeof(int)!=4 || INT_MAX!=2147483647) return 2;
 int work[10];
 while(scanf("%d %d %d %d %d %d %d %d %d", &actor[0],&actor[1],&actor[2],&actor[3],
             &actor[4],&actor[5],&actor[6],&completed,&actor[7])==9){
  int total=actor[0]+actor[1]+actor[2]+actor[3];
  NPC_TransmigrationStatus(0,0,work);
  /* Main:733 overwrites Status's temporary old unspent-point division. */
  actor[7]=actor[6]*10;
  printf("%d %d %d %d %d %d %d\n",actor[0],actor[1],actor[2],actor[3],actor[5],actor[7],
         NPC_TransCalculation(0,total));
 }
}
'''
    return c


def cases():
    result = []
    distributions = [[900,700,0,400], [1,0,0,0], [299,301,199,401],
                     [100000000,1,0,0], [16777217,16777219,1,0]]
    for n in range(1,6):
        for level in [80,85,120,130,131]:
            for q in [0,20]:
                result.append({'base': distributions[(n+level+q)%len(distributions)],
                               'equation': ((n-1)*20<<16)+(n-1)*130,
                               'level':level,'new_count':n,'quests':q,'old_unspent':19})
    # Negative answers are legal intermediate results; clamp components, not ans.
    result.append({'base':[1,0,0,0],'equation':4*80,'level':80,'new_count':5,'quests':0,'old_unspent':0})
    return result


def build(cc='cc'):
    spec, source = sources()
    vectors = cases()
    stdin = ''.join(' '.join(map(str,v['base']+[v['level'],v['equation'],v['new_count'],v['quests'],v['old_unspent']]))+'\n' for v in vectors)
    outputs = []
    flags = ['-std=c99','-fno-fast-math','-ffp-contract=off']
    with tempfile.TemporaryDirectory(prefix='transmigration-rules-c-') as folder:
        folder = Path(folder)
        cfile = folder/'oracle.c'
        cfile.write_text(harness(source))
        for optimization in ['-O0','-O2']:
            binary = folder/('oracle'+optimization)
            subprocess.run([cc,*flags,optimization,str(cfile),'-lm','-o',str(binary)],check=True)
            outputs.append(subprocess.check_output([str(binary)],input=stdin,text=True))
        if outputs[0] != outputs[1]:
            raise ValueError('C oracle differs between O0 and O2')
        compiler = subprocess.check_output([cc,'--version'],text=True).splitlines()[0]
    rows = outputs[0].splitlines()
    if len(rows) != len(vectors):
        raise ValueError('Incomplete C output')
    for vector,line in zip(vectors,rows):
        numbers = [int(x) for x in line.split()]
        vector['expected']={'base':numbers[:4],'equation':numbers[4],'stat_points':numbers[5],'ans':numbers[6]}
    return {'sources':spec['sources'],'oracle':{'functions':['NPC_TransCalculation','Rounding','NPC_TransmigrationStatus'],
            'profile':'human-1-5','flags':flags,'optimization_equivalence':['-O0','-O2']},'inheritance':vectors},compiler


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write',action='store_true')
    parser.add_argument('--cc',default='cc')
    args=parser.parse_args()
    data,compiler=build(args.cc)
    encoded=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
    if args.write:
        FIXTURE.write_text(encoded)
    elif FIXTURE.read_text()!=encoded:
        raise SystemExit('C oracle fixture changed; inspect sources and run --write explicitly')
    print(f"Original C oracle: {len(data['inheritance'])} vectors, O0/O2 agree; {compiler}")

if __name__=='__main__':
    main()
