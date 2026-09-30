"""Extract classic UI art and palette-derived automap colors from local resources."""
import argparse
import json
import shutil
from pathlib import Path
from import_legacy import Archive

# Logical graphic numbers, resolved through ADRN.attr.bmpnumber (offset 76).
IDS = [26012,26042,26081,26236,26260,26101,26102,26103,26104,26105,26106,
       26234,26235,26237,26238,26111,26112,26113,26114,26248,26249,
       26115,26116,26119,26120,26091,25610] + list(range(26001,26010)) + list(range(26150,26164))

def run(source, output):
    archive = Archive(source)
    output = Path(output)
    folder = output / 'ui'
    folder.mkdir(parents=True, exist_ok=True)
    # UI uses full logical IDs; map tile storage alone is 16-bit.
    logical = {e['map_id']: e['id'] for e in archive.entries.values() if e['map_id']}
    metadata = {}
    for number in IDS:
        ident = logical[number]
        archive.image(ident).save(folder / f'{number}.png')
        metadata[str(number)] = dict(bitmap=ident, width=archive.entries[ident]['w'], height=archive.entries[ident]['h'])
    world = json.loads((output / 'samgir.json').read_text())
    colors = {}
    # Original getAutoMapColor averages non-transparent pixels then finds nearest SAP entry.
    for entry in world['ground'] + world['objects']:
        ident = int(entry[2])
        if str(ident) in colors:
            continue
        pixels = [pixel[:3] for pixel in archive.image(ident).getdata() if pixel[3]]
        mean = [sum(p[channel] for p in pixels)//len(pixels) for channel in range(3)] if pixels else [0,0,0]
        palette_index = min([0]+list(range(16,240)), key=lambda i: sum((archive.palette[i][c]-mean[c])**2 for c in range(3)))
        colors[str(ident)] = list(archive.palette[palette_index])
    (folder / 'manifest.json').write_text(json.dumps(dict(images=metadata, map_colors=colors), indent=2)+'\n')
    for name in ('sas_02.wav','sas_03.wav'):
        shutil.copyfile(Path(source)/'data/se'/name,output/name)
    print(f'Imported {len(metadata)} original UI images and {len(colors)} automap colors')

if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('source')
    parser.add_argument('--output',default='client/assets/legacy')
    args=parser.parse_args()
    run(args.source,args.output)
