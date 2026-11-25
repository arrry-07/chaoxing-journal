# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

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

## 2026-11-25 · v1.8.32 规划落盘与双轴审查修订（仅文档）

- 已完成改动：基于 `1.8.31+124` 基线（`7bf6253`）落盘并完成 [v1.8.32 方案](../plans/2026-11-25-v1.8.32-本学期筛选卡片视觉与待办交互优化方案.md) 深度审查与修订：封堵 `syncAllTerms` 往期已交/无截止作业误污染「本学期」漏洞、修正 `AssignmentStore.changes` 公开字段与 5 处缓存失效及 `JournalPickerSheet.filterNoticeBuilder` 分组空提示死代码、限定 `AssignmentCard` 左轨倒计时仅作用于 `!showFullDeadline`（保全默认契约）、强化 `TransientFeedbackController` / `JournalGroupedCard` 静态守卫并补齐 `home_course_labels_1815` / `journal_pilot_v1_ui` / `phase3_ui` / `profile_screen` 耦合回归点。
- 当前 commit 与状态：仅更新计划与状态文档，未改源码、测试或版本标识；`AGENTS.md` + `PROJECT_STATE.md` <= 80 行，`docs/plans/` 仅保留 1 份活跃方案。
- 下一步待办：由执行模型执行 `docs/plans/2026-11-25-v1.8.32-本学期筛选卡片视觉与待办交互优化方案.md` 的 Stage 1（`M1`–`M6`），完成后停机等待 Gate 独立审查。

## 2026-11-25 · v1.8.31 (1.8.31+124) 正式发布收口（main 与 dev 已同步）

- 已完成改动：PR `#64` 合入 `main`（`77b5e8a`）并通过 PR CI（`45482517564`）、`main` CI（`45485091357`）与 Tag `v1.8.31`（`642cb62`）CI（`45490635594`）；构建干净原签名双 ABI 正式包 `chaoxing-journal-1.8.31.apk`（`63,683,210` 字节，SHA-256 `08fc94ecf42d83576902f838b8cd15141b1f889ab5f3928a3853ab9102fe7818`）并在 MuMu `127.0.0.1:16448`（API 35）与华为实体机 `MKB4C20605047402`（`CDY-AN00`，API 29）双端完成保数据覆盖升级、M2–M7、真机/模拟器拍照+相册 PNG+PDF 挂载与外部打开及零崩溃清理验证，正式发布 GitHub Release `457363482` 并通过公开匿名下载与 `site-release-dispatch` / `gitee-release-sync`（线上 `update-manual.json=1.8.31+124`）。
- 当前 commit 与状态：完成 `v1.8.30` / `v1.8.31` 方案、`v1.8.26` 交接与 `v1.8.25` 验收归档及全套收口文档同步，`main` 与 `dev` 树一致（保留未追踪本机材料与 `.ai/`）。
- 下一步待办：下一轮 `dev` 从干净正式基线 `1.8.31+124` 起步，可按需规划 `FB-015` WebDAV 跨设备云同步或真实样本补证。

