# Priority companions

On the next normal launch, a one-time starter claim adds each companion only once and preserves existing pets. It contains the requested blue human dragon, gold tiger and **one red T-rex**. The user's correction removed gold/mechanical/other T-rexes from this starter pack.

| Display alias | Original name | Template | Sprite | Initial | V / S / T / D weights |
|---|---|---:|---:|---:|---|
| 蓝人龙 | 扬奇洛斯 | 92 | 100288 | 29 | 27 / 36 / 16 / 20 |
| 金虎 | 金格萨贝鲁 | 194 | 100330 | 25 | 19 / 29 / 18 / 29 |
| 红暴龙 | 巴朵兰恩 | 303 | 100373 | 27 | 23 / 37 / 20 / 25 |

Source: pinned `gmsv/data/enemybase.txt`. All three use the original 4.50 growth parameter. Explicit template IDs avoid replacing ordinary pets with similarly named newbie or boss records. Original sprites were visually checked; all eight idle/walk/attack/damage/death/guard directions are validated during import.

Run `tools/import_pets.py` against the local original client **after** `import_battle.py` and `import_characters.py`. It extends the battle manifest and writes an ignored provenance catalogue. Run the Godot editor import after all asset importers finish.

The collection capacity is 30, a deliberate single-player convenience rather than an assertion about the historical carried-pet limit. Riding and fighting are separate assignments. This requested starter pack and its optional developer re-grant do not alter original encounter tables or quest rewards. Tests use temporary profiles and do not claim companions in the player save.
