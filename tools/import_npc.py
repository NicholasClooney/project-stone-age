"""Import the first outdoor Samgir resident from local legacy NPC definitions.

Run after import_legacy.py. Source files are decoded strictly as GB18030;
raw definitions and generated original content remain local and gitignored.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from import_legacy import Archive

REVISION = '0c58fb6683a49a178a8ad845a8c296c2cb83bd81'
SOURCE = 'https://github.com/chenmingbiao/stone-age/blob/' + REVISION + '/gmsv/data/npc/'


def run(client, npc_source, output):
    source, output = Path(npc_source), Path(output)
    create = (source / 'poru/samugiru01.create').read_bytes()
    dialogue = (source / 'poru/samugiru02').read_bytes()
    block = re.search(r'\{([^}]+)\}', create.decode('gb18030')).group(1)
    fields = dict(line.strip().split('=', 1) for line in block.splitlines() if '=' in line)
    if fields['floorid'] != '1000' or fields['enemy'] != 'npcgen_man|file:poru/samugiru02':
        raise ValueError('Expected the first outdoor Samgir resident')
    x, y, width, height = map(int, fields['borncenter'].split(','))
    if (width, height) != (1, 1):
        raise ValueError('Expected a fixed NPC position')
    graphic = int(fields['graphicname'])
    archive = Archive(client)
    output.mkdir(parents=True, exist_ok=True)
    archive.image(graphic).save(output / 'samgir-villager.png')
    metadata = archive.entries[graphic]
    result = dict(name=fields['name'], cell=[x, y], graphic=graphic,
                  facing=int(fields['dir']), offset=[metadata['x'], metadata['y']],
                  text=dialogue.decode('gb18030').strip().split(',')[0],
                  sources=[dict(url=SOURCE + path, sha256=hashlib.sha256(raw).hexdigest())
                           for path, raw in [('poru/samugiru01.create', create), ('poru/samugiru02', dialogue)]])
    (output / 'samgir-npc.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"Imported {result['name']} at ({x}, {y}), graphic {graphic}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('client')
    parser.add_argument('npc_source', help='Local directory containing poru/*.create and dialogue files')
    parser.add_argument('--output', default='client/assets/legacy')
    args = parser.parse_args()
    run(args.client, args.npc_source, args.output)
