# Later pets: 8.0 sprites and the 8.5 album

Where the pets beyond the reference server's templates come from, and why they have pictures but no numbers. Data: [`pets-8.0.json`](pets-8.0.json). Used by `tools/import_encounters.py`, `tools/import_encounter_art.py` and [宠物大全](../development/pet-encyclopedia.md).

## Sources checked for stats

| Source | What it has |
| --- | --- |
| `references/chenmingbiao-stone-age/gmsv/data/enemybase.txt` (`enemybase1.txt` is identical) | The only pet stat table: 952 templates, 459 of them pets. Already later than 2.5: 机豹 968, 黑乌力王 1147 and 布里萨尔 1177 are there, with sprites only the 8.0 client has. |
| `references/anson1788-stoneage` server (`Serv.zip`) | Source code only, no `data/` tables. |
| 8.5 client source, `systeminc/petName.h` (`PetAlbumTbl`) | Album number, name and album face graphic of 542 pets. No stats. |
| 8.0 client `data/` | Graphics and sounds. `album_37.dat` and `album_47.dat` are saved player albums (captured pets' levels and stats), not species tables. |

So no original stats exist for the 131 album pets without an `enemybase` template. They are imported with art and `stats_known: false`; nothing is invented. 2.5-era and `enemybase` templates are unchanged.

## Pairing album names with sprites

The album stores a face picture per pet, not the battle sprite. The 8.5 client's `CheckNewPet` (`system/menu.cpp`) maps a sprite number to an album row, but its ranges follow the 8.5 client's numbering and are off by one or more against the 8.0 data and the server (布里萨尔 is 101866 in `enemybase` and the 8.0 data, 101867 by that code). It was not used.

Instead each album-only pet was paired by eye: its face graphic (`face`, an 8.0 graphic number) next to the standing frame of candidate 8.0 sprites. New pets come in runs of the album's order (four colour variants of one design, one page after another), with non-pet graphics (riders, effects, map pieces) between runs. All 131 pairs were checked; for 摩洛索思 (101886) the face and sprite differ most, but its place in the run and the 8.5 source's comment (麒麟) agree.

- 艾比斯 is in the album under that name but is template 995 艾柏瑞 (same sprite 101450). Not added again.
- `史凯勒顿`, `古斯特` and `雷尔` are album names whose `enemybase` templates are not pets (`pet_flag` 0). Left as they are.
- Unnamed album rows (the name is empty) are skipped.

## In the game

- Template id 10000 + album number, `source: "8.0"`, `stats_known: false`, `album`, `face`. No encounter group names them, so they never spawn.
- 宠物大全 shows the sprite, the album family and "没有原版数值"; no Lv.120 prediction. GM 调试 refuses to grant them (a pet needs an initial value and weights to be born).
- Their sprites come from the 8.0 data, so they need the 8.0 data, which `setup-original-data.sh` imports unless run with `--no-8.0`.

## Battle sprites from two clients

`tools/import_encounter_art.py` reads a sprite from the 2.5 client when it has all actions, else from the 8.0 data (313 of the 545 sprites it imports). Bitmaps are keyed by number in the manifest and in the battle view, and the 8.0 data reuses some 2.5 numbers for other pictures: such a bitmap of an 8.0 sprite becomes 1,000,000,000 + its number (3,313 bitmaps, among them all of 机豹's). A number both clients decode to the same pixels is kept. Before this, 机豹 was imported under the 8.0 numbers, which name other pictures in 2.5.

Two 8.0 sprites point one frame at the missing bitmap 4294967295, as 100100 does in every client, and stay unavailable: 亚瑟力 (101925, dead facing 6) and 夏莫 (102070, attack facing 0).
