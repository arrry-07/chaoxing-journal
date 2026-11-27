# dev 本地状态

> 阶段收口或停机交接提交时更新本文件（同一阶段中间小提交无需重复刷写）；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

<a id="工作流成效观察"></a>

## 工作流成效观察

各取下一项真实小修、普通 UI 迭代、数据或同步任务，在对应收口记录中填写四项：需求到可用的总时长、维护者实际投入时长、因遗漏返工的轮数、验收后回退或补修的次数。复用 Git、CI、会话和验收记录，补记模型、任务难度、设备或 CI 等待时长及首轮 MuMu 的设计方向结果。用相同口径与改造前同类任务比较，缺失项标为「未测」；三项样本目前待采集。

**观测起点（2026-11-27，v1.92.3+134）**

- 已完成改动：统一引用全局风险分档，落盘项目验证、两阶段授权、代表页 MuMu 单 ABI 早预览、定点归档和 pwsh UTC 门禁。
- 当前 commit 与状态：基线 `2aed324`，`dev` 应用版本 `1.92.3+134`。正式基线仍为 `1.92.0+132`。验证覆盖仓库安全、元数据、L0 行数、文档链接、PowerShell UTC 命令和归档搜索边界。
- 下一步待办：在接下来的真实任务中按上面的口径记录成效。沿用已有 dev 开发、验收与正式发布权限。

**2026-11-27 · v1.92.3+134 工作流门禁修复**

- 已完成改动：本地与 CI 按集成范围检查 Dart 格式，正式冻结标记让补丁候选也接受完整文档检查，官网正式派发缺 Token 时明确失败。收口直接使用仓内验证入口。
- 当前 commit 与状态：基于 `9aae005`，应用版本仍为 `1.92.3+134`。验证覆盖多提交格式范围、正式补丁缺文档和官网派发失败路径。
- 下一步待办：下一次实际 PR／正式发布按对应入口核对云端运行结果；后续业务任务沿用上方现有的成效观察口径。

**2026-11-28 · v1.92.3+134 日常验证入口精简**

- 已完成改动：明确纯文档、静态文案和局部业务的定向检查入口。项目发版正文以仓内 `.agents/skills/release-chaoxing-journal` 为准。
- 当前 commit 与状态：基于 `f4f4a3a`，交付范围为流程文档。核对了小修、共享契约、日常集成、正式发布和设备验收的适用条件。
- 下一步待办：下一次真实小修记录维护者投入与实际检查耗时，沿用本页的工作流成效观察。

## 2026-11-27 · v1.92.3 (1.92.3+134) UI 回退至 v1.92.1、保留 4 项非 UI 修复、双机实测 PASS 及日常集成 PR #71 合入收口

