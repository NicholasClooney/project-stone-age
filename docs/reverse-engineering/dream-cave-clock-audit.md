# 梦幻洞窟原时间门最小公共需求

此页保留交给公共底座owner的原绑定审计；现已由公共Clock和TimeMan片实现，梦幻内容复用同一实现。当前验收见 `dream-cave-source-audit.md`。

## 时钟

`gmsv/handletime.c:9–12,55–71`：`era=912766409+5400=912771809`；`lsseconds=t-era`；游戏日5400真实秒、每日1024小时、每年100日。`hour=(int)(lsseconds % 5400)*1024/5400`，C有符号除法截断趋零，余数与被除数同号；现代正epoch可用非负整数计算。测试须包括era、era±1、一天边界以及各临界小时，不使用24小时制或自造相位。NowTime包含服务器DEBUG_ADJUSTTIME；正常运行默认为0。

`getLSTime`：700<h<=930为MORNING；200<h<=300为EVENING；300<h<=700为NIGHT；其他为NOON。枚举NIGHT=0/MORNING=1/NOON=2/EVENING=3。

## 四个TimeMan真实绑定

`genout/mugendungeon.create`：400(95,120)原graphic16203、(98,120)原16202，均change_no16200。
`genout/mugendungeon2.create`：400(85,102)原16202、(88,102)原16201，均change_no16204。
脚本分别为`genout/tman_400_<x>_<y>`；均time:AFTER。`npc_timeman.c:38–50,174–195` AFTER边界born126/dead300，严格 **126<h<300**：保留原graphic且mode0/main_msg；其他时间用change_no且mode1/change_msg。不能按对白“太阳”替换成getLSTime的白昼范围。原Watch收到玩家活动才更新，无自动每秒Loop；应统一可信服务器时钟投影避免客户端伪造。

## 真正传送门（与TimeMan图像条件不同）

`mugendungeon.create`：400(97,119)→41(11,8)后缀A；400(98,119)/(97,120)/(96,119)→41(11,8)后缀M。返回41(11,8)→400(97,120)无后缀，原create有重复同向绑定，可去重但不能换坐标。
`mugendungeon2.create`：400(87,101)→42(11,8)后缀N；返回42(11,8)→400(87,101)无后缀。

`npc_warp.c:77–106`解析后缀并设置CHAR_WORKEVENTTYPE；`NPC_TimeWarpCheck(mode1)`在当前gmsv没有调用，且其LS枚举与CHAR_EVENT枚举不同，不能直接把这条死代码作为运行条件。原客户端`system/map.cpp`的`_checkWarpEvent`实际检查：M只MORNING，A是NOON **或EVENING**，N只NIGHT。因此正常原玩法A在h<=300或h>930；M在700<h<=930；N在300<h<=700。

起始审计时`tools/import_world.py:read_portals`丢弃后缀；现公共时间门片保留源后缀并据受审MapWarpPoint记录附加requires_time，服务器走路和到达使用同一时钟复验，不注册无条件入口。

## 碰撞与安全导航

TimeMan更换图像的C分支没有写CHAR_ISOVERED、坐标或传送目标；四个NPC始终在各自原点，不能因mode变化移动NPC或另造一道墙。`char_walk.c:280–289`依CHAR_ISOVERED判NPC格碰撞；npc_warp初始化独立将自身ISOVERED设1。TimeMan不与上述传送格重合，故更换图像本身不是传送许可，A/M/N才是正常客户端门条件。须结合地图真实阻挡/对象层验证入口侧可走路径，测试四NPC格与五传送格在边界模式下均不变几何关系。

助手不得直接导航到41/42内仙人绕入口与终战；应按当前可信位置/区域展示阶段并从外部到合法入口侧，原时间门必须亲自通过。完整地图/谜题/终战来源另在任务manifest审核，第三次交先见之光才写34。

## 已交付的公共范围

1. 单一RealTimeToLSTime/getLSTime纯实现和可注入测试时钟。
2. 严格四实例timeman importer与公开mode/graphic/text投影；不推断其他TimeMan。
3. 五入口的A/M/N字段保留、服务器重验及边界测试；现有无后缀门行为保持。
4. 内容独立helper按实际组件防绕，生产GameScene走门、跨时段回退与四NPC两模式原像素均已定向验证。

## 来源SHA-256

