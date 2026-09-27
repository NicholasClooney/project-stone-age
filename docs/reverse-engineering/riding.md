# Riding / 骑乘: reference support

The preserved reference implements riding. It is not yet restored in the Godot game.

- Server `gmsv/char/char.c` stores `CHAR_RIDEPET` separately from the active battle pet.
- `gmsv/battle/battle_event.c:157` resolves the mounted pet with `BATTLE_getRidePet`; `BATTLE_adjustRidePet3A` below it combines rider/pet combat stats, with weapon and historical build branches.
- Original client `system/menu.cpp:12642` treats `pc.ridePetNo` as a distinct pet-menu state and selects its riding-state artwork.
- `gmsv/include/version.h` contains `_EVERYONE_RIDE`, `_RIDEMODE_20`, `_NEW_RIDEPETS` and later family/item/custom riding switches. These variants must not be silently combined into one rule set.

A restoration needs a chosen historical ruleset, valid rider/mount graphic mappings, mount/dismount state, battle integration and save migration. Matching mounted animations in the local2.5 asset archive still need verification; source support alone does not prove every mount asset is available.
