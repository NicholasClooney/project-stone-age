# 人物面部 (character faces)

Evidence from the pinned 8.5 client source (`references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/`); the 2.5 client's `anim_tbl.h` (`.tools/legacy/anim_tbl.h:1999`) has the same base.

- **Face number.** The creation screen sets `newCharacterFaceGraNo = CG_CHR_MAKE_FACE + family × 100 + colour × 25 + eye × 5 + mouth` (`system/login.cpp:3401-3404`), with `CG_CHR_MAKE_FACE` 30000 (`systeminc/anim_tbl.h:1999`). Family and colour are the appearance's: `selectGraNoTbl[family] + colour × 5` = `SPR_001em` 100000 + family × 20 + colour × 5 (`login.cpp:2481-2494,3399`). Eye and mouth start at 0 (`login.cpp:2799-2800`) and the arrows cycle each through 0..4 (`login.cpp:3545-3592`). So each of the 48 classic appearances has 25 faces: graphic numbers 30000-31199, all 64 × 72 with draw offset (-32, -36), all present in the 2.5 data.
- **Where it shows.** The status window draws `pc.faceGraNo` at (209, 118) of the window (`system/menu.cpp:11754`, classic layout); the login character slots draw each character's face (`login.cpp:2031`) and the creation screen the face being made (`login.cpp:3811`). The server only stores the number (`CHAR_FACEIMAGENUMBER`).

## Here

- `tools/import_faces.py` (run after `import_characters.py`, also from `scripts/setup-original-data.sh`) exports the 1,200 faces as one lossless sprite sheet per appearance, `client/assets/legacy/faces/sheets/<appearance>.png`, with `faces/manifest.json` (per appearance its base number, sheet frames, draw offsets, provenance). The web build puts each sheet in that character's `char-<id>` pack (`tools/plan_web_packs.py`).
- The profile keeps `face` = eye × 5 + mouth (default 0, the original default); changing appearance keeps the eye and mouth. `client/scripts/faces.gd` resolves the number and texture.
- The status window shows the face at the original position in place of the battle portrait (which remains the fallback when faces are not imported).
- The developer character chooser (设置 → 换角色, see `docs/development/character-selection.md`) shows the chosen appearance's face with 眼睛 and 嘴巴 arrows, as on the original creation screen. There is no login character list in this single-player game.
- Not done: the 8.0 `_MO_IMAGE_EXTENSION` faces for the newer appearances (`CG_CHR_MAKE_NEWFACE`), and the later `_NEWPANEL` status layout's face position.