- 已完成改动：承接归档的 [v1.92.2 方案](../archive/plans/2026-11-27-v1.92.2-全站视觉底座首页筛选详情与快速录入精修方案.md) 与 [v1.92.3 方案](../archive/plans/2026-11-27-v1.92.3-我的日历统计课程管理精修与全站验收方案.md) 递增版本至 `1.92.3+134`（`4f4e5a3`），随后按维护者实机反馈将全部 UI 改动完整回退至 `v1.92.1` 基线（`864fa86`，本地 `TZ=UTC verify_local_gate.py --mode full` `+2177 ~1` / 132 项 Python 全绿），保留 4 项非 UI 功能修复（北京时间自然日差、`showFullDeadline` 完整日期、日历说明第 3 条文案修正、课程关注 `accountEpoch` 守卫撤销）；自干净 ASCII 目录 `D:\campus-tools\build-work\cx1923-134-r2-20261127` 构建双架构原签名包 `D:\campus-tools\artifacts\cx1923-134\chaoxing-journal-1.92.3-r2.apk`（`64,607,886` B，SHA-256 `f61cf7c0bd6642097d4ab768511bf19aae98c7aaad029bc17e5118c5a6905f10`，v2 证书 `d36a5715...` / 16 KiB 对齐 / ZIP 473 条目全过），于 MuMu「学习通」（`emulator-5558`，API 35，`firstInstallTime=2026-11-04 19:05:10`）与华为真机（`MKB4C20605047402`，`HUAWEI CDY-AN00`，Android 10，`firstInstallTime=2026-11-11 22:53:16`）保数据覆盖均核对 `base.apk` 一致且 23/23 截屏（`D:\campus-tools\artifacts\cx1923-134\screenshots_r2`）经只读子代理审图 **`OVERALL: PASS`**（双机 `logcat` 0 崩溃/0 溢出）；随后按 PR `#71` 审查意见追加 `DisplayPreferences.beijingDayDiff` UTC 跨夏令时口径与 `CourseListScreen` 改检 `store.operationError`（`dba9d0c`，定向门禁 `+73` 全绿），日常集成 PR `#71`（云端 CI Run `45976367229` 全绿）已合入 `main`（`0087205`，触发 `main` CI Run `45978296798`），同步 `dev` 并归档两份方案。
- 当前 commit 与状态：集成合并基线位于 `00872056e97cba294c68cbeaca5ef81422dac3bd`（`dev` 与 `main` 代码已对齐，本提交仅归档两份方案并更新状态文档推 `origin/dev`）；正式基线仍为 `1.92.0+132`，未修改正式下载文档、未打 Tag、未发正式 Release。
- 下一步待办：下一 `dev` 修订自 `1.92.4+135` 起步（或待维护者下达正式发版指令时冻结 `1.93.0` 进入 Stage 2 正式发布，届时从最终 `main` 重新构建并核验正式包）；非阻断轻记项为安卓桌面原生小组件 `StudyWidgetProvider` 次日仍用 `ceil` 天数（可按需与 Dart 口径对齐），大项推进 Supabase `FB-017` 反馈直发与 `FB-015` 加密云同步。

## 2026-11-27 · v1.92.3 我的、日历、统计、课程管理精修 Stage 1 开发与 Gate 审查闭环 PASS（UI 已于上条回退）

- 已完成改动：承接 `v1.92.2`（`cb501cf`）围绕 [v1.92.3 归档方案](../archive/plans/2026-11-27-v1.92.3-我的日历统计课程管理精修与全站验收方案.md) 完成 M1–M3 全量落地（`552adbf`）：「我的」页顶栏单行化、去独立「设置」标题、新增「其他入口」卡片、三张主题预览加高至 `78dp`、「GitHub 项目」Star 文案配整行打开/右侧复制按钮与失败兜底复制；日历 `48dp` 可见周/月切换栏、单日/整月空态与图例更新、整月议程完整日期；统计「全部学期 / 不限时间」、「已完成 X / Y」（`Journal.uiFamily`）、待完成暖石板中性阶与已逾期 45° 斜纹及下钻不变量保留；课程管理统一 `inputFill/inputBorder` 与带 `accountEpoch` 守卫的关注切换「撤销」闭环；经 Gate 1 独立审查（`Gemini 4 Neon high`）拦截 1 阻断（进度条逾期斜纹未裁剪越界）/1 中级（复制按钮视觉 48dp 过高且 `360dp @ 1.3x` 未下叠）/4 次要后，由第 1 轮返工（`ccaa97b`）一次性清零并获 Gate 2 独立复审（`Gemini 4 Carbon high`）**PASS**。
- 当前 commit 与状态：终版代码位于 `ccaa97ba59b5ffbb59e3a1740b1b96ce17230535`（`dev`，未递增 `1.92.1+133` 版本号、未打自测包、未动 `main`/Tag/Release）；终版 `HEAD` 已实跑 `TZ=UTC python scripts/verify_local_gate.py --mode full` 全绿（Flutter 全套 `+2196 ~1`、`dart analyze lib test` 0 问题、132 项 Python 单测与安全/元数据/L0 `57<=80` 校验全过；Android 原生、APK 构建、MuMu 实机与远端 CI 仍未实测）。
- 下一步待办：已于上条按维护者实机反馈回退 UI、保留 4 项非 UI 修复并经 PR `#71` 集成收口。

