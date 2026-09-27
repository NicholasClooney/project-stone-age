import unittest
from build_level_one_spots import eligible_pets

class LevelOneSpotsTest(unittest.TestCase):
    def test_filter_per_enemy_not_area_minimum(self):
        enemies = {str(i): dict(id=i, template_id=i, max_count=1, level_min=lo, level_max=hi, pet_flag=flag)
                   for i, lo, hi, flag in [(1,1,1,1),(2,20,30,1),(3,1,5,1),(4,1,1,0)]}
        templates = {str(i):dict(id=i,sprite=100+i) for i in range(1,5)}
        group = dict(requires_item=-1,excludes_item=-1,enemies=[dict(id=i,weight=1) for i in range(1,5)])
        catalog=dict(enemies=enemies,templates=templates,groups={'1':group})
        area=dict(probability_max=10,groups=[dict(id=1,weight=1)])
        self.assertEqual([e['id'] for e,t in eligible_pets(area,catalog,{101,102,103,104})],[1,3])
        self.assertFalse(eligible_pets(area,catalog,{101,102,104}))
        self.assertFalse(eligible_pets(dict(area,event_now=1),catalog,{101,102,103,104}))
        group['requires_item']=5
        self.assertFalse(eligible_pets(area,catalog,{101,102,103,104}))

if __name__=='__main__':unittest.main()