- `gmsv/handletime.c`: `6819b5387b924ca3901d47eee0e8bf434201674fd4780fc3d00525f153f08437`
- `gmsv/include/handletime.h`: `4288f1175e4239608539f29d739edb6c85671abd854bbe7b30cc6b61a6342807`
- `gmsv/npc/npc_timeman.c`: `30d88b9846b8fee9691c1fc61222a4fd14a6224f7b16ba46ef0d8105a7373187`
- `gmsv/npc/npc_warp.c`: `9799d5d3d742e18d0ab5da7799f3365e7acbec8ae754a2a9f8921c18fd561c02`
- `gmsv/include/char_base.h`: `167e0ef3dfc758fd407942110ac4eb3292d94c7f31b6a87fcd3eff98b657a770`
- `gmsv/char/char_walk.c`: `c605f93a1945aef0328d86da25f335f24188db86bb25687b6731ed8b5cc82bc0`
- `gmsv/data/npc/genout/mugendungeon.create`: `2cf197c7aa53b20b0be5a74491ed1d47b748afa12d7d07024042ab91c8d6d893`
- `gmsv/data/npc/genout/mugendungeon2.create`: `45a8edf4f53e9a6c70c0f83a8f633c01b2844247b9cedd83d5a4d9d5faeef6cd`
- `gmsv/data/npc/genout/tman_400_95_120`: `7231a57d18815afe2f5aee27237aa1d24ae697d518eda9892e67e2aef5013e28`
- `gmsv/data/npc/genout/tman_400_98_120`: `7231a57d18815afe2f5aee27237aa1d24ae697d518eda9892e67e2aef5013e28`
- `gmsv/data/npc/genout/tman_400_85_102`: `4878461364b952e749c60258a1bf11b136e7709d4b9fd3f8e96c62f8811b8045`
- `gmsv/data/npc/genout/tman_400_88_102`: `4878461364b952e749c60258a1bf11b136e7709d4b9fd3f8e96c62f8811b8045`

## 当前启用的MapWarpPoint路径（补核）

`gmsv/include/version.h:219`定义`_MAP_WARPPOINT`，故不以被跳过的旧Warp NPC初始化证明运行。`gmsv/data/map/mapwarp.txt:2746–2751,2801–2802`保留上述五入口的A/M/N以及无条件返回；每行与create目标坐标一致。

`map/map_warppoint.c:34–40`从getMapdir()/mapwarp.txt加载；`:211–220`把第二字段M/N/A映射为CHAR_EVENT_WARP_MORNING/NIGHT/NOON；`:100–101`创建OBJTYPE_WARPPOINT且obj.chartype=objtype。`map/readmap.c:916–923`将OBJECT_getchartype写入eventbuf；旧未压缩地图路径`:828–835`也写入对应event层。

参考客户端`references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/system/netproc.cpp:2171–2185`从M包第四字段解析eventstring、a62toi后writeMap；同目录`map.cpp:2955–2976`对event层低12位调用上述_checkWarpEvent检查。它与.tools/legacy/map.cpp相同位置一致。这里证明本地所提供C服务端+8.5客户端源的字段链，不宣称已运行某历史2.5官方binary，也不据此断言所有客户端年代行为一致。
- `gmsv/include/version.h`: `081d634dd5c9f87ff6ce28952c96a2e110b51158daadd52dad15a32972da7d94`
- `gmsv/data/map/mapwarp.txt`: `b7b50f42efa8e5a3f740d49a8d0c01cbf994d1bb66151b16ff5b5e7c14e7595c`
- `gmsv/map/map_warppoint.c`: `79ddaf6792db324351cd17cd774dcdfb25afed0eaf954a07571a13d081189856`
- `gmsv/map/readmap.c`: `287ffda7b2307797759aea937d7ba1aee49d3d1abbfb3c8c12e815528c35dc2e`
- `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/system/map.cpp`: `4606b789e03fcb0b16f3b8e8746e307c77f54cd12d4f4e957502d8f39e7d5a02`
- `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/system/netproc.cpp`: `6a769adcfea283b0cd8c55d1cd2af51fac1a6eb80b8e8a95a09900f5a5ef99b3`
- `references/anson1788-stoneage/石器时代8.5客户端最新源代码/石器源码/system/handletime.cpp`: `684acd1c033efb59e5da493f09f0e995930a6e1410c356cbe3ef541eb7df61ee`