## 2026-11-27 · v1.92.2 全站视觉底座、首页、筛选、详情与快速录入精修 Stage 1 开发与 Gate 审查闭环 PASS

- 已完成改动：围绕 [v1.92.2 归档方案](../archive/plans/2026-11-27-v1.92.2-全站视觉底座首页筛选详情与快速录入精修方案.md)（基线 `8655c79`）完成 M1–M4 全量落地（`c68a5b9` / `07ea9d7`）：撤除首页双色光斑与首页/详情顶栏模糊羽化、接入 `AppShell` 状态栏衔接与五态高对比输入框（深色 `inputBorder` `#7A756C` 全表面 `>= 3.0:1`）、引入 `Journal.uiFamily` 数字微标、首页顶栏 2 键与双胶囊筛选、北京时间自然日差消除「明天+剩2天」及置顶/按课程完整日期、三段式搜索筛选面板、详情主次外跳分层与本机完成副文案、快速新增底栏保存与「更多选项」渐进折叠；经 Gate 1 独立审查（`Gemini 4 Neon high`）拦截 1 阻断/2 中级/3 次要后，通过第 1 轮返工（`5bc2ec7`）与测试同步（`d32ab02`）获 Gate 2 独立复审（`Gemini 4 Carbon high`）**PASS**，再直修 2 处非阻断微瑕疵（`368c8cd`）并同步 3 份全量旧测试断言（`c53c83c`）。
- 当前 commit 与状态：终版代码位于 `c53c83c291c0280f29985a642c31b438912fde0f`（`dev`，未递增 `1.92.1+133` 版本号、未构建自测 APK、未动 `main`/Tag/Release）；终版 `HEAD` 已实跑 `TZ=UTC python scripts/verify_local_gate.py --mode full` 全绿（Flutter 全套 `+2189 ~1`、`dart analyze lib test` 0 问题、132 项 Python 单测与安全/元数据校验全过，Android 原生与 MuMu 真机本轮按计划暂缓未实测）。
- 下一步待办：已于上条按维护者实机反馈回退 UI、保留 4 项非 UI 修复并经 PR `#71` 集成收口。

## 2026-11-27 · v1.92.1 (1.92.1+133) 全量拆缝与 UI 精修 MuMu 实机核验 PASS 及日常集成 PR #70 合入收口

- 已完成改动：承接 [v1.92.1 归档方案](../archive/plans/2026-11-27-v1.92.1-全量拆缝重构与UI交互精修方案.md)（基线 `00211d6`，Stage 1 终版代码 `b17b2ec` 本地全量门禁 `+2174 ~1` / 132 项 Python 全绿）完成 `1.92.1+133` 递增（`83e5af0`，受版本影响的 6 组 `+100` 测试与元数据校验全绿）；自干净 ASCII 目录 `D:\campus-tools\build-work\cx1921-133-20261127` 构建原签名 `x86_64` 自测包 `D:\campus-tools\artifacts\cx1921-133\chaoxing-journal-1.92.1-x64.apk`（`41,342,464` B，SHA-256 `8985ef26c7121cd5f233e390123b6cb5a8ebc3a49ab0e00a676eb012853e1f4a`，v2 原证书 `d36a5715...` / 16 KiB 对齐 / ZIP CRC 通过），于 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖（`firstInstallTime=2026-11-04 19:05:10` 保持不变、`base.apk` 摘要一致、`logcat` 0 崩溃/0 溢出）并通过只读子代理审图确认 24 张浅/深双主题与强杀冷启截屏（`D:\campus-tools\artifacts\cx1921-133\screenshots`）6/6 项全部 PASS；日常集成 PR `#70`（云端 CI Run `45941420757` 全绿）已合入 `main`（`4da4c02`，触发 `main` CI Run `45942731152`），同步 `dev` 并归档本轮方案。
- 当前 commit 与状态：集成合并基线位于 `4da4c021bc9f11ec15752d5d27698c8695191c01`（`dev` 与 `main` 代码已对齐，本提交仅归档方案与更新状态文档推 `origin/dev`）；正式基线仍为 `1.92.0+132`，未修改正式下载文档、未打 Tag、未发正式 Release。
- 下一步待办：下一 `dev` 修订自 `1.92.2+134` 起步（或待维护者指令正式发版时冻结 `1.93.0` 进入 Stage 2）；非阻断轻记项为日历说明浮层第 3 条「鼠尾草绿浅底圆圈」文案与现行浅钴蓝选中态对齐，大项推进 Supabase `FB-017` 反馈直发与 `FB-015` 加密云同步及实体 OEM 真机样本补证。

