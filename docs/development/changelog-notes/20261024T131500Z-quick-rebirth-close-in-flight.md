---
subject: "fix(ui): keep quick rebirth outcome when the menu closes mid-confirmation"
title: "快速转生：确认提交后关闭面板也会显示结果"
---

- 快速转生按下「确认」后若立刻关闭人物面板（含手柄 B 键），窗口先隐藏并等待服务器回复，不再静默丢弃结果，也不会对进行中的确认发送取消。
- 回复到达后窗口自动关闭，成功或失败原因显示在画面顶部的提示文字中；未提交确认时关闭行为不变。
