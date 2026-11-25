# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-25 · 研发流程与本地门禁四项提效优化（工具脚本 + 规则文档）

- 已完成改动：落地四项本地门禁与 `/goal` 闭环提效优化并完成双轴代码审查返修加固：① [verify_local_gate.py](../../scripts/verify_local_gate.py) 为 Flutter 单测接入默认 `--timeout 30s`（`--test-case-timeout none` 正确透传禁用）与外层进程树超时熔断（quick 300s / full 900s，锁保护 ANSI/`\r` 逐帧解析并回显最后卡住的用例，覆盖超时与 `KeyboardInterrupt` 全进程树清理），回归见 [test_verify_local_gate.py](../../scripts/test_verify_local_gate.py)；② [run_android_tests.py](../../scripts/run_android_tests.py) 新增 `--local-fast` 持久化 ASCII 白名单增量镜像快检（仅同步 `android/`/`lib/`/`assets/`/`pubspec*`/`analysis_options.yaml`、拦截源/目标目录重叠或嵌套、以成功后落盘的 SHA-256 `pubspec+SDK` 指纹及 `.flutter-plugins-dependencies` 判定按需离线 `flutter pub get`、每次 `pub get` 后重写转义 `android/local.properties` 根除 `[PropertyEscape]`，一次跑通 `:app:testDebugUnitTest` + `:app:compileDebugAndroidTestKotlin` + `:app:lintDebug`），补齐跨平台（Windows/Linux CI 无条件触发）与失败重试回归见 [test_run_android_tests.py](../../scripts/test_run_android_tests.py)；③ 同步更新 [AGENTS.md](../../AGENTS.md)、[VALIDATION.md](VALIDATION.md)、[开发与贡献.md](../guides/开发与贡献.md)、[.agents/rules/skill-routing.md](../../.agents/rules/skill-routing.md) 与全局 `staged-release-gate` 技能，固化标准档体量软上限（≤ 4–5 模块 / ≤ 25–30 文件）、Stage 1 原生快检硬要求与 Gate 3 窄补丁（≤ 10 文件）增量终审。
- 当前 commit 与状态：仅变更门禁脚本、脚本单测与工作流规则文档（未改应用源码、版本 `1.8.33+126`、`main` / Tag / Release 或线上索引），L0 行数 `52 <= 80`，随本提交推送 `origin/dev`。
- 下一步待办：下一轮跨模块迭代按新门禁与体量上限推进，或在维护者明确发出正式发版指令后冻结版本进入 Stage 2 发布流程。

## 2026-11-25 · v1.8.33 (1.8.33+126) 完整 dev 闭环：Stage 1、异构 Gate 终审 PASS 与 MuMu 保数据实测收口

