# 年兽重复索引与原版覆盖顺序

## 根因

2.5 客户端 `spradrn_5.bin` 在已有 sprite 条目后追加了更正记录。原版 C 客户端 `system/loadsprbin.cpp:33–55` 顺序读取索引，每次重新赋值 `SpriteData[sprNo]`，因此同编号最后一条覆盖之前的全部动作，不能按动作合并。

导入器过去在第一条匹配记录处 `break`。地、水、火年兽因此依次拿到水、火、风年兽动作；风年兽第一条缺少完整受伤动作，回退 8.0，又拿到相同风年兽。两者同图是错误索引选择的结果，不是原版火风共图。

`tools/import_legacy.py` 的 `sprite_animations` 统一落实最后记录覆盖；战斗和探索解码入口保留各自动作筛选。后续客户端回退仍只在选中的最终动作不完整时发生。跟随宠物与动态立绘通过 `BattleArt` 使用相同战斗分片，无需另造立绘或配色。

## 原始映射

以下 byte offset 位于 2.5 的 `spradrn_5.bin`，动作 offset 位于 `spr_4.bin`。

| 模板 / sprite | 首索引 → 动作 offset | 末索引 → 动作 offset | 正确 standing3_1 首位图 |
|---|---|---|---|
| 901 / 101152 地 | 10044 → 5570744 | 10104 → 5577816 | 233685 |
| 902 / 101153 水 | 10056 → 5574280 | 10116 → 5570744 | 233189 |
| 903 / 101154 火 | 10068 → 5581352 | 10128 → 5574280 | 233437 |
| 904 / 101155 风 | 10080 → 5584888 | 10140 → 5581352 | 233933 |

四只年兽的 2.5 末记录与 8.0 唯一记录的全部 48 个导入动作一致，每只 248 个 bitmap 的解码 RGBA 和 ADRN 几何也一致。正确来源全部是 2.5，不需强制换用 8.0。

## 完整重复索引审计

2.5 只有 101151–101155 有重复记录。101151 的三条索引 byte offset 是 10020、10032、10092，末条与首条相同，只有一个静态动作；不是已导入宠物，也没有受影响输出。

8.0 的重复条目：101866（18600 / 18612 / 18624）、101990（20112 / 20136）、101991（20124 / 20148）。各编号对应的首末条导入动作完全一致，现有宠物分片与最后记录解析结果一致，不需重导或改变图像。它们分别是布里萨尔、司卡奇、莫里卡奇。

对 546 个不同已导入宠物 sprite 扫描：修复前，跨 sprite 共用 frameimage IDs 的唯一组是 `[101154, 101155]`（248 个 IDs）；全部八方向站立序列、全部动作序列、包含 duration/x/y/sound 的全帧签名、逐 sheet 裁剪 RGBA 像素签名也只有该组。没有仅站立相同而其他动作不同的组。修复后再次扫描 546 个 sprite，所有跨 sprite 重复组均为空。共用一帧不能自动判错，必须核对原索引优先级与来源；本次重复不是原版有效末记录的复用。

## 外观证据

`client/data/classic-pets.json` 的名字与模板来自参考服，外部链接用于经典宠物筛选，不是 bitmap 配色数据。其引用的 [17173 年兽 X 档案](https://news.17173.com/z/stoneage/chongwu/pet11.htm) 列出四只年兽；火兽描述为红色、强臂，风兽段配图 URL 是 `https://images.17173cdn.com/stoneage/images/chongwu/9_9.gif`。本次无法抓取该 GIF，不能宣称与解码 bitmap 逐像素一致。[百度经验年兽一览](https://jingyan.baidu.com/article/75ab0bcb807de5d6864db2ce.html) 介绍风兽敏捷，但当前风兽段没有可核对图片。

实际颜色从正确原始 bitmap 解码确认：火 233437 是红色，风 233933 是金黄色，不能从名字或元素推断。参考 `systeminc/loadsprbin.h:43–74` 的帧及索引结构没有每 sprite 调色板字段；`system/directdraw.cpp:38–44,337–490` 使用全局调色板，`system/handletime.cpp:140–141` 按时间更换全局调色板，未找到年兽特定 recolor。四只本来使用不同 bitmap。

正确首帧 RGBA SHA256（翻转为显示方向，透明像素 RGB 为零）：

- 101152 / 233685: `ffac7d5527595d669b20e4138cbed431002aa88bc489fab450b9437b5894c427`
- 101153 / 233189: `57f5098905d4ecba74056feea15314083b1d02cfd2740f3fbd59f62f1b4db360`
- 101154 / 233437: `96af4ea7036ddddfe23ca2c0f4545a3764361844906b5429e997b0ae8c0fe759`
- 101155 / 233933: `d7697cfacc994f6683be9acb53870a4d85083bb3021c9ab2fff036b42dd9dd57`

原始动作索引与数据文件 SHA256：

- 2.5 `spr_4.bin`: `35e7e9363b7d78be5db61d0c4da8380c79fb473ede6e93e0403ad786f333ca1c`
- 2.5 `spradrn_5.bin`: `c822d9a434b34cf83103e2830aa08c58c1d1a41dd244311712a53e1c9ee48777`
- 8.0 `spr_115.bin`: `a4576f4bf27dc49ed61ab71678db2bddcc313c92fd4c6e592f35e8cd8872b229`
- 8.0 `spradrn_115.bin`: `d07587504b0a44e0692a793f00646d268f86d241a91f678556ad660d3fee9fab`

## 调色板精度

SHA 检查还发现 `sprite_sheets.to_palette` 使用 Pillow `quantize(palette=..., dither=NONE)` 时，会近似查找 palette：火首帧一个像素 `(243,218,155)` 被改为 `(240,216,149)`，风首帧六个像素有上述差异或 `(237,210,132)` → `(237,207,133)`。这些不是原始客户端配色差异。

转换现在按原图已有 RGB 精确映射 palette index，透明像素固定 index 0，不量化、不创造新颜色。`test_sprite_sheets.py` 含这两对真实近色的 fixture。局部重导四年兽恢复原始 SHA，其他已导入 sprite 本次保持原样。

## 验证与局部更新

`tools/test_sprite_index.py` 使用 synthetic 二进制索引验证最后条覆盖、部分覆盖不合并、缺动作才回退；安装本地原始客户端时核对四年兽两版全部动作与 bitmap，并审计另外三个重复 sprite 的已导入输出。`client/tests/nianshou_art_test.gd` 核对真正战斗 actor、跟随宠物、立绘和宠物大全缩略图，比较原图 SHA 与 RGBA/调色板两种图集索引；无窗口测试验证加载与像素数据，不声称验证屏幕渲染。

已有完整导入可局部执行（不影响服务；运行游戏需要主会话按工作流重启以刷新缓存）：

```sh
.tools/asset-venv/bin/python tools/import_encounter_art.py .tools/legacy/extracted/SA2.5-20260823/SA2.5/stoneage2.5 --extra-source .tools/legacy/extracted/SA8.0-20260803 --sprites 101152 101153 101154 101155
.tools/asset-venv/bin/python tools/pack_frame_sheets.py battle --sprites 101152 101153 101154 101155
python3 tools/split_manifests.py battle
.tools/asset-venv/bin/python tools/build_pet_thumbs.py
python3 tools/plan_web_packs.py
```

源资源只重新导入四个 sprite；打包阶段重用其他已打包帧，检查其他 sprite sheet/动作分片 SHA 不变。缩略图大小变化会移动共享图集里的其他矩形，因此必须完整生成 RGBA 与 palette 图集及同一索引，不能单独替换一张缩略图。Web pack 计划也随图集更新。
