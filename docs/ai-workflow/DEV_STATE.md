# dev 本地状态

> 阶段收口或停机交接提交时更新本文件（同一阶段中间小提交无需重复刷写）；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-27 · v1.92.1 (1.92.1+133) 全量拆缝与 UI 精修 MuMu 实机核验 PASS 及日常集成 PR #70 合入收口

- 已完成改动：承接 [v1.92.1 归档方案](../archive/plans/2026-11-27-v1.92.1-全量拆缝重构与UI交互精修方案.md)（基线 `00211d6`，Stage 1 终版代码 `b17b2ec` 本地全量门禁 `+2174 ~1` / 132 项 Python 全绿）完成 `1.92.1+133` 递增（`83e5af0`，受版本影响的 6 组 `+100` 测试与元数据校验全绿）；自干净 ASCII 目录 `D:\campus-tools\build-work\cx1921-133-20261127` 构建原签名 `x86_64` 自测包 `D:\campus-tools\artifacts\cx1921-133\chaoxing-journal-1.92.1-x64.apk`（`41,342,464` B，SHA-256 `8985ef26c7121cd5f233e390123b6cb5a8ebc3a49ab0e00a676eb012853e1f4a`，v2 原证书 `d36a5715...` / 16 KiB 对齐 / ZIP CRC 通过），于 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖（`firstInstallTime=2026-11-04 19:05:10` 保持不变、`base.apk` 摘要一致、`logcat` 0 崩溃/0 溢出）并通过只读子代理审图确认 24 张浅/深双主题与强杀冷启截屏（`D:\campus-tools\artifacts\cx1921-133\screenshots`）6/6 项全部 PASS；日常集成 PR `#70`（云端 CI Run `45941420757` 全绿）已合入 `main`（`4da4c02`，触发 `main` CI Run `45942731152`），同步 `dev` 并归档本轮方案。
- 当前 commit 与状态：集成合并基线位于 `4da4c021bc9f11ec15752d5d27698c8695191c01`（`dev` 与 `main` 代码已对齐，本提交仅归档方案与更新状态文档推 `origin/dev`）；正式基线仍为 `1.92.0+132`，未修改正式下载文档、未打 Tag、未发正式 Release。
- 下一步待办：下一 `dev` 修订自 `1.92.2+134` 起步（或待维护者指令正式发版时冻结 `1.93.0` 进入 Stage 2）；非阻断轻记项为日历说明浮层第 3 条「鼠尾草绿浅底圆圈」文案与现行浅钴蓝选中态对齐，大项推进 Supabase `FB-017` 反馈直发与 `FB-015` 加密云同步及实体 OEM 真机样本补证。

## 2026-11-27 · v1.92.0 (1.92.0+132) 正式发布收口（PR #67–#69 / Tag v1.92.0 / Gitee 双索引同步）