- 已完成改动：通过 `acp-mcp-call delegate_task` 跑完 [v1.8.33 方案](../plans/2026-11-25-v1.8.33-课程过滤更新收敛通知有声与交互精修方案.md) 全部 `M1–M8` 实现（`Gemini 4 Hydrogen high`，`0f6c513`）；经只读 `Gemini 4 Neon (high)` Gate 1 初审报出 5 中级 + 2 次要问题，派新 `Hydrogen (high)` 完成第 1 轮返工并补齐 428 项 Flutter / Python / Gradle 验证（`c510df8`）；经异构 `Gemini 4 Carbon (high)` Gate 2 双锚点复审核销前序 7 项并新捕获 2 中级 + 2 次要问题（原生聚合静默刷新补 `.setOnlyAlertOnce(true)`、4 份 `androidTest` 对齐 `ReminderDatabase v9` / `CHANNEL_UPDATES_V2` 及 `v8→v9` 迁移测试、`cancelPrivateSchedules` 串行闭包内取消测试定时器、原生未完成旧作业迁移时保护 `assignment_deadlines`），由总控直接第 2 轮攻坚修复并通过 212 项定向 Flutter + 9 组 Python + `dart analyze` + Gradle `:app:testDebugUnitTest :app:compileDebugAndroidTestKotlin :app:lintDebug`（`fb2d5b6`），再由新 `Carbon (high)` Gate 3 双锚点终审返回 **`PASS`（0 阻断 / 0 中级 / 0 次要）**；随后升至 `1.8.33+126`（`abff61e`），在干净 ASCII 目录 `D:\campus-tools\build-work\cx1833-126-20261125` 用 JDK 17 原签名构建双 ABI 自测包 `D:\campus-tools\artifacts\cx1833-preview\chaoxing-journal-1.8.33+126.apk`（`63,989,286` 字节，SHA-256 `74036130e03d60ca791fc6d3d9a1c87f520f7c7eea5b48ae38e0ec8290be2f0d`，`verify_apk_and_report.py` 全部通过），在 MuMu「学习通」（`emulator-5558`，API 35）保数据 `-r` 覆盖安装（保留 `firstInstallTime=2026-11-04 19:05:10` 及全部课业/课程/手帐数据，设备 `base.apk` 哈希一致，未触发学习通线上刷新）完成 M1–M8、浅/深双主题、自动迁 v2 渠道与后台测试通知实机送达（`1900000008`/`1900000009`）及 `logcat` 零崩溃核验，截图存 `D:\campus-tools\artifacts\cx1833-preview\screenshots`。
- 当前 commit 与状态：Stage 1 `0f6c513`、两轮 Gate 修复 `c510df8` / `fb2d5b6`、自测升版 `abff61e` 已推送 `origin/dev`（未触碰 `main` / Tag / Release / 线上 `update-*.json`），本次随状态文档更新推送 `origin/dev`；L0 行数 `52 <= 80`。
- 下一步待办：可在 `dev` 继续规划下一批迭代，或在维护者明确发出正式发版指令后冻结版本（如 `1.90.0`）进入 Stage 2 正式发布流程。

## 2026-11-25 · v1.8.32 (1.8.32+125) Gate 审查通过与 MuMu 保数据自测收口

- 已完成改动：因 `antigravity-acp` 运行时未开放 `delegate_task`，本轮改由零父历史只读 `research (pro)`（`47b126e1`）初审 + 规划模型复核查出 6 项局部问题并一次性修复（吸顶栏 `home-sliver-agenda-entry`、首页 `AssignmentCard` 列表级左轨同宽对齐、`AssignmentStore` 两处 `CourseTermCatalog.build` 补传 `changes`、`CourseTermCatalog` 180 天统计召回上限与本学期可信截止补修、待办详情复制热区 `48×40dp` 扩区、`ManualAgendaScreen` `clock` 注入与固定时钟/警告回归），通过 11 项定向门禁（`91` 项测试全绿、`dart analyze` 0 问题）推 `origin/dev`（`2d88084`），并由新只读 `research (pro)`（`af207197`）双锚点复审返回 `PASS`（0 阻断 / 0 中级 / 0 次要）；随后升至 `1.8.32+125`（`fab514f`），在干净 ASCII 目录 `D:\campus-tools\build-work\cx1832-125-20261125-141728` 用 JDK 17 原签名构建双 ABI 自测包 `D:\campus-tools\artifacts\cx1832-preview\chaoxing-journal-1.8.32+125.apk`（`63,748,670` 字节，SHA-256 `2d4feaa52fe95c30dc0b8eb0bf3bb239fb3d37c909b88a22f9f805cbfd7fa184`，`verify_apk_and_report.py` 全部通过），在 MuMu「学习通」（`emulator-5558`，API 35）保数据 `-r` 覆盖安装（保留 `firstInstallTime=2026-11-04 19:05:10` 及全部课业/课程/手帐数据，设备 `base.apk` 哈希一致，未触发线上刷新接口）完成 M1–M5 与浅/深双主题目视及全交互验收（`logcat` 0 崩溃），截图存 `D:\campus-tools\artifacts\cx1832-preview\screenshots`。
- 当前 commit 与状态：Stage 1 与 6 项 Gate 修复已合入 `2d88084`，自测升版提交 `fab514f`（未触碰 `main` / Tag / Release / `update-*.json`），本次随状态文档更新推送 `origin/dev`；L0 行数 `<= 80`。
- 下一步待办：可在 `dev` 继续攒批下一轮迭代，或在维护者明确发出正式发版指令后冻结版本进入 Stage 2 发布流程。

## 2026-11-25 · 研发与审查工作流实战减负优化（仅规则与状态文档）

