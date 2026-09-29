# Original character selection

Open **设置 → 换角色** or press **Tab**. The developer chooser displays original animated appearances. Click a preview to change character; close the chooser to resume movement. Selection survives map changes and saving/reloading. Both UI and local authority reject changes during combat.

This is a developer convenience panel, not a reconstruction of the historical character-creation screen. The selected character changes appearance only; it does not reroll progression or equipment.

Above the grid the chooser shows the appearance's original face (人物面部) with the creation screen's 眼睛 and 嘴巴 arrows (five of each). The chosen face is saved in the profile (`face`), keeps its eye and mouth when the appearance changes, and appears in the status window. See [character faces](../reverse-engineering/character-faces.md); import with `tools/import_faces.py` after `tools/import_characters.py`.

## Import and evidence

Run after `tools/import_battle.py`:

```sh
.tools/asset-venv/bin/python tools/import_characters.py /path/to/stoneage2.5
./scripts/run.sh --headless --editor --import --quit
```

`gmsv/char/char_data.c`, `CHAR_eqimagetbl`, maps the 48 classic base appearances to their equipment sprites. `gmsv/include/anim_tbl.h` resolves each symbolic constant. The importer reads both, rather than assuming weapon variants use a numeric offset. Exploration animations and original club battle actions come directly from the local SPR/ADRN archives.

The current source bundle supplies **41 completely validated appearances**. IDs 100080, 100095, 100140, 100145, 100150 and 100155 contain frames rejected by the strict RLE decoder; 100100 references missing bitmap 4294967295. The importer records these exclusions in `characters/catalog.json` and does not manufacture replacements. Repairing the source bundle/decoder is separate work. The UI exposes only validated entries.

Legacy saves without `character_id` default to 100000. If the optional character pack is absent, exploration falls back visually to 100000 while preserving the saved choice for a later import.

## Verification

- `character_selection_test.gd`: animated selection, save/reload, old-save fallback, map rebuild, combat lock and equipped battle variant.
- `test_import_characters.py`: source-table mapping with deliberately nonadjacent equipment IDs, ensuring no `base + 2` shortcut.
- Test launches use the Dummy audio driver.