- 已完成改动：承接 [v1.91.1 归档方案](../archive/plans/2026-11-26-v1.91.1-Clawd2.0文字舞台8bit音效与轻量收口方案.md) 并在两次 Stage 2 MuMu 熔断退回 `dev` 后彻底清零首页压字/气泡遮挡 `home-sync-status`/统计客串靠右/摸头爱心驻留/切 Tab 毒化共享 `tickerEnabled` 与二级页冒泡竞态（`fee9a0c`、`5593980`、`8f12a97`、`64397fe`、`5330a21`、`8d4a0f6`，同步涵盖 `509bc38` 工作流解耦，最终 `8d4a0f6` 本地 `TZ=UTC verify_local_gate.py --mode full` `+2123 ~1` / 132 项 Python 单测全绿）；PR `#68` / `#69`（Run `45851596541` / `45863592685`）、最终 `main` CI（Run `45865824746`）、Tag `v1.92.0` CI（Run `45867936379`）、`site-release-dispatch`（Run `45869719962`）与 `gitee-release-sync`（Run `45869719906` + `promote_stable=true` Run `45869736892`）全部 `success`。自最终 `main` `55e5d6e` 干净 ASCII 目录 `D:\campus-tools\build-work\cx1920-132-20261126-r3` 构建原签名双 ABI 正式包 `D:\campus-tools\artifacts\cx1920-132\chaoxing-journal-1.92.0.apk`（`64,607,886` B，SHA-256 `f5fffb0444f74c56ee22b4ebf1e86822fa3978abd9fc1cf353f02224105268fd`，`verify_apk_and_report.py` 与 `check_apk_abis.py` 全过），在 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖通过 6/6 项浅/深双主题视觉终审 **`OVERALL: PASS`**（13 张截图存 `D:\campus-tools\artifacts\cx1920-132\screenshots`，`logcat` 0 崩溃/0 溢出，4 条 `v3` 渠道就绪），完成 GitHub Release `459719737` 公开设 `latest`、五方 SHA-256 校验、Gitee `update-manual.json` / `update-stable.json` 双索引公网回读（未传 APK 镜像），并归档 `v1.91.1` 方案与 `v1.90.0` 验收记录。
- 当前 commit 与状态：发布代码与 annotated Tag `v1.92.0`（`5b7bf90e`）固定在 `55e5d6ea982f2d5f62f48b49beb69af931b20e6b`（不动 Tag），本次 `[skip ci]` 收口文档提交同步推送至 `origin/main` 与 `origin/dev`，L0 行数 `<= 80`，工作区仅保留既有未提交个人/外部文件。
- 下一步待办：下一 `dev` 修订自 `1.92.1+133` 起步；优先小步快修 `CalendarScreen` 气泡滚动锚点与滚动收起对齐，随后按独立审读推进 `AssignmentStore` / `AssignmentListScreen` 领域拆缝重构（结合 `509bc38` 日常集成 PR 节奏），再立项 Supabase `FB-017` 反馈直发与 `FB-015` 端到端加密云同步，并按样本节奏补齐实体 OEM 真机与外部样本验证。

## 2026-11-26 · v1.92.0 (1.92.0+132) Stage 2 MuMu 目视验收触发熔断，已安全停机退回 Stage 1（已于上条闭环解决）

- 已完成改动：r1 候选包（`4562eb9`，SHA-256 `2766e99a...`）通过 `SoundPool` 8-bit 音轨与静音/DND 拦截实测，但视觉审计拦截首页气泡遮挡 `home-sync-status`、统计客串靠右及摸头爱心即灭；随后 r2 候选包（`295657b`，SHA-256 `6c46b79c...`）再暴露 `NoTransitionPage` 切 Tab 毒化共享 `tickerEnabled`，均严守只读红线熔断退回 `dev` 清零。
- 当前 commit 与状态：已随 `r3` 正式包（`55e5d6e`，SHA-256 `f5fffb04...`）与 `v1.92.0` 正式发布全部闭环。
- 下一步待办：已闭环。

## 2026-11-26 · v1.91.1 Stage 1 开发与独立 Gate 审查闭环 PASS（已随 v1.92.0 发布）

- 已完成改动：围绕 [v1.91.1 归档方案](../archive/plans/2026-11-26-v1.91.1-Clawd2.0文字舞台8bit音效与轻量收口方案.md) 完成 `M1–M5` 全部 29 个白名单文件实现、Gate 1/2 独立审查与全量本地门禁。
- 当前 commit 与状态：已汇总合入 `v1.92.0` 正式发布（`55e5d6e`）。
- 下一步待办：已随 `1.92.0+132` 正式发布。

## 2026-11-26 · v1.91.0 (1.91.0+131) 正式发布收口（PR #66 / Tag v1.91.0 / Gitee 双索引同步）

- 已完成改动：PR `#66` 合入 `5ab698b`，`v1.91.0`（`1.91.0+131`，Release `459234902`，SHA-256 `a9a1fdf1...`）汇总交付 `v1.90.1`–`v1.90.4`（悬浮顶栏渐变羽化、Clawd 像素伙伴、光学纸感与阻尼弹簧、同批 `clazzId` 学期推断、4 渠道有声 `v3` 提醒），MuMu 保数据 7/7 项通过，Gitee 双索引同步至 `1.91.0+131`。
- 当前 commit 与状态：上一正式版本（`5ab698b`）。
- 下一步待办：已发布并由 `1.92.0+132` 接替为当前最新正式版。
