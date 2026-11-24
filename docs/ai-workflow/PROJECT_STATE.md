# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（正式版 1.8.26+120；dev 自测包 1.8.29+123）

- **1.8.26+120 已正式发布收口**（PR `#63` 合入 `7021e47`，`v1.8.26` → `7021e47`，Release `455145659`），五阶段 `1A–5C` 全部交付；详见[验收与发布记录](../reviews/2026-11-23-v1.8.26-五阶段体验升级学期归档与提醒重构验收与发布记录.md)。
- 终版验证：UTC 全量 `1894 passed / 1 skipped`、上海/洛杉矶核心各 `231 passed`、JVM `76`、Lint 0 错误、隔离 MuMu API 32 仪器测试 `112` 项 0 失败；正式双 ABI 包在 MuMu「学习通」保数据覆盖，版本 `1.8.26 (120)`，统计往期下钻 33/33。
- **`dev` 首项预备修复已合入**（`0806fee`）：补齐统计下钻 `LocalRecordFilterSpec.copyWith` / `isStatsScoped` / `resetToAllLocal`、`LocalRecordQuery.query` 的 `statsScoped` 退出及 `LocalRecordsScreen` 横幅学期标签/`didUpdateWidget`（附单元+组件回归），并将 `AssignmentNotificationPublisherTest#unknownTimeNewAssignmentPublishesSilentlyOnSilentChannel` 改为设备本地固定白天 `10:00`；本地门禁（6 文件 75 项、`dart analyze` 0 问题）与隔离 ASCII 目录 `:app:compileDebugAndroidTestKotlin` 通过，全量 CI 与实机 `androidTest` 留待后续 PR/发版补齐。
- 已启用[新版三段版本规则](VALIDATION.md#版本号与迭代分级规则)（`dev` 打 MuMu 自测包升 `Z`，正式版一律升 `Y` 归零 `Z`、`Y` 上限 `99`），并定稿 [v1.8.27 首页手动课业混排与发版自动化方案](../plans/2026-11-23-v1.8.27-首页手动课业混排与发版自动化方案.md)（首页手动课业混排 + `androidTest` 隔离脚本 + 波次 C-1，波次 B-2/C-2 暂缓）；详见[交接文档](handoffs/2026-11-23-v1.8.26-发版收口与下一轮起点交接.md)。
- **首页混排阶段通过代码 Gate（`700f95f`）与 MuMu 自测（`0604293`）**：`1.8.27+121` 已在 MuMu「学习通」保数据验证同日混排、逾期置底与手动置顶/拖拽、无截止待办、完成撤销、统计隔离、日历及精确闹钟。详见 [dev 本地状态](DEV_STATE.md)。
- **Stage 1 与 Gate 已收口，`1.8.28+122` 自测包通过**：[v1.8.28 置顶持久化与隔离设备仪器测试方案](../plans/2026-11-24-v1.8.28-置顶持久化与隔离设备仪器测试方案.md) 修复 `_savePins` 拒写误报（`ef0e39a`）并扩项隔离通道夹具/脚本 UTF-8（`3de0f59`）；隔离 MuMu API 32 `127.0.0.1:16384` 实跑 112 项得 110 通过/2 假设跳过/0 失败。Gate 通过后升版 `1.8.28+122` 并在 MuMu「学习通」`127.0.0.1:16448` 保数据实测（置顶/拖拽重启持久化、逾期置底与置顶、完成撤销、统计与日历、提醒页），详见 [dev 本地状态](DEV_STATE.md)。
- **v1.8.29 增量 Gate 通过，`1.8.29+123` 自测包通过**：Gate 于 `e915990` 通过（0 阻断），版本提交 `87a4207`；从该提交干净 ASCII 镜像、本机缓存 `--no-pub` 构建原签名双 ABI APK，MuMu「学习通」`127.0.0.1:16448` 保数据覆盖后 `firstInstallTime` 保留、设备 APK 哈希一致；纯离线冒烟 0 线上请求成功（阻断 UID 10042 出站 6 包），登录态/40 门课程/首页课业、混排与置顶、提醒页及关于我们 `1.8.29 (123)` 均正常，logcat 0 条 `FATAL/FlutterError/RenderFlex overflowed`。详见 [dev 本地状态](DEV_STATE.md)；`docs/plans/` 保持 3 份。
- **`1.8.29+123` 完整功能回归通过（2026-11-24）**：主实例 `127.0.0.1:16448` 保数据完成首页混排/双向排序与逾期置底/筛选/搜索/置顶拖拽持久化/完成撤销/手动待办增删、详情与提醒状态、日历月周与议程、统计 24/39 与往期 33/41 下钻及关注恢复、提醒权限与测试通知、更新检查、40 门课程/42 条通知/桌面小组件与双击返回退出；全程仅集中刷新 1 次（扫描 38 门，跳过往期/归档 2 门）。隔离 `127.0.0.1:16384`（API 32）完成 1.7.3→`1.8.29` 原地升级、清数据首启、登录校验/协议页、精确闹钟拒绝降级与渠道重建；主/隔离 0 条 App `FATAL/FlutterError/RenderFlex`（仅 `uiautomator` 工具自身退出 SIGSEGV）。非阻断问题：关于对话框按钮为英文、夜间静音个人日程触发首页全局「提醒或小组件需要处理」提示，证据在 `D:\campus-tools\build-work\cx1829-full-regression-20261124-212529`。下一步按 ROADMAP 规划 `v1.8.30`。
- **`v1.8.30` 设备矩阵补齐（2026-11-24）**：新建 API 26/30/31/33/34 隔离 AVD，复用同源 APK 跑 4 批 116 项，0 失败（111/111/112/114/115 通过，其余假设跳过），均 Doze `IDLE → reset`；修复 androidTest 在 API 26 的 `SQLiteOpenHelper.use` 与渠道重要性兼容。证据见 [dev 本地状态](DEV_STATE.md)。

## 最近 2 个正式发布版本

- **1.8.26+120（当前正式版，2026-11-23）**。PR #63 合入 `7021e47`，`v1.8.26` 指向 `7021e47`。五阶段体验升级：视觉/返回、本机有序置顶/手动截止/本机完成、完整 `FB-008` 学期归档与精选同步、夜间静音/三档预设/v2 有声渠道、日历/考前条/复制/桌面小组件。Gitee `manual` 为 `1.8.26+120`，`stable` 为 `1.8.0+67`，本版未上传 Gitee APK 镜像。[验收与发布记录](../reviews/2026-11-23-v1.8.26-五阶段体验升级学期归档与提醒重构验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.26)
- **1.8.25+114（2026-11-23）**。PR #62 合入 `233a8b0`，`v1.8.25` 指向 `233a8b0`。统计「未知 1」归类修复（`FB-007`）与 `FB-008` 先期止血、首页/日历/记录懒加载、缺年改期锚点与全仓 `clazzId`、并发写租约、SQLite v7 原生提醒、Cookie/外链/下载安全纵深与工程门禁。[验收与发布记录](../reviews/2026-11-23-v1.8.25-八维治理止血统计修复与底盘加固验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.25)

## 待补证与按需入口

- 隔离 API 26/30/31/32/33/34/35 已覆盖 4 批 22 类 `androidTest` 0 失败（API 26/30/31/33/34 于 2026-11-24 补齐，分别 111/111/112/114/115 通过，其余为假设跳过，均 Doze `IDLE → reset`；API 35 Doze 真实 `IDLE`；API 32 OEM 禁用 Doze 记 `unsupported`）；并修复 androidTest 在 API 26 的 `SQLiteOpenHelper.use` 与渠道重要性断言兼容。物理 OEM 真机手感/后台限流、自然 `9010`、真实改期/`completeTime` 样本仍待补证。
- `3A` 已核实缓存通知模板（`senderName == '学习通知'`）与监听器无班级键；`backclazzdata` 在网 `teacherfactor`/`state`/`isEnd` 字段存在率及真实在线 `2C` 新旧作业详情返回路径待明确样本时顺带核实。
- `FB-002`、自然 `9010`、改期/`completeTime` 与 30 天发布时间/活动性质核实见[反馈台账](../待处理体验反馈.md)；已完成方案归档于[归档方案](../archive/plans/2026-11-22-v1.8.25-产品与体验分期升级方案.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
