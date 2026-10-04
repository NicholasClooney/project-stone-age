"""Read-only 4b source/portal audit. Never imports or writes original assets."""
import hashlib
import json
import re
import time
from collections import deque
from pathlib import Path

from map_file import load_map

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / 'client/server/quest_auto_golden_bui_sources.json'
SHA = 'e5ccf199c0e3a06756370ee1ce40efe6501bdcf6f40501379a9960e9a07a00d8'


def check():
    raw = TABLE.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == SHA, 'Changed reviewed table'
    assert f'const DATA_SHA:="{SHA}"' in TABLE.with_suffix('.gd').read_text()
    data = json.loads(raw)
    reference = ROOT / 'references/chenmingbiao-stone-age'
    texts = {}
    for name, digest in data['sources'].items():
        source = (reference / name).read_bytes()
        assert hashlib.sha256(source).hexdigest() == digest, name
        texts[name] = source.decode('gb18030', errors='replace')
    catalog = json.loads((ROOT / 'client/assets/legacy/quests/catalog.json').read_text())
    world = json.loads((ROOT / 'client/assets/legacy/world/manifest.json').read_text())
    assert len(data['npcs']) == 39
    assert len({n['id'] for n in data['npcs']}) == 39
    services = [n for n in data['npcs'] if 'service_id' in n]
    assert [sum(n['kind'] == kind for n in services) for kind in
            ('golden_bui_quiz', 'golden_bui_janken', 'golden_bui_gate')] == [21, 9, 5]
    for expected in data['npcs']:
        found = [n for n in catalog['npcs'] if n['id'] == expected['id']]
        assert len(found) == 1
        assert {k: found[0][k] for k in expected} == expected, expected['id']
        assert 'gmsv/data/npc/' + expected['source_script'] in data['sources']
        for branch in expected['branches']:
            claim = expected['source_script'] == 'quiz/equiz_01'
            assert branch['source_branch_index'] == (3 if claim else 4)
            assert branch['actions'] == ({'GetItem': '2753'} if claim else
                                        {'GetPet': '14', 'DelItem': '2753', 'EndSetFlg': '44'})
            assert branch['event'] == 44
    assert data['reward_pet'] == catalog['reward_pets']['14']
    lines = texts['gmsv/data/map/mapwarp.txt'].splitlines()
    creates = texts['gmsv/data/npc/genout/quiz.create'].splitlines()
    assert len(data['portals']) == 30
    assert {p['from_map'] for p in data['portals']} == set(range(800, 810)) | set(range(820, 830)) | set(range(840, 850))
    real_edges = 0
    for p in data['portals']:
        source = [p['from_map'], *p['from_cell']]
        target = [p['to_map'], *p['to_cell']]
        assert lines[p['mapwarp_line']-1] == 'NONE:NULL:%s:%s:NULL' % (','.join(map(str, source)), ','.join(map(str, target)))
        forward = []
        for index, line in enumerate(lines, 1):
            match = re.fullmatch(r'NONE:NULL:(\d+),(\d+),(\d+):(\d+),(\d+),(\d+):NULL', line.strip())
            if match:
                values = list(map(int, match.groups()))
                if values[0] == p['from_map'] and values[3] == p['to_map']:
                    forward.append(index)
        assert len(forward) == 2 and forward[0] == p['mapwarp_line']
        real_edges += len(forward)
        block = '\n'.join(creates[p['create_line']-1:p['create_line']+7])
        assert 'floorid=%d\n' % source[0] in block
        assert 'borncorner=%d,%d,%d,%d\n' % (*source[1:], *source[1:]) in block
        assert 'enemy=npcgen_warp|%d|%d|%d\n' % tuple(target) in block
        links = [l for l in world['portals'] if l['from_map'] == source[0] and l['cell'] == source[1:]]
        assert links == [p['live_link']], source
        assert p['live_link']['source'] == 'quiz.create:%d' % p['create_line']
        grid = load_map(ROOT / 'client/assets/legacy' / world['maps'][str(source[0])]['path'])
        portals = {tuple(l['cell']) for l in world['portals'] if l['from_map'] == source[0]}
        actors = {tuple(n['cell']) for n in world['residents'] + catalog['npcs'] if n['map_id'] == source[0]}
        goal = tuple(source[1:])
        portals.discard(goal)

        def distance(origin):
            queue = deque([(origin, 0)])
            seen = {origin}
            while queue:
                (x, y), steps = queue.popleft()
                if (x, y) == goal:
                    return steps
                for q in ((x-1,y), (x+1,y), (x,y-1), (x,y+1)):
                    if q in seen or q in portals or q in actors:
                        continue
                    if not (0 <= q[0] < grid['width'] and 0 <= q[1] < grid['height']):
                        continue
                    if grid['blocked'][q[1]*grid['width']+q[0]]:
                        continue
                    seen.add(q)
                    queue.append((q, steps+1))
            return None

        assert distance((source[1], 15)) == 2, source
        assert distance((source[1], 21)) is None, source
    assert real_edges == 60
    print('4b static: %d pinned sources; 39 NPC identities; 30 selected / 60 original edges; 30 two-cell paths and walls' % len(data['sources']))


if __name__ == '__main__':
    started = time.monotonic()
    check()
    print('elapsed %.3fs (Python only; no Godot/runtime authority verification)' % (time.monotonic()-started))
