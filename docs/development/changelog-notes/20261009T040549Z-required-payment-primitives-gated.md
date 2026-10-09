---
subject: "chore(fees): stage closed required payment primitives"
title: "200/300 必需费用原语验证完成，仍未开放"
---

- 开发说明：加入精确200永久许可与300赛姆扣款及Warp原语，无生产授权发放方或执行caller，收费开关仍关闭；不开放自动路线。
- 自动事实使用独立automatic_required校验，沿用金额、余额、owner、source及交易字段；原A手动校验与writer保持，不加run/step/UID或schema。
- 夜间决定，待用户确认：独立D保护延伸手动保存不阻塞规则的未知IO异常例外，仅真实IO进入后无法确认结果时保护原Session/owner/account/path。包括共享Session物理守卫及Backend保存/三sidecar守卫；退出切换不阻，失败或warm加载与run退休不解除，真实核准加载才解除，不借C权限或自动修盘。
- 原UI拒绝把自动事实当手动typed fact；既有text fallback仍可能显示文字或清空提示，没有手动去重和owner过滤。
- 定向19套跨窗通过：交易套沿用依赖未变的check/runtime证据，余18套本窗通过；修正测试缩进和一个字段错名，历史FAIL/盘保留。未执行full、注册、import或开放开关，其余映射留协调者集成验证。
- 边界：JSON profile，Session旧path连续三读非逐读CAS，无跨文件原子/跨进程自动重试；父函数对照位于候选环境，内部binding及battle便利fixture不代表完整路线或认证WebSocket。