- 已完成改动：重构全局 `staged-release-gate`（含 `references/t3-goal-automation.md`）、三套 T3 Antigravity 实例 `GEMINI.md`、`~/.codex/AGENTS.md`、`~/.claude/CLAUDE.md` 及本仓 `AGENTS.md`、`.agents/rules/skill-routing.md`、`VALIDATION.md`：① 按改动体量拆为「≤3 文件轻快档 / 跨模块 `/goal` 标准档 / Stage 2 发版档」并精简状态文档为阶段收口一更；② 计划规格书由 11 章八股压缩为 4 个高信噪比模块，支持同窗 `/clear`（首选）或新对话切入 `/goal`；③ Gate 初审区分「≤2 文件小瑕疵总控直修」与「实质缺陷返工 + 双锚点异构复审 + 第 2 轮强模型升级攻坚」，校准 `orchestrator_capabilities` 跨实例档位核验并隔离 `code-review` 子代理嵌套冲突、精简 `delivery-no-pseudoblock`。
- 当前 commit 与状态：仅更新工作流规则与状态文档（`v1.8.32` Stage 1 代码提交 `90a9e5b` 保持不变），L0 行数符合 `<= 80` 门禁。
- 下一步待办：在当前对话发 `/clear`（或新开 `Carbon high` 对话）运行续接 `/goal` 指令，完成 `v1.8.32`（`7bf6253..90a9e5b`）的独立 Gate 审查与 `1.8.32+125` 原签名自测包 MuMu 实测收口。

## 2026-11-25 · v1.8.32 Stage 1 (M1–M6) 完成（待 Gate 独立审查）

- 已完成改动：完成 `v1.8.32` Stage 1 全部元步骤 `M1`–`M6`：① `M1` 扩展 `CourseTermCatalog` 宽松年份目录解析、180 天召回上限、`published` 增量新作业证据（防 `syncAllTerms` 往期老课污染）及 `matchesHomeCoursePicker` 隔离静默 `ungrouped` 课至「未分组」，`AssignmentStore` 5 处 `changes` 赋值同步失效缓存，`JournalPickerSheet` 新增 `filterNoticeBuilder`，`CourseListScreen` 新增「未分组」副标与「标为本学期」快捷操作；② `M2` 新增 `overdueAmber`/`overdueAmberBg`/`overdueInk` 浅深双主题色板，去红降噪并切换统计页与饼图逾期色，重构 `ManualHomeCard` 与 `AssignmentCard` 左轨倒计时对齐、隐藏正常「提前30分提醒」并保留「自己添加」及手帐备注条；③ `M3` 对齐 `JournalGroupedCard` 43dp 头部，精修待办详情页复制胶囊、底部分割线「查看提醒状态」行并移除顶栏重复铅笔按钮；④ `M4` 重构 `ManualAgendaScreen` 为「进行中 + 默认折叠已完成（N）」双区并接入 `JournalSwipeTile` 左右滑、撤销 `SnackBar`（`TransientFeedbackController`）与长按菜单；⑤ `M5` 重组「我的」顶部 3 合 1 学习卡片（保留外置 `AppearanceControls` 与底部「关于与更新」5 项），`SyncStatusScreen` 内联白天后台检查开关与 2/4/6 小时频率，首页顶栏常驻 `待办` 并将 `每日计划` 收拢至 `更多` 菜单；⑥ `M6` 同步耦合测试并新增 M1/M2/M4/M5 回归测试。
- 当前 commit 与状态：Stage 1 全部改动待提交推送 `origin/dev`，`M1`–`M6` 均已完成；`TZ=UTC` 下 `python scripts/verify_local_gate.py --tests <22 份测试>` 全绿（`dart format` 30 文件 0 变更、`dart analyze lib test` 0 问题、9 组 Python 单测全绿、Flutter `+203 / 0 failed`）；未完成项与不确定点：无（真机/MuMu 视觉与手感核验按流程留待 Gate 通过打 `1.8.32+125` 自测包后执行）。
- 下一步待办：由独立审查代理按 `docs/plans/2026-11-25-v1.8.32-本学期筛选卡片视觉与待办交互优化方案.md` 第 9 章对 `git diff 7bf6253..HEAD` 执行 Gate 审查。

