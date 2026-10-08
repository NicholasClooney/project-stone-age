---
subject: "test(quests): reject failed runs in natural loot acceptance"
title: "自然刷物验收严格区分失败运行"
---

- 自然验收被动保留真实E1观察对象；任何initial_failure记录（包括已持久关闭）或观察对象替换均判失败，不能在到期边界冒充正常零命中。
- 仅加强失败分类，不改变预算、RNG或生产；正常满预算零命中仍为TARGET_UNPROVEN。
- 本片不代表自然验收通过：旧UNCOMPLETE保留，P3与2760自然证明仍未完成，未重开自然窗口。
