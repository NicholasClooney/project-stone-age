"""A source match or successful recolor must never grant semantic approval."""
import copy
import unittest
from review_red_dragon_corpus import approved_rule, require_complete_review, stable_hash, generation_hash


class ReviewGateTest(unittest.TestCase):
    def setUp(self):
        self.source=dict(source_rd_sha256='rd',source_indices_sha256='decoded',
                         geometry=dict(x=-20,y=-30,w=80,h=90),
                         slots=[dict(body=101307,clip='0_0',frame=0,
                                     sprite_frame=dict(image=1,x=0,y=0,sound=0),duration_ms=100)])
        self.rule=dict(self.source,rider_envelopes=[[[2,2],[4,2],[4,4]]])
        self.book=dict(source_palette_sha256='pal',rider_boundary_dilation=1)
        self.receipt=dict(generation_sha256=generation_hash(self.rule,self.book),status='independently-reviewed',source_sha256=stable_hash(self.source),
                          rule_sha256=stable_hash(self.rule),rider_complete=True,
                          dragon_materials_complete=True,occlusion_reviewed=True)

    def test_source_or_mask_change_invalidates_receipt(self):
        self.assertTrue(approved_rule(self.source,self.rule,self.receipt,self.book))
        for field,value in [('source_rd_sha256','changed'),('source_indices_sha256','changed'),
                            ('geometry',dict(x=-19,y=-30,w=80,h=90)),('slots',[])]:
            source=copy.deepcopy(self.source);source[field]=value
            self.assertFalse(approved_rule(source,self.rule,self.receipt,self.book))
        rule=copy.deepcopy(self.rule);rule['rider_envelopes'][0][0][0]=3
        self.assertFalse(approved_rule(self.source,rule,self.receipt,self.book))

    def test_generation_defaults_and_palette_invalidate_review(self):
        for book in (dict(self.book,rider_boundary_dilation=0),
                     dict(self.book,source_palette_sha256='another')):
            self.assertFalse(approved_rule(self.source,self.rule,self.receipt,book))
        receipt=dict(self.receipt);receipt.pop('generation_sha256')
        self.assertFalse(approved_rule(self.source,self.rule,receipt,self.book))
        rule=dict(self.rule,rider_boundary_dilation=2)
        self.assertEqual(generation_hash(rule,self.book),
                         generation_hash(rule,dict(self.book,rider_boundary_dilation=0)))
        for invalid in (-1,True,1.5,None):
            with self.assertRaises(ValueError):
                generation_hash(self.rule,dict(self.book,rider_boundary_dilation=invalid))

    def test_partial_or_draft_inspection_never_passes(self):
        self.assertFalse(approved_rule(self.source,self.rule,{},self.book))
        for field in ('rider_complete','dragon_materials_complete','occlusion_reviewed'):
            receipt=dict(self.receipt);receipt[field]=False
            self.assertFalse(approved_rule(self.source,self.rule,receipt,self.book))
        receipt=dict(self.receipt,status='DRAFT')
        self.assertFalse(approved_rule(self.source,self.rule,receipt,self.book))

    def test_full_coverage_cannot_be_replaced_by_samples(self):
        ledger=dict(records={'1':self.source,'2':self.source},source_palette_sha256='pal')
        rules=dict(self.book,records={'1':self.rule})
        with self.assertRaisesRegex(ValueError,'missing 1'):require_complete_review(ledger,rules,{'1':self.receipt})
        rules['records']['2']=self.rule
        with self.assertRaisesRegex(ValueError,'missing or stale'):require_complete_review(ledger,rules,{'1':self.receipt})
        self.assertEqual(require_complete_review(ledger,rules,{'1':self.receipt,'2':self.receipt}),2)


if __name__=='__main__':unittest.main()
