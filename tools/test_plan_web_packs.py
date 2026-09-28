import unittest
from pathlib import Path

import plan_web_packs

LEGACY = plan_web_packs.LEGACY


@unittest.skipUnless((LEGACY / "world/manifest.json").exists(), "imported original assets required")
class PlanWebPacksTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.plan = plan_web_packs.plan()

    def test_every_asset_lands_in_exactly_one_pack(self):
        seen = {}
        for name, paths in self.plan["packs"].items():
            for path in paths:
                self.assertNotIn(path, seen, f"{path} in {seen.get(path)} and {name}")
                seen[path] = name
        on_disk = {plan_web_packs.res(p) for p in LEGACY.rglob("*") if p.is_file() and p.suffix != ".import" and p.name != ".DS_Store"}
        self.assertEqual(on_disk, set(seen))

    def test_lookups_name_real_packs(self):
        packs = set(self.plan["packs"])
        for ident, names in self.plan["maps"].items():
            self.assertIn(f"map-{ident}", names)
            self.assertTrue(set(names) <= packs, ident)
        for kind in ("sprites", "riding", "characters", "files"):
            self.assertTrue(set(self.plan[kind].values()) <= packs, kind)

    def test_core_excludes_bulk_art(self):
        core = self.plan["packs"]["core"]
        for prefix in ("battle/backgrounds/", "world/1000.json"):
            self.assertFalse(any(p.startswith(plan_web_packs.RES + prefix) for p in core), prefix)
        # Frames outside every sprite or rider animation are shared effects; keep them few.
        effects = [p for p in core if p.startswith((plan_web_packs.RES + "battle/images/", plan_web_packs.RES + "riding/images/"))]
        effect_bytes = sum((LEGACY / p[len(plan_web_packs.RES):]).stat().st_size for p in effects)
        self.assertLess(effect_bytes, 5_000_000)

    @unittest.skipUnless((LEGACY / "loading").is_dir(), "waiting screen assets not imported")
    def test_loading_pack_holds_only_the_small_waiting_screen(self):
        loading = self.plan["packs"]["loading"]
        self.assertTrue(all(p.startswith(plan_web_packs.RES + "loading/") for p in loading))
        self.assertLess(sum((LEGACY / p[len(plan_web_packs.RES):]).stat().st_size for p in loading), 2_000_000)

    def test_villages_depend_on_character_art_they_draw(self):
        self.assertTrue(any(name.startswith("char-") for name in self.plan["maps"]["1000"]))


if __name__ == "__main__":
    unittest.main()
