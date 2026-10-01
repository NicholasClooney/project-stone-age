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
        on_disk = {plan_web_packs.res(p) for p in LEGACY.rglob("*") if p.is_file() and p.suffix != ".import" and p.name != ".DS_Store"
                   and not plan_web_packs.is_source(p)}
        self.assertEqual(on_disk - set(self.plan["skipped"]), set(seen))
        self.assertFalse(set(self.plan["skipped"]) & set(seen))

    def test_importer_manifests_are_not_shipped(self):
        shipped = {path for paths in self.plan["packs"].values() for path in paths}
        for source in ("battle/manifest.json", "riding/manifest.json", "characters/catalog.json", "battle/backgrounds.json"):
            self.assertNotIn(plan_web_packs.RES + source, shipped)
        self.assertFalse(any(path.startswith(plan_web_packs.RES + "battle/pets/") for path in shipped))

    @unittest.skipUnless((LEGACY / "battle/index.json").is_file(), "art manifests not split (tools/split_manifests.py)")
    def test_core_holds_the_indexes_and_every_non_pet_sprite_file(self):
        import json
        core = set(self.plan["packs"]["core"])
        for name in ("battle/index.json", "riding/index.json", "characters/index.json", "battle/battlefields.json"):
            self.assertIn(plan_web_packs.RES + name, core)
        index = json.loads((LEGACY / "battle/index.json").read_text())
        for ident in index["sprites"]:
            self.assertIn(f"{plan_web_packs.RES}battle/sprites/{ident}.json", core, ident)
        for ident in json.loads((LEGACY / "characters/index.json").read_text())["characters"]:
            self.assertIn(f"{plan_web_packs.RES}characters/art/{ident}.json", core, ident)

    def test_thumbnail_variants_have_independent_complete_packs(self):
        import json
        index = json.loads((LEGACY/'thumbs/index.json').read_text())
        self.assertIn(plan_web_packs.RES+'thumbs/index.json',self.plan['packs']['core'])
        for key in ('files','palette_files'):
            for name in index.get(key,[]):
                path = plan_web_packs.RES+'thumbs/'+name
                pack = self.plan['files'][path]
                self.assertTrue(pack.startswith('thumbs-'))
                self.assertEqual(self.plan['packs'][pack],[path])
                self.assertEqual(pack.startswith('thumbs-palette-'),key=='palette_files')

    def test_lookups_name_real_packs(self):
        packs = set(self.plan["packs"])
        for ident, names in self.plan["maps"].items():
            self.assertIn(f"map-{ident}", names)
            self.assertTrue(set(names) <= packs, ident)
        for kind in ("sprites", "riding", "characters", "files"):
            self.assertTrue(set(self.plan[kind].values()) <= packs, kind)

    def test_core_excludes_bulk_art(self):
        core = self.plan["packs"]["core"]
        for prefix in ("battle/backgrounds/", "world/1000.map", "world/1000.json"):
            self.assertFalse(any(p.startswith(plan_web_packs.RES + prefix) for p in core), prefix)
        # Frames outside every sprite or rider animation are shared effects; keep them few.
        effects = [p for p in core if p.startswith((plan_web_packs.RES + "battle/images/", plan_web_packs.RES + "riding/sheets/"))]
        effect_bytes = sum((LEGACY / p[len(plan_web_packs.RES):]).stat().st_size for p in effects)
        self.assertLess(effect_bytes, 5_000_000)

    @unittest.skipUnless((LEGACY / "loading").is_dir(), "waiting screen assets not imported")
    def test_loading_pack_holds_only_the_small_waiting_screen(self):
        loading = self.plan["packs"]["loading"]
        self.assertTrue(all(p.startswith(plan_web_packs.RES + "loading/") for p in loading))
        self.assertLess(sum((LEGACY / p[len(plan_web_packs.RES):]).stat().st_size for p in loading), 2_000_000)

    @unittest.skipUnless((LEGACY / "riding/manifest.json").is_file(), "riding composites not imported")
    def test_every_riding_pair_has_a_complete_pack(self):
        import json
        riding = json.loads((LEGACY / "riding/manifest.json").read_text())
        for key, pair in riding["pairs"].items():
            ident = str(pair["sprite"])
            pack = self.plan["riding"].get(ident)
            self.assertEqual(pack, f"riding-{ident}", key)
            contents = set(self.plan["packs"][pack])
            if (LEGACY / "riding/index.json").is_file():
                self.assertIn(f"{plan_web_packs.RES}riding/composites/{ident}.json", contents, key)
            sheet = riding["sheets"][ident]
            for name in sheet["files"]:
                self.assertIn(f"{plan_web_packs.RES}riding/{name}", contents, key)
            for animation in riding["characters"][ident].values():
                for frame in animation["frames"]:
                    self.assertIn(str(int(frame["image"])), sheet["frames"], key)

    def test_every_battle_sprite_pack_holds_its_sheet(self):
        import json
        battle = json.loads((LEGACY / "battle/manifest.json").read_text())
        if "sheets" not in battle:
            self.skipTest("battle frames not packed into sheets")
        for ident, animations in battle["characters"].items():
            sheet = battle["sheets"][ident]
            contents = set(self.plan["packs"][self.plan["sprites"][ident]])
            for name in sheet["files"]:
                self.assertIn(f"{plan_web_packs.RES}battle/{name}", contents, ident)
            for animation in animations.values():
                for frame in animation["frames"]:
                    self.assertIn(str(int(frame["image"])), sheet["frames"], ident)

    def test_every_extra_pet_sprite_pack_holds_its_file_and_sheet(self):
        import json
        battle = json.loads((LEGACY / "battle/manifest.json").read_text())
        if not battle.get("extra_sprites"):
            self.skipTest("no pet sprites kept in their own files")
        core = set(self.plan["packs"]["core"])
        for ident, name in battle["extra_sprites"].items():
            extra = json.loads((LEGACY / "battle" / name).read_text())
            contents = set(self.plan["packs"][self.plan["sprites"][ident]])
            runtime = f"{plan_web_packs.RES}battle/sprites/{ident}.json"
            self.assertIn(runtime, contents, ident)
            self.assertNotIn(runtime, core, ident)
            sheet = extra["sheets"][ident]
            for file in sheet["files"]:
                self.assertIn(f"{plan_web_packs.RES}battle/{file}", contents, ident)
            for animation in extra["characters"][ident].values():
                for frame in animation["frames"]:
                    self.assertIn(str(int(frame["image"])), sheet["frames"], ident)

    def test_every_character_pack_holds_its_sheet(self):
        import json
        catalog = json.loads((LEGACY / "characters/catalog.json").read_text())
        if "sheets" not in catalog:
            self.skipTest("character frames not packed into sheets")
        for ident in catalog["characters"]:
            contents = set(self.plan["packs"][self.plan["characters"][ident]])
            for name in catalog["sheets"][ident]["files"]:
                self.assertIn(f"{plan_web_packs.RES}characters/{name}", contents, ident)

    def test_villages_depend_on_character_art_they_draw(self):
        self.assertTrue(any(name.startswith("char-") for name in self.plan["maps"]["1000"]))

    @unittest.skipUnless((LEGACY / "music/manifest.json").is_file(), "music library not imported")
    def test_music_library_packs_one_track_each_and_battle_music_in_core(self):
        import json
        library = plan_web_packs.library_tracks()
        self.assertGreaterEqual(len(library), 24)
        battle = json.loads((LEGACY / "battle/manifest.json").read_text())
        battle_music = {Path(name).stem for name in battle["audio"].values() if Path(name).name.startswith("sabgm_")}
        self.assertIn("sabgm_b0", battle_music)
        for ident, path in library.items():
            where = plan_web_packs.res(path)
            if ident in battle_music:
                self.assertIn(where, self.plan["packs"]["core"], ident)
            else:
                self.assertEqual(self.plan["packs"][f"music-{ident}"], [where], ident)
                self.assertEqual(self.plan["files"][where], f"music-{ident}")
        # No older copy of a library track (world/audio/sabgm_t0.wav ...) is shipped.
        for name, paths in self.plan["packs"].items():
            for path in paths:
                file = Path(path)
                if file.name.startswith("sabgm_") and file.parent.name not in ("music", "loading"):
                    self.fail(f"{path} in {name}: the library copy plays instead")


if __name__ == "__main__":
    unittest.main()
