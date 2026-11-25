# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-25 · v1.8.32 规划落盘（本学期筛选、卡片视觉与待办交互优化，仅文档）

- 已完成改动：基于 `1.8.31+124` 基线（`7bf6253`）与维护者截图/交互反馈，落盘 [v1.8.32 方案](../plans/2026-11-25-v1.8.32-本学期筛选卡片视觉与待办交互优化方案.md)（`M1`–`M6` 元步骤级规格）：明确课程筛选「本学期 / 未分组 / 往期 / 全部学期」与增量新作业证据、暖琥珀逾期色板去红降噪与首页待办卡重构（隐藏正常提前提醒、保留「自己添加」、倒计时收左轨、柔和备注块）、待办详情备注齐平头部与行对齐、「个人待办与考试」左右滑与已完成折叠区，以及「我的」入口重组（保留外置外观与关于 5 项、同步页内联后台检查、首页顶栏 `待办` 入口）。
- 当前 commit 与状态：仅更新计划与状态文档，未改源码、测试或版本标识；`AGENTS.md` + `PROJECT_STATE.md` <= 80 行，`docs/plans/` 仅保留 1 份活跃方案。
- 下一步待办：由执行模型执行 `docs/plans/2026-11-25-v1.8.32-本学期筛选卡片视觉与待办交互优化方案.md` 的 Stage 1（`M1`–`M6`），完成后停机等待 Gate 独立审查。

## 2026-11-25 · v1.8.31 (1.8.31+124) 正式发布收口（main 与 dev 已同步）

- 已完成改动：PR `#64` 合入 `main`（`77b5e8a`）并通过 PR CI（`45482517564`）、`main` CI（`45485091357`）与 Tag `v1.8.31`（`642cb62`）CI（`45490635594`）；构建干净原签名双 ABI 正式包 `chaoxing-journal-1.8.31.apk`（`63,683,210` 字节，SHA-256 `08fc94ecf42d83576902f838b8cd15141b1f889ab5f3928a3853ab9102fe7818`）并在 MuMu `127.0.0.1:16448`（API 35）与华为实体机 `MKB4C20605047402`（`CDY-AN00`，API 29）双端完成保数据覆盖升级、M2–M7、真机/模拟器拍照+相册 PNG+PDF 挂载与外部打开及零崩溃清理验证，正式发布 GitHub Release `457363482` 并通过公开匿名下载与 `site-release-dispatch` / `gitee-release-sync`（线上 `update-manual.json=1.8.31+124`）。
- 当前 commit 与状态：完成 `v1.8.30` / `v1.8.31` 方案、`v1.8.26` 交接与 `v1.8.25` 验收归档及全套收口文档同步，`main` 与 `dev` 树一致（保留未追踪本机材料与 `.ai/`）。
- 下一步待办：下一轮 `dev` 从干净正式基线 `1.8.31+124` 起步，可按需规划 `FB-015` WebDAV 跨设备云同步或真实样本补证。

## 2026-11-25 · v1.8.31 Stage 2 正式冻结完成（Gate 2 终审 0 阻断通过，1.8.31+124 待提 PR 与双端验收）

- 已完成改动：基于 `Gate 2` 增量终审 `930175d1` 对 `7e730f5` 返回 **PASS（0 阻断 / 0 中级 / 0 次要）** 后，授权扩展 `check_release_metadata.py` 与 `freeze_release.py`（及对应 Python 单测）支持维护者显式冻结 `1.8.31+124` 正式补丁版（保持未冻结 `dev` 拒过、前导零与 `minor <= 99` 门禁不变）；更新 `CHANGELOG.md`（汇总 `v1.8.27`–`v1.8.31` 交付并明确披露 `personal_schedule_v2` 渠道迁移及加密备份不含本地附件），运行 `freeze_release.py --apply --mode formal --version 1.8.31+124` 同步版本标识，并顺带修复全量 `TZ=UTC` 回归暴露的 `assignment_list_screen.dart` 360dp 紧凑按钮宽度及 `v1830_manual_detail_m6_test.dart` 时区无关本地时间断言。
- 当前 commit 与状态：冻结变更待提交（前序 `7e730f5` 已推 `origin/dev`），L0 `60 <= 80`；`freeze_release.py --check --mode formal --previous 1.8.26+120`、`check_release_metadata.py` 与 `TZ=UTC` 全套 `--release --mode full` 门禁（Flutter 1977 passed / 0 failed / 1 opt-in benchmark skipped、9 组 114 项 Python 单测与 `dart analyze` 0 问题）全部通过。
- 下一步待办：完成全套门禁并提交推送 `dev` 后，提 PR `dev -> main`、跑通 PR CI 与审计并合入 `main`，构建干净签名的 `chaoxing-journal-1.8.31.apk` 在 MuMu `127.0.0.1:16448` 与物理真机 `MKB4C20605047402` 双端保数据验收通过后发布 `v1.8.31` 正式 Release 并收口归档。

