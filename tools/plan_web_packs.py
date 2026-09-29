"""Plan on-demand asset packs for the web build.

Every file under client/assets/legacy lands in exactly one pack, so shared
art is never downloaded twice:

  loading         the waiting screen's image and music, fetched before
                  anything else so the screen can cover the core download
  core            small always-needed data: catalogs, UI, battle
                  manifest/UI/audio, the map catalog
  map-<id>        one map's JSON plus tiles and residents no other map uses
  char-<id>       one player character's walking art
  tiles-<hash>    tiles shared by several maps, grouped by the exact set of
                  maps that use them
  sprite-<id>     one battle/pet sprite's frames
  riding-<id>     one mounted composite's frames
  bg-<name>       one battle background
  music-<name>    one music track
  radio-<name>    one radio (电台) track, fetched when the radio plays it

Writes build/web-packs/plan.json: pack name -> res:// paths, plus the
lookups the game needs (map -> packs, sprite -> pack, file -> pack).
build_web_packs.gd turns the plan into .pck files.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "client/assets/legacy"
RES = "res://assets/legacy/"


def res(path: Path) -> str:
    return RES + path.relative_to(LEGACY).as_posix()


def sprite_images(characters: dict) -> dict:
    result = {}
    for ident, animations in characters.items():
        frames = set()
        for animation in animations.values():
            for frame in animation.get("frames", []):
                frames.add(str(int(frame["image"])))
        result[str(ident)] = frames
    return result


def plan() -> dict:
    files = [p for p in LEGACY.rglob("*") if p.is_file() and p.suffix != ".import" and p.name != ".DS_Store"]
    owner: dict = {}
    packs = collections.defaultdict(list)

    def assign(pack: str, path: Path) -> None:
        if path.exists() and path not in owner:
            owner[path] = pack
            packs[pack].append(res(path))

    # Fetched first and kept tiny: the waiting screen shown during every other download.
    for path in sorted((LEGACY / "loading").glob("*")):
        if path.suffix != ".import" and path.name != ".DS_Store":
            assign("loading", path)

    manifest = json.loads((LEGACY / "world/manifest.json").read_text())
    maps_images = {}
    map_json = {}
    for ident, info in manifest["maps"].items():
        path = LEGACY / info["path"]
        if not path.exists():
            continue
        data = json.loads(path.read_text())
        map_json[ident] = path
        maps_images[ident] = set(data.get("images", {}).keys())
    use = collections.Counter()
    for images in maps_images.values():
        use.update(images)

    # Character art lives beside map tiles but is chosen per player, not per map.
    characters = json.loads((LEGACY / "characters/catalog.json").read_text())
    character_images = set(str(k) for k in characters.get("images", {}))
    lookups = {"maps": {}, "sprites": {}, "riding": {}, "characters": {}, "files": {}}
    for ident, images in sprite_images(characters.get("characters", {})).items():
        pack = f"char-{ident}"
        # The character's sprite sheet (tools/pack_frame_sheets.py), plus frame
        # PNGs still present: ones maps also draw, or an import not packed yet.
        for name in characters.get("sheets", {}).get(ident, {}).get("files", []):
            assign(pack, LEGACY / "characters" / name)
        for image in sorted(images):
            assign(pack, LEGACY / f"images/{image}.png")
        lookups["characters"][ident] = pack
    # The status window's face (tools/import_faces.py) travels with the character.
    faces_manifest = LEGACY / "faces/manifest.json"
    if faces_manifest.exists():
        for ident, sheet in json.loads(faces_manifest.read_text()).get("sheets", {}).items():
            if ident in lookups["characters"]:
                for name in sheet.get("files", []):
                    assign(lookups["characters"][ident], LEGACY / "faces" / name)

    signatures = collections.defaultdict(set)
    for image, count in use.items():
        if image in character_images:
            continue
        if count > 1:
            signatures[frozenset(m for m, s in maps_images.items() if image in s)].add(image)
    for ident, path in map_json.items():
        pack = f"map-{ident}"
        assign(pack, path)
        for image in sorted(maps_images[ident]):
            if use[image] == 1 and image not in character_images:
                assign(pack, LEGACY / f"images/{image}.png")
        lookups["maps"][ident] = [pack]
    npc_maps = collections.defaultdict(set)
    for resident in manifest.get("residents", []):
        if resident.get("path"):
            npc_maps[resident["path"]].add(str(int(resident["map_id"])))
    for path, users in npc_maps.items():
        if len(users) == 1 and next(iter(users)) in lookups["maps"]:
            assign(f"map-{next(iter(users))}", LEGACY / path)
    # Maps that draw character art (villagers share player sprites) need those packs.
    character_pack_of = {}
    for ident, images in sprite_images(characters.get("characters", {})).items():
        for image in images:
            character_pack_of.setdefault(image, f"char-{ident}")
    for ident, images in maps_images.items():
        for image in sorted(images & character_images):
            pack = character_pack_of.get(image)
            if pack and pack not in lookups["maps"][ident]:
                lookups["maps"][ident].append(pack)
    for users, images in signatures.items():
        digest = hashlib.sha1(",".join(sorted(users)).encode()).hexdigest()[:10]
        pack = f"tiles-{digest}"
        for image in sorted(images):
            assign(pack, LEGACY / f"images/{image}.png")
        for ident in users:
            lookups["maps"][ident].append(pack)

    battle = json.loads((LEGACY / "battle/manifest.json").read_text())
    # One battle sprite's sheet(s) per pack (tools/pack_frame_sheets.py);
    # per-frame PNGs from an import that was not packed yet still work.
    for ident, sheet in battle.get("sheets", {}).items():
        pack = f"sprite-{ident}"
        for name in sheet["files"]:
            assign(pack, LEGACY / "battle" / name)
        lookups["sprites"][ident] = pack
    for ident, images in sprite_images(battle.get("characters", {})).items():
        pack = f"sprite-{ident}"
        for image in sorted(images):
            assign(pack, LEGACY / f"battle/images/{image}.png")
        lookups["sprites"][ident] = pack
    riding_manifest = LEGACY / "riding/manifest.json"
    if riding_manifest.exists():
        riding = json.loads(riding_manifest.read_text())
        # One composite's sprite sheet(s) per pack (tools/import_riding.py).
        for ident, sheet in riding.get("sheets", {}).items():
            pack = f"riding-{ident}"
            for name in sheet["files"]:
                assign(pack, LEGACY / "riding" / name)
            lookups["riding"][ident] = pack

    for path in sorted((LEGACY / "battle/backgrounds").glob("*")):
        if path.suffix != ".import":
            pack = f"bg-{path.stem}"
            assign(pack, path)
            lookups["files"][res(path)] = pack
    music = [p for p in files if p.suffix == ".wav" and p.name.startswith("sabgm_") and "battle" not in p.parts]
    for path in sorted(music):
        pack = f"music-{path.stem}"
        assign(pack, path)
        lookups["files"][res(path)] = pack
    for path in sorted((LEGACY / "music").glob("sabgm_*")):
        if path.suffix != ".import":
            pack = f"radio-{path.stem}"
            assign(pack, path)
            lookups["files"][res(path)] = pack

    for path in sorted(files):
        assign("core", path)
    return {"packs": {name: sorted(paths) for name, paths in packs.items()}, **lookups}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default=str(ROOT / "build/web-packs/plan.json"))
    args = parser.parse_args()
    result = plan()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False))
    sizes = collections.Counter()
    for name, paths in result["packs"].items():
        for path in paths:
            sizes[name] += (LEGACY / path[len(RES):]).stat().st_size
    kinds = collections.Counter(name.split("-")[0] for name in result["packs"])
    print(f"{len(result['packs'])} packs {dict(kinds)}; loading {sizes['loading']/1e3:.0f} KB; core {sizes['core']/1e6:.1f} MB; total {sum(sizes.values())/1e6:.1f} MB")


if __name__ == "__main__":
    main()
