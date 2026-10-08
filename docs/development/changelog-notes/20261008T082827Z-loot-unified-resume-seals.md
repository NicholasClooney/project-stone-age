---
subject: "fix(server): unify loot resume seals and bounded failure exits"
title: "刷物内部续封与受限失败退场"
---

- 刷物入口仍关闭；仅原outer-process resume的同内容、单次成功writer可续封当前initial或C1票据，保持原预算与已结算收益。
- 失效时按当前执行、原close与续封的各自权限受限退出；旧调用不触后继，preclose外来scope不借后继权限close。
- writer claim只读拒绝不构成对称全局互斥；capture拒绝后原普通save仍可令旧fee claim失效。
- 开发验证：内部65例组合与六项定向回归通过；测试便利不代表自然P3或2760掉落已证明，历史自然UNCOMPLETE保留。
