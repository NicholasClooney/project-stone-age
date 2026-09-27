"""Extract original skill shop26139 and Samgir trainer16047, without reimportingworld."""
import argparse,json
from pathlib import Path
from import_legacy import Archive

def run(source, output):
    root=Path(output);archive=Archive(source)
    logical={e['map_id']:e['id'] for e in archive.entries.values() if e['map_id']}
    for graphic,folder in [(26139,'mvp/ui'),(16047,'world/npcs')]:
        target=root/folder;target.mkdir(parents=True,exist_ok=True)
        bitmap=logical[graphic];archive.image(bitmap).save(target/f'{graphic}.png')
    bitmap=logical[16047];entry=archive.entries[bitmap]
    manifest=root/'world/manifest.json';data=json.loads(manifest.read_text())
    data['residents']=[n for n in data['residents'] if not(n['map_id']==1003 and n['cell']==[18,13])]
    data['residents'].append(dict(map_id=1003,cell=[18,13],name='超级饲育员',role='trainer',graphic=16047,path='world/npcs/16047.png',offset=[entry['x'],entry['y']],facing=4,text='这个村里的超级饲育员\n好了！要教它什么好呢？',source='gmsv/data/npc/genout/shop_m.create:78',dialogue_source='gmsv/data/npc/genout/psks_1003_18_13'))
    manifest.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')))
    print('Imported original skill shop26139 and trainer16047 at1003(18,13)')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source');p.add_argument('--output',default='client/assets/legacy');a=p.parse_args();run(a.source,a.output)
