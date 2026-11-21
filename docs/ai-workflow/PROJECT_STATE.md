# 当前工程状态

<a id="dev-当前迭代进度"></a>

## dev 当前迭代进度（1.8.24-dev）

- [x] Android 构建工具链与噪音治理：升级 Gradle 8.14.2 / AGP 8.11.1 / Kotlin 2.2.20、迁移 Kotlin `compilerOptions` DSL 并设置 `kotlin.incremental=false` 根治跨盘符缓存异常，核实 `lib/` 零 `CupertinoIcons` 引用；下一轮预览从 `1.8.24-dev.1+103` 起步。

按独立改动随代码更新对应进度；当前无活跃交接或待执行计划。

## 最近 2 个正式发布版本

- **1.8.23+102（当前正式版，2026-11-22）**。PR #60 合入 `b298dbb`，`v1.8.23` 指向 `b298dbb`。三档主题即时切换、柔和交互音效与短振、未提交随堂练习状态修复、无框恢复顶栏/日历、考试置顶继承与并发加固。Gitee manual 为 `1.8.23+102`，stable 为 `1.8.0+67`，APK 镜像为 `1.7.52+59`。[验收与发布记录](../reviews/2026-11-22-v1.8.23-主题交互与随堂练习状态修复验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.23)
- **1.8.22+89（2026-11-21）**。PR #59，`v1.8.22` 指向 `c0ab249`。课业置顶与自动退顶、未逾期待交项七天分层、首页短日期。Gitee manual 曾发至 `1.8.22+89`。[验收与发布记录](../reviews/2026-11-21-1454-1.8.22课业置顶与时间轴验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.22)

## 待补证与按需入口

- 查清设备端剩余 2 条「提交未知」归因；落地缺年锚点、异常 Cookie 与 `clazzId` 加固，并取证自然 `9010`、改期及隔离切号/写入通道交错。
- 课程群云历史（FB-002）、真实 30 天发布时间与活动性质、真机听测与 `syncDone` 口径统一及原生音频单测见[反馈台账](../待处理体验反馈.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
