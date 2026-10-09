---
subject: "chore(quests): stage gated doctor first request runner"
title: "博士首请求运行器定向验证完成，仍未开放"
---

- 开发说明：加入默认关闭的博士job6/event15首请求运行器，复用真实无收费路线与原REQUEST；在手动选宠前停止，不串job7、不消耗宠、不接收费D1。公开能力及Policy未开放。
- 私有显式Start与博士对话守卫在安装、保存返回及窗口生成前核对身份；旧返回失效即丢弃，同旧run执行标志在下一tick撤除，不清后继。Session、Hub及收费链保持。
- 保留原手动及false-after语义：磁盘/cache可已提交而内存按false返回回滚，不新增跨文件原子或恢复保证。
- 九套定向测试分窗通过，前四套依赖不变沿用、剩余五套fresh通过。测试逐侧验证token类型/serial/关联和重放后，仅映射比较副本的关联token，保完整profile/宠UID/钱/盘/cache断言。父函数对照运行于候选环境，内部binding、GM宠与无遇敌fixture不代表认证WS或自然验收。
- 旧博士故障fixture的精确抓宠日志WARNING依据协调者基线仅runtime允许一次，raw/console与native分别锁原stack。历史FAIL及监测格式失败保留；未跑full、注册、import、开关开放或重启，集成验证另行进行。