## 2026-11-25 · v1.8.30 Stage 1 + Gate 1 返工完成（24 文件 282 项与全套校验全绿，待 Gate 1 复审）

- 已完成改动：在 `946a179` 基础上完成 Gate 1 双轴（Axis 1 Standards + Axis 2 Spec）全部阻断、中级及关键次要项返工：`LocalNotificationService` 改为仅在 `migrateLegacyManualChannelIfNeeded` 确认创建 `personal_schedule_v2` 且重排 `p:` 闹钟后再安全退役旧 `personal_schedule`（并兼容无宿主插件测试的 `MissingPluginException`/`UnimplementedError`/`LateInitializationError`），清理 `reminderWindowMissed` 对全局 `lastWarning` 污染、`showTest`/`showTestManual` 捕获 `StateError` 并统一 `_clock()`；`AssignmentStore` 拆分 5 路子系统告警桶、`hasWidgetWarningOnly`/`hasNonQuietServiceWarning`、`manualSaveWarnings` 与 `saveFeedback(warnings:)`，防止保存待办弹出无关全局 SnackBar；`AssignmentDetailScreen` 截止预警横幅与 `AssignmentChangesScreen` 截止变更徽章收敛为 `ochre`，`ManualHomeCard` 按需诚实显示夜间静音/不足 30 分文案、`ReminderSettingsScreen` 补全 `manualChannel` 音振诊断与 `personal_schedule_v2` 用户偏好重置说明；`AssignmentListScreen` 修复 `_courseCountsFor` 覆盖完整目录、空课兜底与考试快捷新建；`AppDeepLinks` 支持 `/assignments/manual/:id` 登录后回跳，补全 `JournalPalette.==`/`hashCode`；`v1.8.30` 方案补充 §11 M1 诊断、M3 对比度及 D14 披露。
- 当前 commit 与状态：Stage 1 返工待提交（前序 `946a179` 已推 `origin/dev`），L0 共 `60 <= 80` 行；`dart analyze lib test` 0 问题、全部 9 组 Python 单测通过、24 个定向 Flutter 测试（282 项）全绿；前序 ASCII Gradle `:app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :app:lintDebug`（`cx1830-m7-gradle`）与 M3 对比基准（`cx1830-m3`）已留档。
- 下一步待办：提交推送本轮 Gate 1 返工并执行定向 Gate 1 增量复审至 0 阻断；随后归档超额旧计划、落盘并实施 `v1.8.31` 待办附件（先改存储格式向后兼容，后接原生桥与 UI/生命周期清理 + Gate 2），最后按维护者授权直发正式版 `1.8.31+124`（PR/CI + MuMu/真机双端实测 + Release 与归档）。

## 2026-11-25 · v1.8.30 M1 通知诊断 + M2 筛选

- 已完成改动：M2 类型筛选新增「待办」（作业/考试不再混入手动待办）；课程候选并入本学期完整目录，按条目数排序、无课业写「暂无」；入口改为无图标「课程 ▾」行加 × 清除；选中空课程显示「这门课暂无作业和考试」并可一键为该课添加待办（预填课程）。M1 真机 CDY-AN00（API 29，1.8.24）只读诊断：各渠道均有默认提示音，系统 `mode_ringer=1` 振动模式静音通知流，判定分支 (d)。
- 当前 commit 与状态：定向 10 个测试文件全绿、`dart analyze` 0 问题；旧 JSON 读到未知类型回落「全部」已加回归。证据 `D:\campus-tools\build-work\cx1830-m1`。
- 下一步待办：M3 可读性与红色收敛 → M4 字体/本地化/按钮 → M5 日历 → M6 待办详情 → M7 通知（铃声模式提示 + 个人渠道 v2 + 测试待办提醒）→ v1.8.31 附件。

