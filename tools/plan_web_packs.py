"""Plan on-demand asset packs for the web build.

Every file under client/assets/legacy lands in exactly one pack, so shared
art is never downloaded twice:

  loading         the waiting screen's image and music, fetched before
                  anything else so the screen can cover the core download
  core            small always-needed data: catalogs, UI, the battle,
                  riding and character indexes, battle sprites' and
                  characters' own files (tools/split_manifests.py), the
                  map catalog, the battle music
  map-<id>        one map file (world/<id>.map) plus tiles and residents no other map uses
  char-<id>       one player character's walking art
  tiles-<hash>    tiles shared by several maps, grouped by the exact set of
                  maps that use them
  sprite-<id>     one battle/pet sprite's frames (and, for a pet sprite
                  only 宠物大全 and GM grants need, its own file)
  riding-<id>     one mounted composite's frames and its own file

The importers' working manifests (battle/manifest.json, battle/pets/,
riding/manifest.json, characters/catalog.json, battle/backgrounds.json) are
not shipped: the game reads the files split_manifests.py makes from them.
They still tell this planner which pack owns each sheet.
  bg-<name>       one battle background
  music-<name>    one track of the music library (tools/import_music.py),
                  fetched when a map, or the radio (电台), plays it

Copies of a music track outside the library (world/audio/sabgm_*.wav and
the like, left by older imports) are not packed: the game plays the
library's Ogg Vorbis instead (client/scripts/music_tracks.gd). They are
listed under "skipped".

Writes build/web-packs/plan.json: pack name -> res:// paths, plus the
lookups the game needs (map -> packs, sprite -> pack, file -> pack).
build_web_packs.gd turns the plan into .pck files.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

from map_file import load_map

ROOT = Path(__file__).resolve().parents[1]
LEGACY = ROOT / "client/assets/legacy"
RES = "res://assets/legacy/"
# Importer working data the game does not read (tools/split_manifests.py).
SOURCES = ("battle/manifest.json", "battle/pets", "riding/manifest.json", "characters/catalog.json",
           "battle/backgrounds.json")


def is_source(path: Path) -> bool:
    relative = path.relative_to(LEGACY).as_posix()
    return any(relative == source or relative.startswith(source + "/") for source in SOURCES)


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


def library_tracks() -> dict:
    """Track id -> file of the music library (music/manifest.json)."""
    manifest = LEGACY / "music/manifest.json"
    if not manifest.exists():
        return {}
    tracks = json.loads(manifest.read_text()).get("tracks", [])
    return {t["id"]: LEGACY / t["file"] for t in tracks if (LEGACY / t["file"]).exists()}


def stale_music(path: Path, library: dict) -> bool:
    """An older import's copy of a track the library has (not the waiting screen's)."""
    parts = path.relative_to(LEGACY).parts
    return (path.name.startswith("sabgm_") and path.suffix in (".wav", ".ogg") and parts[0] not in ("music", "loading")
            and path.stem in library)


def plan() -> dict:
    library = library_tracks()
    files = [p for p in LEGACY.rglob("*") if p.is_file() and p.suffix != ".import" and p.name != ".DS_Store"]
    skipped = sorted(res(p) for p in files if stale_music(p, library))
    files = [p for p in files if not stale_music(p, library) and not is_source(p)]
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
        data = load_map(path, header_only=True)
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
    quest_catalog = LEGACY / "quests/catalog.json"
    if quest_catalog.exists():
        for npc in json.loads(quest_catalog.read_text())["npcs"]:
            npc_maps[npc["path"]].add(str(int(npc["map_id"])))
            for mode in ["main","changed"]:
                visual=npc.get("time_visuals",{}).get(mode,{})
                if visual.get("path"):npc_maps[visual["path"]].add(str(int(npc["map_id"])))
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
    # Pet sprites kept in their own file (import_encounter_art.py): the
    # sprite's runtime file travels with its sheets, so only the index's
    # small list is in core. Every other sprite's runtime file is in core.
    for ident, name in battle.get("extra_sprites", {}).items():
        pack = f"sprite-{ident}"
        path = LEGACY / "battle" / name
        if not path.exists():
            continue
        extra = json.loads(path.read_text())
        assign(pack, LEGACY / "battle/sprites" / f"{ident}.json")
        for sheet in extra.get("sheets", {}).values():
            for file in sheet["files"]:
                assign(pack, LEGACY / "battle" / file)
        for image in sorted(sprite_images(extra.get("characters", {})).get(ident, set())):
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
            assign(pack, LEGACY / "riding/composites" / f"{ident}.json")
            lookups["riding"][ident] = pack

    for path in sorted((LEGACY / "battle/backgrounds").glob("*")):
        if path.suffix != ".import":
            pack = f"bg-{path.stem}"
            assign(pack, path)
            lookups["files"][res(path)] = pack
    # Every battle plays its music at once, so the tracks the battle manifest
    # names stay in core; the rest of the library is one pack per track.
    battle_music = {Path(name).stem for name in battle.get("audio", {}).values() if Path(name).name.startswith("sabgm_")}
    for ident, path in sorted(library.items()):
        if ident in battle_music:
            assign("core", path)
            continue
        pack = f"music-{ident}"
        assign(pack, path)
        lookups["files"][res(path)] = pack
    # Without a library (an older import) each music file is its own pack.
    for path in sorted(files):
        if path.name.startswith("sabgm_") and path.suffix in (".wav", ".ogg") and "battle" not in path.parts and path not in owner:
            pack = f"music-{path.stem}"
            assign(pack, path)
            lookups["files"][res(path)] = pack

    # 宠物大全's pre-cut thumbnails (tools/build_pet_thumbs.py): the small
    # index is in core, the atlases are one quiet background pack each.
    for path in sorted(list((LEGACY / "thumbs").glob("atlas-*.png")) + list((LEGACY / "thumbs").glob("palette-*.png"))):
        pack = f"thumbs-{'palette-' if path.stem.startswith('palette-') else ''}{path.stem.split('-')[-1]}"
        assign(pack, path)
        lookups["files"][res(path)] = pack

    for path in sorted(files):
        assign("core", path)
    return {"packs": {name: sorted(paths) for name, paths in packs.items()}, **lookups, "skipped": skipped}


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
