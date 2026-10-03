---
subject: "fix(transmigration): scan all carried pet slots for sacrifices"
title: "转生献宠规则兼容现有随身容量"
---
- 开发验证：献宠规则按全部随身宠物的原顺序选择，兼容项目现有30槽容量，第6至30槽也可选中；实际容量仍由Session校验。
- 保留原C五槽验证，新增30槽默认与UID选择、五转祭品及非法身份测试；生产转生服务尚未由本片开放。
