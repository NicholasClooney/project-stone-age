"""Narrow original prison map restoration; all five exits remain NPC services."""
import hashlib
import json
from pathlib import Path

SPEC = Path(__file__).with_name('prison_world_sources.json')
MAPS = {110,117}

def key(portal):
    return (portal['from_map'], *portal['cell'], portal['to_map'], *portal['target'])

def load_review(reference):
    review = json.loads(SPEC.read_text())
    if set(map(int,review['map_sources'])) != MAPS:
        raise ValueError('Unreviewed prison map set')
    for record in review['map_sources'].values():
        if hashlib.sha256((Path(reference)/record['path']).read_bytes()).hexdigest() != record['sha256']:
            raise ValueError('Prison map SHA changed')
    for path,sha in review['portal_sources'].items():
        if hashlib.sha256((Path(reference)/path).read_bytes()).hexdigest() != sha:
            raise ValueError('Prison portal SHA changed')
    for portal in review['ordinary_portals']:
        text=(Path(reference)/portal['source']).read_bytes().decode('gb18030')
        expected='NONE:NULL:'+','.join(map(str,[portal['from_map'],*portal['cell']]))+':'+','.join(map(str,[portal['to_map'],*portal['target']]))+':NULL'
        if text.splitlines()[portal['source_line']-1] != expected:
            raise ValueError('Prison portal differs from original source')
    return review

def restrict_portals(portals, review):
    """Do not infer permission for other endpoints just because two maps exist."""
    allowed={key(p) for p in review['ordinary_portals']}
    seen=set()
    result=[]
    for portal in portals:
        if MAPS.isdisjoint((portal['from_map'],portal['to_map'])):
            result.append(portal)
        elif key(portal) in allowed and not portal.get('gate_source'):
            result.append(portal)
            seen.add(key(portal))
    if seen != allowed:
        raise ValueError('Missing reviewed original prison entrance')
    return result
