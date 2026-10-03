"""Exact source prison endpoints and unchanged unrelated world inputs."""
import copy
import json
import unittest
from pathlib import Path
from prison_world import load_review, restrict_portals, key
from transmigration_foundation import portals
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'references/chenmingbiao-stone-age'

class PrisonWorld(unittest.TestCase):
    def setUp(self):
        self.review=load_review(REF)

    def test_exact_two_maps_and_eighteen_source_endpoints(self):
        self.assertEqual(self.review['map_sources'], {
            '117':{'path':'gmsv/data/map/extra/117','sha256':'672b928fda056c63da4772a7686ca73fe39509cf70d5e7d34cade1bf98f9dd59'},
            '110':{'path':'gmsv/data/map/extra/110','sha256':'579c5500bcad3bc86cad940596602b3c7d4fe53c588b8f9b261ea7be325e629d'}})
        expected={(32020,x,y,117,225,13) for x,y in [(20,8),(19,7),(20,7),(21,7),(19,6),(20,6),(21,6)]}
        expected|={(32020,x,5,117,180,99) for x in [19,20,21]}
        expected|={(21214,30,y,117,180,99) for y in range(33,40)}|{(21014,15,4,117,180,99)}
        self.assertEqual({key(p) for p in self.review['ordinary_portals']},expected)
        self.assertEqual(len(self.review['ordinary_portals']),18)
        raw=portals(REF,[self.review])
        self.assertEqual({key(p) for p in restrict_portals(raw,self.review)},expected)
        self.assertEqual(set(self.review['restored_scripts']), {'genout/wpm_117_6_5'}|{'genout/wpm_110_37_'+str(y) for y in [20,24,28,32]})

    def test_no_extra_prison_entrance_or_service_bypass(self):
        raw=portals(REF,[self.review])
        unrelated=[dict(from_map=777,cell=[1,2],to_map=778,target=[3,4],source='unrelated',custom={'original':True})]
        extra=[dict(from_map=117,cell=[6,5],to_map=110,target=[23,27],gate_source='genout/wpm_117_6_5')]
        extra += [dict(from_map=110,cell=[37,y],to_map=m,target=[13,13],gate_source='genout/wpm_110_37_'+str(y)) for y,m in zip([20,24,28,32],[1012,2012,3012,4012])]
        before=copy.deepcopy(raw+unrelated+extra)
        result=restrict_portals(raw+unrelated+extra,self.review)
        self.assertEqual([p for p in result if p['from_map']==777],unrelated)
        self.assertEqual(raw+unrelated+extra,before)
        self.assertFalse(any(p['from_map'] in [110,117,5510,5576,30691,30692,30693,30694,30619,30620] for p in result))
        self.assertFalse(any(p.get('gate_source') for p in result))
        with self.assertRaisesRegex(ValueError,'Missing reviewed'):
            restrict_portals([p for p in raw if key(p)!=(21014,15,4,117,180,99)],self.review)

if __name__=='__main__':unittest.main()
