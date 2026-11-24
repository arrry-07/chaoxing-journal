# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-25 · v1.8.31 Stage 1 + Gate 2 二次返工完成（Semantics/防连点/代理对全通过，待复审收口）

- 已完成改动：在 `9c810ef` 基础上修复 `Gate 2` 增量复审指出的 Major（`manual_attachment_picker_section.dart` 为图片删除与预览 `Semantics(excludeSemantics: true)` 补全 `onTap`/`enabled` 并新增 `SemanticsAction.tap` 断言）及高价值 Minor（`_AttachmentFullscreenViewer.dispose` 同步复位 `_galleryOpening`、`PersonalFileBridge.kt` 用截断前原始扩展名线索猜测 MIME、`ManualAttachmentPathPolicyTest.kt` 补充 UTF-16 代理对截断单测）。
- 当前 commit 与状态：二次返工待提交（前序 `9c810ef` 已推 `origin/dev`），L0 `60 <= 80`；`verify_local_gate.py` 定向门禁（5 组 Flutter 37 项 + 9 组 Python + `dart analyze` 0 问题）与隔离 ASCII Gradle `:app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :app:lintDebug --rerun-tasks`（`cx1831-gradle`）全部通过。
- 下一步待办：提交推送本轮返工并完成 `Gate 2` 最终复审 0 阻断通过；随后冻结并直发正式版 `1.8.31+124`（PR/CI + MuMu/真机双端验收 + Release 与归档）。

## 2026-11-25 · v1.8.30 Stage 1 + Gate 1 返工完成（24 文件 282 项与全套校验全绿，待 Gate 1 复审）

- 已完成改动：在 `946a179` 基础上完成 Gate 1 双轴（Axis 1 Standards + Axis 2 Spec）全部阻断、中级及关键次要项返工：`LocalNotificationService` 改为仅在 `migrateLegacyManualChannelIfNeeded` 确认创建 `personal_schedule_v2` 且重排 `p:` 闹钟后再安全退役旧 `personal_schedule`（并兼容无宿主插件测试的 `MissingPluginException`/`UnimplementedError`/`LateInitializationError`），清理 `reminderWindowMissed` 对全局 `lastWarning` 污染、`showTest`/`showTestManual` 捕获 `StateError` 并统一 `_clock()`；`AssignmentStore` 拆分 5 路子系统告警桶、`hasWidgetWarningOnly`/`hasNonQuietServiceWarning`、`manualSaveWarnings` 与 `saveFeedback(warnings:)`，防止保存待办弹出无关全局 SnackBar；`AssignmentDetailScreen` 截止预警横幅与 `AssignmentChangesScreen` 截止变更徽章收敛为 `ochre`，`ManualHomeCard` 按需诚实显示夜间静音/不足 30 分文案、`ReminderSettingsScreen` 补全 `manualChannel` 音振诊断与 `personal_schedule_v2` 用户偏好重置说明；`AssignmentListScreen` 修复 `_courseCountsFor` 覆盖完整目录、空课兜底与考试快捷新建；`AppDeepLinks` 支持 `/assignments/manual/:id` 登录后回跳，补全 `JournalPalette.==`/`hashCode`；`v1.8.30` 方案补充 §11 M1 诊断、M3 对比度及 D14 披露。
- 当前 commit 与状态：Stage 1 返工待提交（前序 `946a179` 已推 `origin/dev`），L0 共 `60 <= 80` 行；`dart analyze lib test` 0 问题、全部 9 组 Python 单测通过、24 个定向 Flutter 测试（282 项）全绿；前序 ASCII Gradle `:app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :app:lintDebug`（`cx1830-m7-gradle`）与 M3 对比基准（`cx1830-m3`）已留档。
- 下一步待办：提交推送本轮 Gate 1 返工并执行定向 Gate 1 增量复审至 0 阻断；随后归档超额旧计划、落盘并实施 `v1.8.31` 待办附件（先改存储格式向后兼容，后接原生桥与 UI/生命周期清理 + Gate 2），最后按维护者授权直发正式版 `1.8.31+124`（PR/CI + MuMu/真机双端实测 + Release 与归档）。

## 2026-11-25 · v1.8.30 M1 通知诊断 + M2 筛选

- 已完成改动：M2 类型筛选新增「待办」（作业/考试不再混入手动待办）；课程候选并入本学期完整目录，按条目数排序、无课业写「暂无」；入口改为无图标「课程 ▾」行加 × 清除；选中空课程显示「这门课暂无作业和考试」并可一键为该课添加待办（预填课程）。M1 真机 CDY-AN00（API 29，1.8.24）只读诊断：各渠道均有默认提示音，系统 `mode_ringer=1` 振动模式静音通知流，判定分支 (d)。
- 当前 commit 与状态：定向 10 个测试文件全绿、`dart analyze` 0 问题；旧 JSON 读到未知类型回落「全部」已加回归。证据 `D:\campus-tools\build-work\cx1830-m1`。
- 下一步待办：M3 可读性与红色收敛 → M4 字体/本地化/按钮 → M5 日历 → M6 待办详情 → M7 通知（铃声模式提示 + 个人渠道 v2 + 测试待办提醒）→ v1.8.31 附件。

## 2026-11-24 · v1.8.30 体验反馈代码审查与规划（仅文档）

- 已完成改动：对照代码审查维护者 2026-11-24 反馈（筛选、可读性、红色、字体、日历、待办、附件、通知声音、云同步），新增 [v1.8.30 方案](../plans/2026-11-24-v1.8.30-筛选可读性日历与待办详情体验方案.md)，并同步 ROADMAP、反馈台账 FB-009–FB-015 和工程状态；附件排到 `v1.8.31`，WebDAV 云同步放中长期。
- 当前 commit 与状态：只改文档，未改源码、版本或签名；关键结论：`muted` 对比度约 7:1，「淡」要先测量；日历红框是繁忙底色；课程候选只取有课业的课程；通知无声根因要真机 `dumpsys` 判断。
- 下一步待办：等维护者拍板启动 v1.8.30 Stage 1，先做 M1 真机通知诊断；`docs/plans/` 现有 4 份，超过「最多两份」，`v1.8.27–v1.8.29` 三份待 `1.90.0` 发布收口时归档。

## 2026-11-24 · v1.8.30 设备矩阵补齐：API 26/30/31/33/34 全绿

- 已完成改动：为 `v1.8.30` 设备矩阵新建 API 26/30/31/33/34 隔离 AVD，复用 `1.8.29` 同源 debug/androidTest APK 跑 4 批 22 类 116 项；修复 androidTest 的 minSdk 26 兼容（`ReminderSourceScopeTest`/`ReminderDatabaseMigrationTest` 去掉 `SQLiteOpenHelper.use` 改 `try/finally`，`AssignmentNotificationPublisherTest` 的 v1 渠道断言改为「ensureChannels 不改变既有重要性」并加删除等待）。
- 当前 commit 与状态：API 26/30/31/33/34 分别 111/111/112/114/115 通过、0 失败（其余为 API/环境假设跳过），均 Doze `IDLE → reset`；API 32/35 沿用 `1.8.29` 证据（111 通过/5 跳过 与 115 通过/1 跳过）。日志在 `D:\campus-tools\build-work\androidtest-api{26,30,31,33,34}-20261124.log`；仅测试代码变更，未改 App 源码/版本/签名，未新建预览包。
- 下一步待办：物理 OEM 真机只读体检需设备授权；回归发现的两个 UI/文案问题仍待下一轮产品收口，正式发版仍等维护者指令。

