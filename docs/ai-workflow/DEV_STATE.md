# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-25 · v1.8.30 Stage 1 完成（M3–M7 本地门禁与原生校验全绿，待 Gate 1）

- 已完成改动：M3 去除文字透明叠加、规范正文与次要字号（`LXGW WenKai Screen` 权重与行距收口）、将红色（`berry`）严格收敛至逾期与错误/销毁操作，同步调整 `CourseworkStatusPill`、首页卡片与日期组标题；M4 接入 `flutter_localizations` 固定 `zh_CN` 兜底「关于/日期选择器」中文化、补齐文楷字体与 `IntrinsicHeight` 等高细节按钮；M5 取消日历繁忙红框底色与今日外环，改为按类型着色圆点（作业 `accent`、考试 `examOrange`、待办 `todoGreen`）及图例，并修复 `AssignmentListScreen` 在叠加搜索/筛选时错误展示 `selectedCourseIdle` 的问题；M6 新增 `ManualEntryDetailScreen` 与 `/assignments/manual/:id(/edit)` 路由及 `p:<id>` 深链，统一「待办/考试 + 自己添加」文案与备注摘要露出，并按 D13 分离夜间静音项级提醒与全局告警；M7 迁移 `personal_schedule_v2` 显式有声/振动通知渠道并安全退役旧 `personal_schedule`，在 `MainActivity` 暴露 `AudioManager.ringerMode` 与系统勿扰状态到提醒页健康警示、新增「测试待办提醒」及系统通知设置入口。
- 当前 commit 与状态：Stage 1 `M3–M7` 待提交，L0 共 `60 <= 80` 行；M3/M4（71 项）、M5（46 项）、M6（95 项）、M7（156 项 Flutter + 全套 Python + `dart analyze` 0 问题）与隔离 ASCII 目录 `D:\campus-tools\build-work\cx1830-m7-gradle\local_app` Gradle `:app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :app:lintDebug`（0 错误）全部通过；M3 基准对比数据位于 `D:\campus-tools\build-work\cx1830-m3`。
- 下一步待办：提交推送 `dev` 并执行 Gate 1（Standards + Spec 双路并发审查）至 0 阻断；随后归档超限旧计划、推进 `v1.8.31` 待办附件方案与实现（Gate 2），最后按维护者指令直接冻结正式版 `1.8.31+124` 经 PR/CI、MuMu + 真机双端实测与 GitHub Release 收口。

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

## 2026-11-24 · 1.8.29+123 完整功能回归通过（主实例保数据 + 隔离破坏性）

- 已完成改动：对 `1.8.29+123` 原包（SHA-256 `0749a144…`）在 MuMu「学习通」`127.0.0.1:16448` 完成完整回归：首页混排与双向排序/逾期置底、筛选/搜索、置顶拖拽及冷启持久化、完成撤销、手动待办增删、详情/提醒状态、日历月周与议程、统计 24/39 与往期 33/41 下钻及关注恢复、提醒权限与测试通知、更新检查、40 门课程/42 条通知/桌面小组件与双击返回；仅集中线上刷新 1 次（扫描 38 门，跳过往期/归档 2 门）。隔离 `127.0.0.1:16384`（API 32）完成 1.7.3→`1.8.29` 原地升级、清数据首启、登录校验/协议页、精确闹钟拒绝降级与通知渠道重建。
- 当前 commit 与状态：回归基线 `711d835`；主实例 `firstInstallTime`、登录态、40 门课程与 80 条记录保持，临时条目/置顶/主题/提醒 3 条/统计关注均已恢复；主/隔离 0 条 App `FATAL/FlutterError/RenderFlex`（仅 `uiautomator` 工具自身退出 SIGSEGV）。证据在 `D:\campus-tools\build-work\cx1829-full-regression-20261124-212529`；非阻断问题：关于对话框按钮英文、夜间静音个人日程导致首页持续显示「提醒或小组件需要处理」，另有一条考试通知详情疑似重复待样本核对。
- 下一步待办：按 [ROADMAP](../ROADMAP.md#dev-下一阶段) 规划 `v1.8.30`；`docs/plans/` 保持 3 份现状，正式发版仍待维护者指令（目标 `1.90.0`）。

