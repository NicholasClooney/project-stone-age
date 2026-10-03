"""The single source-bound Banam jug shop; not a general item-shop importer."""
import csv
import hashlib
import re

SCRIPT='genout/ss_30504_10_11'
CREATE='gmsv/data/npc/genout/shop_m3.create'
TEMPLATE='gmsv/data/npc/genout/npcgen.template'
IDENT=SCRIPT+'@30504:10:11'
SOURCES={
 CREATE:'3afe6385430b772455f78e6bc7933e9591fde6e2f0f149a2c0cd85924643501a',
 'gmsv/data/npc/'+SCRIPT:'c58937e9590b5106529b300432ce8a166ef13b7c19b31cbbc7cd52968a1a8684',
 TEMPLATE:'0c5a58d5e31cafd3b58ccc1fa88fee7d1f95d12c0b87b04db9f06fea3b2a4df3',
 'gmsv/data/itemset.txt':'c997393a4806f01833de102939830fc0000bb2a9d445eb214b8501c2b28c4f5d',
 'gmsv/npc/npc_itemshop.c':'ce1bf934f19fba940ed97e0111bc859b38f821fc14f7a1c95e0bae73ed71d4d5'}
PURCHASE={'item_id':2708,'quantity':1,'price':1150,'base_cost':500,'buy_rate':'2.3'}

def parse(spec,texts,script,create,ordinal,fields,review):
    if (spec['id']!='transmigration-fire' or script!=SCRIPT or create!=CREATE or ordinal!=41
        or review!={'kind':'original_jug_shop','events':[40]} or 2708 not in spec['items']):
        raise ValueError('Unreviewed original jug shop identity')
    for path,sha in SOURCES.items():
        if spec['sources'].get(path)!=sha or hashlib.sha256(texts.get(path,'').encode('gb18030')).hexdigest()!=sha:
            raise ValueError('Unreviewed original jug shop source: '+path)
    expected={'floorid':'30504','borncorner':'10,11,10,11','createnum':'1','graphicname':'16201','dir':'4','enemy':'npcgen_shop|file:'+SCRIPT,'name':'巴那姆湖的看守者'}
    if any(fields.get(k)!=v for k,v in expected.items()):raise ValueError('Changed jug shop create')
    templates=[dict(line.strip().split('=',1) for line in block.splitlines() if '=' in line and not line.lstrip().startswith('#')) for block in re.findall(r'\{([^}]+)\}',texts[TEMPLATE])]
    matches=[t for t in templates if t.get('templatename')=='npcgen_shop']
    if len(matches)!=1 or matches[0].get('functionset')!='ItemShop':raise ValueError('Changed shop template')
    shop=dict(line.split(':',1) for line in texts['gmsv/data/npc/'+SCRIPT].splitlines() if ':' in line and not line.startswith('#'))
    row=next(r for r in csv.reader(texts['gmsv/data/itemset.txt'].splitlines()) if len(r)>26 and r[16]=='2708')
    if shop.get('buy_rate')!='2.3' or shop.get('ItemList')!='2708' or row[18]!='500':raise ValueError('Changed jug purchase')
    return {'kind':'original_jug_shop','handler':'ItemShop','purchase':PURCHASE.copy()}

def is_reviewed_npc(npc,module_id):
    return (module_id=='transmigration-fire' and npc.get('kind')=='original_jug_shop'
            and npc.get('id')==IDENT and npc.get('source_script')==SCRIPT
            and npc.get('source_create')==CREATE and npc.get('source_create_index')==41
            and npc.get('map_id')==30504 and npc.get('cell')==[10,11]
            and npc.get('graphic')==16201 and npc.get('facing')==4
            and npc.get('handler')=='ItemShop' and npc.get('events')==[40]
            and npc.get('branches')==[] and npc.get('purchase')==PURCHASE)
