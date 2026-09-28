# Original main pet window

The menu-bar pet window uses **mutually exclusive screens**, not a list and detail panel side by side. Restored geometry follows `system/menu.cpp` in the pinned original client:

- List: (4,4),272×320, art26044; five rows begin atY31, spaced51pixels. Names atX69, level at108, HP at168/223. Original list has no miniature pet portraits. State buttons center at(39,41+51i):26052rest,26053battle. Detail/close buttons at(80,299)/(192,299).
- Detail: (4,4),272×332, art26045; nameY35, rename button(86,66), numbersY82/106/130/154/178/202/226/250. Native pet art anchors at(200,144) with original bitmap offsets and is animated: `MakeAnimDisp(x+200,y+144,graNo,ANIM_DISP_PET)` (menu.cpp:12777) starts `ANIM_STAND` at facing 1 (menu.cpp:1879-1881) and `AnimDisp` loops it at normal speed; clicking the pet turns it one facing and plays sound 217 (menu.cpp:1177-1188). `animated_portrait.gd` reproduces this from the battle manifest (action 3, `duration_ms` spread over the frames, as in `battle_view.gd`) on a shared clock, so the frequent rebuilds of the window neither restart the loop nor reset the chosen facing until the window is reopened. Skill button(198,286), navigation/return alongY317.
- Skills: (4,4),272×348, art26130. Slot overlays26131+ use ADRN offsets relative towindowcenter(136,174), **not (0,0)**. Basic and learned skill names occupy25pixel rows. Return/navigationY330.
- Rename: original26049window immediately below detail atglobal(4,340), with original confirm26093/cancel26050 controls.

Source sections: list12300–12745; detail12750and15150–15335; skills15350–15710. Reference builds contain conditional later-version additions; riding, mail, pet dropping, album registration and unavailable elemental/loyalty data are not fabricated. Current state button toggles the implemented active pet/rest behavior.

`tools/import_mvp.py` now extracts all required rename, navigation and skill-row sprites. `pet_window_test.gd` verifies five-pet geometry, screen replacement, the native portrait animating, turning and continuing across rebuilds, rename, active selection and withdrawal. Muted rendered checks produce `/tmp/pet-window-list.png`, `/tmp/pet-window-detail.png`, `/tmp/pet-window-skills.png` with `-- --capture`.
