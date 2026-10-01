---
subject: "fix(client): keep pet lists updating after using a number box"
title: "点过数字框后宠物列表也会更新"
---

- 在同种比较等窗口点过数字框（例如放生门槛）后，窗口不再停止刷新；找宠流程新抓到的宠物会立即出现在宠物列表和同种比较中。
- 只有正在输入文字的两秒内才暂缓刷新，避免清掉正在输入的内容。
