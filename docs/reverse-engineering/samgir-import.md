# Samgir resource import — observed evidence

## Inputs

- Community client archive: `https://99ds.com/downloads/windows/Stoneage2.5-Windows.rar`, served as `SA2.5-20260823.rar`.
- Archive SHA-256: `0e157c0fcfe2bcf91826907d580d4403138d86fab9488aa39cd9494af17449ae`.
- Original server map: [samugiru](https://github.com/chenmingbiao/stone-age/blob/master/gmsv/data/map/sainasu/samugiru/samugiru).
- Server map SHA-256: `6db7b01e1b0f07102ec8f50e25ff7adf4d87e7cc890def5f3171e466ee14127e`.
- Client cached `1000.DAT` SHA-256: `94b19cb59d72b7b48da70d2741ba68516caad970297fd48ed11ef720fa3ea97e`.
- `Palet_1.sap` SHA-256: `32870080c47537a59beaf770b6df7bd79820fd52a23825058460900494f0b4b0`.

These are observed legacy resources from community distributions, not proof of an untouched official release. Inputs stay in ignored local storage; converted proprietary assets are also ignored.

## Format findings

Cross-checked against `anson1788/stoneage`, under `石器时代8.5客户端最新源代码/石器源码/`:

| Source | Implemented finding |
| --- | --- |
| `systeminc/loadrealbin.h`, `system/loadrealbin.cpp` | 80-byte ADRN records; image ID, file offset/length, signed draw offsets, dimensions, footprint, hit flags, map graphic ID at byte 76 |
| `system/unpack.cpp` | RD header and nibble-command JSS RLE; literal, repeated-color, and transparent runs |
| `system/directdraw.cpp`, `systeminc/palname.h` | `Palet_1.sap` is default; BGR colors occupy indices 16–239, fixed colors outside; transparent index 0 |
| `system/loadsprbin.cpp`, `systeminc/loadsprbin.h` | 12-byte SPRADRN records; 12-byte animation header; 10-byte frames containing image ID, offsets, sound ID |
| `system/map.cpp` | Isometric projection, original movement direction table, and footprints extending +X / −Y |
| `system/t_music.cpp` | Map tone 40 → BGM index 4 → `data/bgm/sabgm_t0.wav` |
| `chenmingbiao/stone-age/gmsv/map/readmap.c` | LS2MAP header, big-endian dimensions and ground/object arrays |

Pixel verification established bottom-up bitmap rows; the importer flips rows when producing PNGs. Preserve ADRN and frame offsets separately. Action 3 is idle, 4 walk, 5 sit, and 6 hand/wave. Duration fields are retained in milliseconds. Direction 0 faces south and 4 north in the original movement table.

## Map selection

Both sources identify Samgir as map 1000, 160 × 160 cells. The client cache had incomplete outer cells and later decorative objects near (86–90, 85–89), including two references to missing graphic 22413. The selected server map has the original geometry without those additions; its import resolves every required graphic.

The current conversion produces 25,600 ground cells, 482 scenery objects, and 1,066 unique textures including three character appearances. `client/assets/legacy/provenance.json` records the actual conversion result.

## Runtime limits

Collision uses original ground hit flags, object footprints, and invisible blocking markers. This is local movement validation, not a complete server movement implementation. Special later-edition collision exceptions, NPC occupancy, warps, battles, and map events remain deferred.

BGM association is verified through map tone and source table. A legacy sound file is used as click feedback; its exact historical UI assignment is not yet verified. No generated replacement art or music is active.

The Godot HUD is new and minimal. It uses OFL-licensed Noto Sans SC from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc), with the license in `client/assets/fonts/OFL.txt`.
