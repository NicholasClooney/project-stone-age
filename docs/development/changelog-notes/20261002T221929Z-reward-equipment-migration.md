---
subject: "fix(items): restore reviewed reward equipment and validate worn save UIDs"
title: "补齐母亲发饰普通属性与旧奖励装备兼容"
---

- 母亲的发饰按原饰物类型使用现有饰物槽，魅力加2；不增加装备槽或魔法效果。
- 旧存档里尚未穿戴、仅作为任务物品保存的龙之枪、龙的魅力之笛和母亲的发饰，保留物品UID并补原始耐久。已有正数磨损不会被修复。
- 修正读取JSON数字时已穿戴UID的识别，拒绝已穿戴但零耐久的无效存档记录，不把它作为旧任务物品修复。存档格式不变。
