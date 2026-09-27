# Original stone-fish cursor

The original game window loads `SA_MOUSE1` in `system/main.cpp:718`; its talk window uses the same resource in `system/talkwindow.cpp:128`. `resource.h` maps it to resource 166, and `Script1.rc:37` identifies `123.cur`. The older `pointer.cur` is a different resource (`SA_MOUSE`, 104) and is not the active window cursor.

The active cursor is 32×32 pixels with a `(0,0)` hotspot. Its Windows bitmap stores RGB separately from a one-bit AND transparency mask. The importer preserves both; simply converting the CUR with Pillow loses that mask and produces a black rectangle.

Import from the preserved reference checkout:

```sh
.tools/asset-venv/bin/python tools/import_cursor.py \
  'references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/123.cur'
```

Output is the ignored `client/assets/legacy/cursor/` resource pack, including source SHA-256 and hotspot metadata. No art is redrawn. `legacy_cursor.gd` installs it as a native cursor for every Godot cursor shape, so buttons, text fields, gameplay and battle all retain the original fish instead of switching to platform hands or arrows. The reference does not establish alternate context-specific cursor art. World and UI zoom do not enlarge the native cursor.

Tests:

```sh
.tools/asset-venv/bin/python -m unittest discover -s tools -p test_import_cursor.py
./scripts/run.sh --headless --script res://tests/cursor_test.gd
./scripts/run.sh --script res://tests/cursor_test.gd
```

The graphical test is muted and writes `/tmp/stone-fish-cursor-render.png`, displaying the decoded bitmap at native and magnified sizes on black, green and pale backgrounds. This verifies pixels and transparency; a rendered viewport screenshot does not capture the OS-drawn pointer itself.
