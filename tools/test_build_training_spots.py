import unittest
from build_training_spots import effective_area, landing, ordinary_enemies

class TrainingSpotsTest(unittest.TestCase):
    def test_priority_and_solid_landing(self):
        base={'id':1,'rect':[0,0,2,2],'priority':1}
        overlay={'id':2,'rect':[1,1,1,1],'priority':2}
        data={'width':3,'height':3,'blocked':[False]*9,'ground':[[x,y,1] for y in range(3) for x in range(3)]}
        point=landing(base,[base,overlay],data,{(0,0)})
        self.assertNotEqual(point,[1,1])
        self.assertNotEqual(point,[0,0])
        self.assertEqual(effective_area([base,overlay],*point)['id'],1)
        self.assertEqual(effective_area([base,dict(overlay,priority=1)],1,1)['id'],1)
        self.assertIsNone(landing(base,[base],dict(data,blocked=[True]*9),set()))

    def test_landing_skips_void(self):
        # Unblocked cells with no ground picture are the black void outside walls.
        area={'id':1,'rect':[0,0,2,2],'priority':1}
        data={'width':3,'height':3,'blocked':[False]*9,'ground':[[2,2,7]]}
        self.assertEqual(landing(area,[area],data,set()),[2,2])
        self.assertIsNone(landing(area,[area],dict(data,ground=[]),set()))

    def test_gate_art_and_weight_filter(self):
        enemy={'template_id':1,'max_count':1,'level_min':1,'level_max':2}
        group={'requires_item':-1,'excludes_item':-1,'enemies':[{'id':1,'weight':1}]}
        c={'groups':{'1':group},'enemies':{'1':enemy},'templates':{'1':{'sprite':123}}}
        area={'probability_max':5,'groups':[{'id':1,'weight':1}]}
        self.assertEqual(len(ordinary_enemies(area,c,{123})),1)
        self.assertFalse(ordinary_enemies(area,c,set()))
        self.assertFalse(ordinary_enemies(dict(area,event_now=1),c,{123}))
        group['requires_item']=99
        self.assertFalse(ordinary_enemies(area,c,{123}))
        group['requires_item']=-1;group['invalid_weights']=True
        self.assertFalse(ordinary_enemies(area,c,{123}))

if __name__=='__main__':unittest.main()
