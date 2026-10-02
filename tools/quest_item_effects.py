"""Source-labelled item effects; importing labels never enables their runtime."""
import csv
import hashlib
from functools import lru_cache
from pathlib import Path

MAGIC_SOURCE = 'gmsv/data/magic.txt'
MAGIC_SHA = 'e4e63894a532272fdfda51f2aa4dba0e46d1ab872a551a3dcf667a95711612bd'
STATS = [('attack','攻击',37),('defence','防御',39),('speed','敏捷',41),
         ('hp','体力',43),('mp','气力',45),('luck','运气',47),('charm','魅力',49),('avoid','回避',51)]
RESISTANCES = ['毒','麻痹','睡眠','石化','酒醉','混乱']

@lru_cache(maxsize=4)
def magic_definitions(reference):
    raw=(Path(reference)/MAGIC_SOURCE).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=MAGIC_SHA:
        raise ValueError('Unreviewed original magic metadata source')
    return {int(row[4]):dict(name=row[0],function=row[2],argument=row[3],line=line)
            for line,row in enumerate(csv.reader(raw.decode('gb18030').splitlines()),1)
            if len(row)>4 and row[4].isdigit()}

def annotate_item(item, reference):
    row=item['raw_columns']
    if len(row)<75:raise ValueError('Missing original item effect columns')
    def source(columns):
        return dict(path=item['source'],line=item['source_line'],columns=columns)
    def effect(kind,label,columns,raw,reason):
        return dict(type=kind,label=label,active=False,raw=raw,source=source(columns),reason=reason)
    effects=[]
    if row[55].strip() or int(row[56] or 0) or int(row[57] or 0):
        ident=int(row[55] or -1)
        definition=magic_definitions(str(Path(reference).resolve())).get(ident)
        entry=effect('magic',definition['name'] if definition else f'原魔法编号{ident}',[55,56,57],
                     dict(magicid=row[55],magicprob=row[56],magicusemp=row[57]),'原装备魔法运行时尚未实现')
        if definition:
            entry['definition']=dict(definition,source=MAGIC_SOURCE,sha256=MAGIC_SHA)
        effects.append(entry)
    for index,label in enumerate(RESISTANCES):
        column=63+index*2
        values=row[column:column+2]
        if any(int(value or 0) for value in values):
            effects.append(effect('resistance',label+'耐性',[column,column+1],
                                  dict(min=values[0],max=values[1]),'原六状态抗性运行时尚未实现'))
    if row[10].strip():
        if item.get('use',{}).get('field_supported'):
            entry=effect('use','野外回复体力',[3,10],dict(argument=row[3],function=row[10]),'仅野外使用已实现；战斗道具尚未接入')
            entry['active']=True;entry['scope']='field';effects.append(entry)
        else:
            label='复活至'+row[3] if row[10]=='ITEM_useRessurect' else '原使用作用'
            effects.append(effect('use',label,[3,10],dict(argument=row[3],function=row[10]),'原物品使用作用尚未实现'))
    if max(int(row[35] or 0),int(row[36] or 0))>1:
        effects.append(effect('attack_count','原连续攻击次数',[35,36],dict(min=row[35],max=row[36]),'原武器连续攻击尚未实现'))
    if int(row[19]) in [17,18,19]:
        effects.append(effect('attack_pattern','原投掷武器攻击方式',[19],dict(item_type=row[19]),'原特殊攻击目标规则尚未实现'))
    item['effects']=effects
    # These are source values, not a claim that every modifier is implemented.
    # QuestCatalog resolves each modifier against actual equipment definitions.
    item['stats_source']=[dict(type='stat',stat=stat,label=label,
                              raw=dict(min=row[column],max=row[column+1]),source=source([column,column+1]))
                          for stat,label,column in STATS
                          if int(row[column] or 0) or int(row[column+1] or 0)]
    return item
