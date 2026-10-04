# 公开走廊第一轮几何实际结果

## 执行与窗口

精确基点main b5ec513c，pool-b / feat/quest-auto-public-corridors；没有2b答案历史。
获准后仅运行一次：
`./scripts/run.sh --headless --script res://tests/quest_auto_public_corridors_geometry_test.gd`
命令进程结束，已立即notice释放窗口；交错的再次确认没有引起重复启动。未运行其它suite/check-only/import/六job长路/full。

实际wall **2.529秒**，suite内部1479ms；113断言，0失败，exit0。
首跑无解析/断言错误。完整原日志 `public-expansion-geometry-first.log`。

## 数量和剔除

37源候选中，**29几何通过 / 8剔除**。通过按map分布：100十四条、200十四条、5000一条。8条全部为map300：forde→miner/golden/brothers、三洞→forde、forde↔jiru。
这些原create端点真实存在，但当前原A碰撞寻路从精确原落点到原门得不到可用通路。只记录此实际结果，不臆断缺口具体成因，亦不以B掩盖A失败。它们不纳首轮生产扩展，后续恢复地图交通需另审。
既有7条不变，若29条正式接policy，则总数36；**本次仍未修改生产，实际新增0**，并非已上线36条。

通过逐项A步数、B候选门前格、起点portal标记见附表；结构化完整源/几何组合见public-expansion-geometry-results.json。
此处“A路径”是同一个生产Navigation.local_path在固定start→精确door上的原路径；不是已验证每个任务的Navigation.plan都会选该door。实际任务若选其它门或路径不等精确后缀，继续A，后续执行suite才统计收益。

## 本次验证覆盖/未覆盖

- 37项实时原link完整身份与源行对照；起点至少一个原返回link仍存在。此前source-table生成已核create原块/实际create字节SHA。本轮没有重新hash全部开发reference地图文件；地图SHA仍是已审manifest provenance，不能称已独立复算地图源SHA。
- 29路径逐逻辑格相邻、原碰撞/居民有效；中间没有portal或保护scope；门前格紧邻精确door；door不能成为项目快移落点。
- 起点本身为原portal的5项（marju-mati、sea-goya、goya-karutana、goya-jaja、sea-tamutamu）必须先真实walk离开，再检查精确后缀；不是从portal直接B/C起跳。
- 保护负例拒10201/10202/10203海洞、10204、120/121脚本口袋、20101、20401/20406、118/119/122、32001；另拒300(105,228)/(108,225)/(103,228)/(109,226)。未修改arrival/policy。
- 占格负例：为每个通过项复制occupied并插入门前格，public_candidate必须拒绝，共29项。这是**纯几何阻挡负例**；实时NPC版本变化后已签segment失效的执行行为尚未验。
- 未审fallback本轮没有调用next_segment或执行器，因此**未新增fallback执行绿证据**。suite只给候选分类；生产仍7条，下一片须加未审/变门/动态改位→A或安全停的实际接口验证。
- A/C同序列、每格自然遭遇首次截尾、B不授proof、完整ACK与逐job fast/protected_walk全未在此几何套声称通过，后续分别验。

## 任务收益调整

可进入实现候选：job12/13亚姆双方野外段；job5马祖去迷宫外段；job9原出洞落点返回马提段；job24及独立公开起点job25前往哥亚的野外段。连续job25仍全保护walk/fast0，旧洞口job24 fixture仍可fast0。
job1/11/30既有7段保留，并增加相应公开接近候选；具体真实fast数量待执行。
第二批萨顿/博士/强恩/龙洞/哈恩/四宝玉/公开卡鲁它那交通，以及福尔德村内→深蓝洞外几何候选保留。矿工/金羊/五兄弟与福尔德↔吉鲁交通因8候选失败，本片明确不新增覆盖。
脚本NPC公开接近、300外门口袋、所有洞内/守卫/票/口令继续A或原manual；不宣称覆盖全部未来路线。

## 下一片

可按29通过项接只读public_routes精确表，复用现执行器；旧A算法、核心文件不改。
应先短验生产audit/validate/动态失效/fallback，再根据旧六job B/C约171.5秒基线安排实际执行长路。尚未启动后续套，不擅占75pilot窗口。本次只有两个自有测试/fixture文件未提交，完整功能片到实际执行验证后再交原hash。

## 逐候选结果

| id | map | A步数（至原door） | B候选门前格 | 起点本身为portal | 结果 |
|---|---:|---:|---|---|---|
|public-v2-yam-mati|100|382|[621, 190]|False|通过|
|public-v2-mati-yam|100|381|[260, 171]|False|通过|
|public-v2-mati-marju|100|673|[548, 637]|False|通过|
|public-v2-marju-mati|100|800|[621, 197]|True|通过|
|public-v2-samgir-yam|100|701|[260, 171]|False|通过|
|public-v2-samgir-mati|100|612|[621, 197]|False|通过|
|public-v2-yam-samgir|100|699|[637, 491]|False|通过|
|public-v2-mati-samgir|100|616|[637, 491]|False|通过|
|public-v2-marinas-kou|100|448|[470, 630]|False|通过|
|public-v2-kou-marinas|100|448|[79, 614]|False|通过|
|public-v2-marinas-saton|100|246|[132, 422]|False|通过|
|public-v2-marinas-doctor|100|268|[327, 633]|False|通过|
|public-v2-samgir-saton|100|582|[132, 422]|False|通过|
|public-v2-samgir-doctor|100|502|[328, 632]|False|通过|
|public-v2-sea-goya|200|109|[98, 426]|True|通过|
|public-v2-jaja-goya|200|530|[99, 426]|False|通过|
|public-v2-tamutamu-goya|200|764|[99, 426]|False|通过|
|public-v2-karutana-goya|200|379|[99, 426]|False|通过|
|public-v2-goya-karutana|200|381|[304, 599]|True|通过|
|public-v2-goya-jaja|200|532|[570, 376]|True|通过|
|public-v2-sea-tamutamu|200|697|[481, 95]|True|通过|
|public-v2-tamutamu-sea|200|668|[174, 403]|False|通过|
|public-v2-karutana-jan|200|1268|[286, 926]|False|通过|
|public-v2-karutana-dragon|200|938|[434, 742]|False|通过|
|public-v2-karutana-wood|200|1060|[396, 820]|False|通过|
|public-v2-karutana-phoenix|200|139|[420, 577]|False|通过|
|public-v2-jaja-karutana|200|526|[304, 599]|False|通过|
|public-v2-karutana-jaja|200|523|[570, 379]|False|通过|
|public-v2-forde-miner|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-forde-golden|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-forde-brothers|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-miner-forde|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-golden-forde|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-brothers-forde|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-forde-jiru|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-jiru-forde|300|—|—|—|no usable A path or no public interior prefix|
|public-v2-forde-blue-cave|5000|16|[46, 19]|False|通过|
