# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（1.8.26+120 已正式发布收口；dev 已按 Gate 返工 1.9.0 Stage 1，待复核）

- **1.8.26+120 已正式发布收口**（PR `#63` 合入 `7021e47`，`v1.8.26` → `7021e47`，Release `455145659`），五阶段 `1A–5C` 全部交付；详见[验收与发布记录](../reviews/2026-11-23-v1.8.26-五阶段体验升级学期归档与提醒重构验收与发布记录.md)。
- 终版验证：UTC 全量 `1894 passed / 1 skipped`、上海/洛杉矶核心各 `231 passed`、JVM `76`、Lint 0 错误、隔离 MuMu API 32 仪器测试 `112` 项 0 失败；正式双 ABI 包在 MuMu「学习通」保数据覆盖，版本 `1.8.26 (120)`，统计往期下钻 33/33。
- **`dev` 已合入 1.9.0 首项预备修复**（`0806fee`）：补齐统计下钻 `LocalRecordFilterSpec.copyWith` / `isStatsScoped` / `resetToAllLocal`、`LocalRecordQuery.query` 的 `statsScoped` 退出及 `LocalRecordsScreen` 横幅学期标签/`didUpdateWidget`（附单元+组件回归），并将 `AssignmentNotificationPublisherTest#unknownTimeNewAssignmentPublishesSilentlyOnSilentChannel` 改为设备本地固定白天 `10:00`；本地门禁（6 文件 75 项、`dart analyze` 0 问题）与隔离 ASCII 目录 `:app:compileDebugAndroidTestKotlin` 通过，全量 CI 与实机 `androidTest` 留待后续 PR/发版补齐。
- 已启用[新版三段版本规则](VALIDATION.md#版本号与迭代分级规则)（`dev` 打 MuMu 自测包升 `Z`，正式版一律升 `Y` 归零 `Z`、`Y` 上限 `99`），并定稿 [v1.9.0 详细执行方案](../plans/2026-11-23-v1.9.0-首页手动课业混排与发版自动化方案.md)（首页手动课业混排 + `androidTest` 隔离脚本 + 波次 C-1，波次 B-2/C-2 暂缓）；详见[交接文档](handoffs/2026-11-23-v1.8.26-发版收口与下一轮起点交接.md)。
- **1.9.0 Stage 1 已按 Gate 返工（待复核）**：修复 `displayAt` 时间信任与 Tier 1 越界、`reorderPinned` 筛选子集、首页空态/筛选/置顶重排及 `assignment_list_screen.dart` 抽离（净减 22 行）、`manual_agenda_screen` 删除守卫、`androidTest` 全限定类名与崩溃判错、`freeze_release.py` dev/formal 双模式与 CRLF 保留；`assignment_store.dart` 净增 40 行（≤45）；版本仍 `1.8.26+120`，未改 `pubspec`、Tag 或 Release。
- **Gate 增量返工待复审**：补齐真实切号断言与常规字号卡片避让，修复置顶保存跨时间边界、无课名展示、缺年考试置顶排序和仪器测试中断判错。检查结果与复审范围见 [dev 本地状态](DEV_STATE.md)。

## 最近 2 个正式发布版本

- **1.8.26+120（当前正式版，2026-11-23）**。PR #63 合入 `7021e47`，`v1.8.26` 指向 `7021e47`。五阶段体验升级：视觉/返回、本机有序置顶/手动截止/本机完成、完整 `FB-008` 学期归档与精选同步、夜间静音/三档预设/v2 有声渠道、日历/考前条/复制/桌面小组件。Gitee `manual` 为 `1.8.26+120`，`stable` 为 `1.8.0+67`，本版未上传 Gitee APK 镜像。[验收与发布记录](../reviews/2026-11-23-v1.8.26-五阶段体验升级学期归档与提醒重构验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.26)
- **1.8.25+114（2026-11-23）**。PR #62 合入 `233a8b0`，`v1.8.25` 指向 `233a8b0`。统计「未知 1」归类修复（`FB-007`）与 `FB-008` 先期止血、首页/日历/记录懒加载、缺年改期锚点与全仓 `clazzId`、并发写租约、SQLite v7 原生提醒、Cookie/外链/下载安全纵深与工程门禁。[验收与发布记录](../reviews/2026-11-23-v1.8.25-八维治理止血统计修复与底盘加固验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.25)

## 待补证与按需入口

- `androidTest` 本轮已在隔离 MuMu API 32 执行 112 项、0 失败；API 33+/OEM 真机提醒矩阵、隔离切号/退出小组件复验仍按需补证；CI 目前仅编译 `androidTest`。
- `3A` 已核实缓存通知模板（`senderName == '学习通知'`）与监听器无班级键；`backclazzdata` 在网 `teacherfactor`/`state`/`isEnd` 字段存在率及真实在线 `2C` 新旧作业详情返回路径待明确样本时顺带核实。
- `FB-002`、自然 `9010`、改期/`completeTime` 与 30 天发布时间/活动性质核实见[反馈台账](../待处理体验反馈.md)；已完成方案归档于[归档方案](../archive/plans/2026-11-22-v1.8.25-产品与体验分期升级方案.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