## 2026-11-27 · v1.92.0 (1.92.0+132) 正式发布收口（PR #67–#69 / Tag v1.92.0 / Gitee 双索引同步）

- 已完成改动：承接 [v1.91.1 归档方案](../archive/plans/2026-11-26-v1.91.1-Clawd2.0文字舞台8bit音效与轻量收口方案.md) 并在两次 Stage 2 MuMu 熔断退回 `dev` 后彻底清零首页压字/气泡遮挡 `home-sync-status`/统计客串靠右/摸头爱心驻留/切 Tab 毒化共享 `tickerEnabled` 与二级页冒泡竞态（`fee9a0c`、`5593980`、`8f12a97`、`64397fe`、`5330a21`、`8d4a0f6`，同步涵盖 `509bc38` 工作流解耦，最终 `8d4a0f6` 本地 `TZ=UTC verify_local_gate.py --mode full` `+2123 ~1` / 132 项 Python 单测全绿）；PR `#68` / `#69`（Run `45851596541` / `45863592685`）、最终 `main` CI（Run `45865824746`）、Tag `v1.92.0` CI（Run `45867936379`）、`site-release-dispatch`（Run `45869719962`）与 `gitee-release-sync`（Run `45869719906` + `promote_stable=true` Run `45869736892`）全部 `success`。自最终 `main` `55e5d6e` 干净 ASCII 目录 `D:\campus-tools\build-work\cx1920-132-20261126-r3` 构建原签名双 ABI 正式包 `D:\campus-tools\artifacts\cx1920-132\chaoxing-journal-1.92.0.apk`（`64,607,886` B，SHA-256 `f5fffb0444f74c56ee22b4ebf1e86822fa3978abd9fc1cf353f02224105268fd`，`verify_apk_and_report.py` 与 `check_apk_abis.py` 全过），在 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖通过 6/6 项浅/深双主题视觉终审 **`OVERALL: PASS`**（13 张截图存 `D:\campus-tools\artifacts\cx1920-132\screenshots`，`logcat` 0 崩溃/0 溢出，4 条 `v3` 渠道就绪），完成 GitHub Release `459719737` 公开设 `latest`、五方 SHA-256 校验、Gitee `update-manual.json` / `update-stable.json` 双索引公网回读（未传 APK 镜像），并归档 `v1.91.1` 方案与 `v1.90.0` 验收记录。
- 当前 commit 与状态：发布代码与 annotated Tag `v1.92.0`（`5b7bf90e`）固定在 `55e5d6ea982f2d5f62f48b49beb69af931b20e6b`（不动 Tag），本次 `[skip ci]` 收口文档提交同步推送至 `origin/main` 与 `origin/dev`，L0 行数 `<= 80`，工作区仅保留既有未提交个人/外部文件。
- 下一步待办：下一 `dev` 修订自 `1.92.1+133` 起步；优先小步快修 `CalendarScreen` 气泡滚动锚点与滚动收起对齐，随后按独立审读推进 `AssignmentStore` / `AssignmentListScreen` 领域拆缝重构（结合 `509bc38` 日常集成 PR 节奏），再立项 Supabase `FB-017` 反馈直发与 `FB-015` 端到端加密云同步，并按样本节奏补齐实体 OEM 真机与外部样本验证。
