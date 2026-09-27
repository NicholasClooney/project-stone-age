"""Import native rider+pet composites proven by the server's ridePetTable."""
import argparse
import json
import re
import shutil
from pathlib import Path
from import_legacy import Archive
from import_battle import animations

PETS = {100330:'golden_tiger',100352:'blue_brontosaurus'}

def mappings(source):
    text = Path(source).read_bytes().decode('latin1')
    result = {}
    for ride, rider, pet, enemy in re.findall(r'^\s*\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\}',text,re.M):
        if int(pet) in PETS and 100000 <= int(rider) < 100240:
            result[f'{rider}:{pet}'] = dict(sprite=int(ride),rider=int(rider),pet=int(pet),source_enemy_id=int(enemy))
    return result

def run(source, table, output):
    archive = Archive(source)
    output = Path(output)
    (output/'images').mkdir(parents=True,exist_ok=True)
    pairs = mappings(table)
    characters = {}
    unavailable = []
    for key, pair in list(pairs.items()):
        try: data = animations(archive,pair['sprite'])
        except ValueError:
            unavailable.append(pair);del pairs[key];continue
        if not all(f'{action}_{direction}' in data and data[f'{action}_{direction}']['frames'] for action in [3,4] for direction in range(8)):
            unavailable.append(pair);del pairs[key];continue
        characters[str(pair['sprite'])] = data
    used = {f['image'] for c in characters.values() for a in c.values() for f in a['frames']}
    decoded = {}
    invalid = set()
    for ident in sorted(used):
        try: decoded[ident] = archive.image(ident)
        except (ValueError,KeyError,IndexError): invalid.add(ident)
    for key,pair in list(pairs.items()):
        actions = characters[str(pair['sprite'])]
        if any(f['image'] in invalid for a in actions.values() for f in a['frames']):
            unavailable.append(dict(pair,reason='invalid bitmap in original pack'))
            del pairs[key]
            del characters[str(pair['sprite'])]
    used = {f['image'] for c in characters.values() for a in c.values() for f in a['frames']}
    images = {}
    for ident in sorted(used):
        decoded[ident].save(output/'images'/f'{ident}.png')
        images[str(ident)] = {k:archive.entries[ident][k] for k in ['x','y','w','h']}
    manifest = dict(pairs=pairs,characters=characters,images=images,unavailable=unavailable,
                    source='gmsv/char/char_base.c:50 ridePetTable, char.c:3065 exact rider+pet lookup',
                    names={str(k):v for k,v in PETS.items()})
    add_audio(archive.data,output,manifest)
    (output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',',':')))
    print(f'Imported {len(pairs)} verified native riding pairs, {len(used)} images; {len(unavailable)} unavailable pairs excluded')
def add_audio(data, output, manifest):
    (output/'audio').mkdir(parents=True,exist_ok=True)
    sounds = {62:'sae_12.wav',63:'sae_13.wav',254:'sad_05.wav'}
    for name in sounds.values(): shutil.copyfile(data/'se'/name,output/'audio'/name)
    manifest['frame_sounds'] = {str(k):'audio/'+v for k,v in sounds.items()}

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source');p.add_argument('--table',default='references/chenmingbiao-stone-age/gmsv/char/char_base.c');p.add_argument('--output',default='client/assets/legacy/riding');a=p.parse_args();run(a.source,a.table,a.output)
