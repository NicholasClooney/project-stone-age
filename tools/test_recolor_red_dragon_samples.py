"""Verify fail-closed source binding and preservation contracts, not art truth."""
import copy
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import numpy as np
from recolor_red_dragon_samples import recolor, raster, validate_source
from audit_red_dragon_recolor import digest


def rule():
    return {'geometry':dict(x=0,y=0,w=12,h=12),
            'rider_envelopes':[[[3,3],[6,3],[6,6],[3,6]]],
            'uncertain_polygons':[[[6,6],[8,6],[8,8],[6,8]]],
            'dragon_envelopes':[[[0,0],[11,0],[11,11],[0,11]]],
            'ventral_polygons':[[[0,0],[11,0],[11,11],[0,11]]],
            'underwing_preserve_polygons':[[[0,9],[2,9],[2,11],[0,11]]]}


class SpatialContractTest(unittest.TestCase):
    def test_dorsal_highlight_requires_explicit_region_and_keeps_protection(self):
        p=np.full((12,12),211,np.uint8);p[0,0]=210
        r=rule();r['ventral_polygons']=[[[9,0],[11,0],[11,2],[9,2]]]
        self.assertTrue(np.array_equal(recolor(p,r,1)[0],p))
        r['dorsal_highlight_polygons']=[[[0,0],[9,0],[9,11],[0,11]]]
        out,(rider,unknown,dragon,ventral,wing)=recolor(p,r,1)
        self.assertEqual(out[0,0],222);self.assertEqual(out[0,2],223)
        self.assertTrue(np.array_equal(out[rider|unknown|ventral|wing],p[rider|unknown|ventral|wing]))
        self.assertTrue(np.array_equal(out[:,10:],p[:,10:]))
        r['dragon_envelopes']=[]
        self.assertTrue(np.array_equal(recolor(p,r,1)[0],p))

    def test_protected_and_unknown_override_material(self):
        p=np.full((12,12),213,np.uint8);p[0,0]=0;p[0,1]=168;p[10,10]=159
        out,(rider,unknown,dragon,ventral,wing)=recolor(p,rule(),1)
        self.assertTrue(np.array_equal(out[rider|unknown|wing],p[rider|unknown|wing]))
        self.assertEqual(out[10,10],212)
        self.assertEqual(out[0,0],0);self.assertEqual(out[0,1],168)
        self.assertFalse(dragon[0,0]);self.assertFalse(dragon[0,1])
        self.assertTrue(unknown[6,6]);self.assertFalse(rider[6,6])
        self.assertTrue(np.any(out!=p))

    def test_invalid_polygon_refuses_clipping(self):
        with self.assertRaises(ValueError):raster((12,12),[[[0,0],[12,0],[0,11]]])

    def test_wrong_source_bytes_refused(self):
        r=rule();r.update(source_rd_sha256='reviewed',source_indices_sha256='wrong')
        with patch('recolor_red_dragon_samples.indices',return_value=(np.zeros((12,12),np.uint8),'new bytes')):
            with self.assertRaisesRegex(ValueError,'hash mismatch'):validate_source(None,1,r)

    def test_geometry_and_timing_refused(self):
        p=np.zeros((12,12),np.uint8);r=rule();r.update(source_rd_sha256='ok',source_indices_sha256=digest(p.tobytes()),
            slots=[dict(body=1,clip='3_2',frame=0,sprite_frame=dict(image=1,x=0,y=0,sound=0),duration_ms=100)])
        fake=SimpleNamespace(entries={1:dict(x=1,y=0,w=12,h=12)})
        with patch('recolor_red_dragon_samples.indices',return_value=(p,'ok')):
            with self.assertRaisesRegex(ValueError,'geometry mismatch'):validate_source(fake,1,r)
            fake.entries[1]['x']=0
            with patch('recolor_red_dragon_samples.sprite_animations',return_value={'3_2':dict(frames=[r['slots'][0]['sprite_frame']],duration_ms=101)}):
                with self.assertRaisesRegex(ValueError,'SPR slot mismatch'):validate_source(fake,1,r)

    def test_source_array_never_mutated(self):
        p=np.full((12,12),213,np.uint8);before=p.copy();r=rule();saved=copy.deepcopy(r)
        first=recolor(p,r,2)[0];second=recolor(p,r,2)[0]
        self.assertTrue(np.array_equal(first,second));self.assertTrue(np.array_equal(p,before));self.assertEqual(r,saved)


if __name__=='__main__':unittest.main()
