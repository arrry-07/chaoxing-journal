# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

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

