# dev 本地状态

> 阶段收口或停机交接提交时更新本文件（同一阶段中间小提交无需重复刷写）；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-26 · v1.92.0 (1.92.0+132) Stage 2 MuMu 目视验收触发熔断，已安全停机退回 Stage 1（未打 Tag / 未发 Release / 未动 Gitee）

- 已完成改动：严格守住业务源码与测试只读红线，完成 `dev` 版本冻结 `1.92.0+132`（`62a4825`，`TZ=UTC verify_local_gate.py --mode full` `+2114 ~1` / 128 项 Python 单测全绿）、PR `#67`（CI Run `45827429525` `success`）+ 后台只读 `research` 审读（`7a1ca6b0`，0 阻断）并合入 `main`（`4562eb9`，`main` CI Run `45829440111` `success`）；自 `4562eb9` 干净 ASCII 目录 `D:\campus-tools\build-work\cx1920-132-20261126` 构建原签名双 ABI 正式包 `D:\campus-tools\artifacts\cx1920-132\chaoxing-journal-1.92.0.apk`（`64,607,886` B，SHA-256 `2766e99a97e12f82e17019838e1042efbf56d0c03c63200e38318014a3741f6a`，`verify_apk_and_report.py` 与 `check_apk_abis.py` 全过）并在 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖（`firstInstallTime=2026-11-04 19:05:10`、`base.apk` 同哈希、4 条 `v3` 渠道就绪、`SoundPool` 8-bit 音轨 `3600/5280/7440/7200/4080/3360/1344` 与关闭静音/DND 拦截/`logcat` 0 崩溃 0 溢出均通过）；但经只读视觉审读子代理（`6db55b58`）核验 21 张实机截图（`D:\campus-tools\artifacts\cx1920-132\screenshots`）后，**Checkpoint 2 & 3 判定 FAIL**：① **阻断 UI 遮挡**：`assignment_list_screen.dart:2284` 将首页 `ClawdAnchoredSpeechBubble` 的 `top` 定位在 `14.0 - offset + anchor.bottomY + 2.0`（`~56dp`），在浅/深双主题下每次轻点、3 连击、摸头与拖拽时均直接覆盖 `home-sync-status` 状态行（遮挡 `18:01 更新` 50%–100%，违反方案第 4 节第 3 条）；② **次要交互细节**：长按摸头松手后 `petSquint` 爱心立即消失（`05` 未见浮起爱心）、统计页客串小人靠右而非紧邻「课业统计」（`13`）；另有 PR 审读指出的次要联动（三副主栏 `isSyncing` 漏判 `syncReport.phase == SyncPhase.running`、统计/我的气泡滚动未随动、`allowStageMotion` 降级未清 `transientPose`）。
- 当前 commit 与状态：已立即触发 Stage 2 熔断停机——**未创建/推送 Tag `v1.92.0`、未创建 GitHub Release、未触碰 Gitee `update-manual.json`/`update-stable.json`**；`main` 停在 `4562eb9`（无 Tag 锚定，后续修复经新 PR 合入 `main` 后再统一重建正式包并打 Tag），MuMu 已恢复默认现场（`跟随系统` / `全部主页面` / `交互音效` 开启 / `ZEN_MODE_OFF`）。
- 下一步待办：退回 Stage 1 在 `dev` 修复 `assignment_list_screen.dart:2284` 首页气泡与 `home-sync-status` 重叠缺陷（补齐 `bubbleRect.overlaps(syncStatusRect) == false` 回归单测），并按需顺手收口摸头爱心短驻留、统计页客串对齐及 PR 审读列出的 3 项小联动；跑通全量门禁与独立复审后，提新 PR 合入 `main`、重建 `1.92.0+132` 正式包重过 MuMu 6 项验收再推进 Tag/Release/Gitee。

## 2026-11-26 · v1.91.1 Stage 1 开发与独立 Gate 审查闭环 PASS（跳过自测包，就绪进入 v1.92.0 Stage 2）

- 已完成改动：围绕 [v1.91.1 方案](../plans/2026-11-26-v1.91.1-Clawd2.0文字舞台8bit音效与轻量收口方案.md)（业务基线 `2005beb`，方案提交 `d7e3e1f`）按两波次完成 `M1–M5` 全部 29 个白名单文件实现：Wave 1A-a（`243661e`，`DeepSeek V4.1 Flash high`，`assignment_store.dart` 6 处会话守卫收口与 3 份文档校准）、Wave 1A-b（`3a980e1`，`Gemini 4 Hydrogen high`，8 项 8-bit 芯片音效合成与 `SoundPool` 桥接、`MainActivity.previewNotificationChime` `prepareAsync()` 异步化与勿扰拦截、死键清理及 `CourseStudyHubScreen` 折叠统一；`run_android_tests.py --local-fast` 与 5 份定向测试 `+82` 全绿）、Wave 1B（`6a8af33`，`Gemini 4 Hydrogen high`，`ClawdCompanionController` 单一真源、三档显示、`ClawdTitleStage` 等高文字舞台、`ClawdSpeechBubble` 暖纸气泡、去蓝星图标与 4 主页轻客串；全量 `+2108 ~1`）。独立 Gate 1 初审（纯 `Gemini 4 Neon high`）拦截 1 阻断 + 2 中级 + 2 次要后，由 Rework 1（`ac5acca`，`Gemini 4 Hydrogen high`，11 文件，全量 `+2114 ~1`）全数修复并补齐回归测试；独立 Gate 2 复审（纯 `Gemini 4 Neon high`）返回 **`PASS`（0 阻断 / 0 中级 / 2 次要）**；随后总控 1 文件直修 `ClawdTabCameo` 同步小跑 `mood` 联动（`d8b7f47`），在最终代码 `HEAD` 重跑 `TZ=UTC python scripts/verify_local_gate.py --mode full` 全绿（`+2114 ~1`、128 项 Python 单测、格式/静态分析/安全扫描与 L0 行数预算均通过）。
- 当前 commit 与状态：最终业务代码提交固定在 `d8b7f47`，本条状态随文档提交同步推送至 `origin/dev`；按维护者授权跳过 `1.91.1+132` 中间自测包，版本号维持 `1.91.0+131` 未改动，未触碰 `main` / Tag / Release。未实测项：MuMu/物理真机 6 项目视像素、拖拽手感及原生 8-bit 芯片发声与免打扰试听（留待 Stage 2 正式包上机核验）。
- 下一步待办：新开干净对话直接进入方案第 5 节 **Stage 2 正式发布 `v1.92.0`（`1.92.0+132`）**——在 `dev` 冻结版本并提汇总 PR 合入 `main`、干净 ASCII 目录原签名打包并在 MuMu「学习通」保数据完成 6 项目视/听觉验收、打 Tag `v1.92.0` 公开 GitHub Release 与推进 Gitee `update-manual.json` + `update-stable.json`（`--promote-stable`），最后 `[skip ci]` 收口归档。

## 2026-11-26 · v1.91.0 (1.91.0+131) 正式发布收口（PR #66 / Tag v1.91.0 / Gitee 双索引同步）

- 已完成改动：围绕 [v1.90.4 归档方案](../archive/plans/2026-11-26-v1.90.4-悬浮顶栏渐隐过渡与Clawd像素伙伴精修方案.md)（基线 `3da48eb`）完成 `M1–M2` 实现（`7135629`，`Gemini 4 Hydrogen high`，6 文件白名单，全量 `+2098 ~1`）、Gate 1 独立审查（`Gemini 4 Neon high`）拦截 2 中级 + 1 次要后的第 1 轮返工（`714eac0`，4 文件白名单，全量 `+2101 ~1`）及 Gate 2 独立复审（`Gemini 4 Neon high`，**`PASS` 0 阻断 / 0 中级 / 0 次要**）；随后在 `dev` 冻结 `1.91.0+131`（`ecc2346`），PR `#66` 汇总 `1.90.1–1.90.4` 合入 `main`（`5ab698b`），annotated Tag `v1.91.0`（`662616aa` → `5ab698b`）与 PR/main/Tag 全量 CI（`45794750429` / `45796462441` / `45798321017`）、`site-release-dispatch`（`45800488770`）及 `gitee-release-sync`（`45800488689` + `promote_stable=true` `45800592922`）全部 `success`。在干净 ASCII 目录 `D:\campus-tools\build-work\cx1910-131-20261126` 用 JDK `17.0.21` 原签名构建双 ABI 正式包 `D:\campus-tools\artifacts\cx1910-131\chaoxing-journal-1.91.0.apk`（`64,280,402` B，SHA-256 `a9a1fdf14434a5246f5d5a1800a7898d2f4aeb69425bfd80f1779deda635c8ae`，`verify_apk_and_report.py` 与 `check_apk_abis.py` 全过），完成 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖 7/7 项浅/深双主题视觉审计 PASS（截图存 `D:\campus-tools\artifacts\cx1910-131\screenshots`，`logcat` 0 崩溃/0 溢出，4 条 `v3` 渠道就绪）、GitHub Release `459234902` 公开设 `latest` 与五方回下载校验、Gitee `update-manual.json` / `update-stable.json` 双索引公网回读核验（未上传 Gitee APK 镜像），并归档 `v1.90.1`/`v1.90.3`/`v1.90.4` 方案与 `v1.8.31` 验收记录。
- 当前 commit 与状态：发布代码与 Tag `v1.91.0` 固定在 `5ab698b542b7549be1d1edf3eb8b5b06c2abacce`（不动 Tag），本次随 `[skip ci]` 收口文档提交同步推送至 `origin/main` 与 `origin/dev`，L0 行数 `<= 80`，工作区干净。
- 下一步待办：优先按发布后独立审读推进 `AssignmentStore` / `AssignmentListScreen`（含 `HomeBuddyController`）领域拆缝重构并冻结 `v3` 渠道代际，补齐物理真机 OEM `v3` 响铃/Doze/120Hz 与跨校 `backclazzdata` 样本，随后统一 `FB-015` 选型口径立项云端同步与 App 内直发反馈（下一 `dev` 自测包自 `1.91.1+132` 起步）。

## 2026-11-26 · v1.90.3 (1.90.3+130) 主页光学质感、顶栏像素伙伴与阻尼弹簧闭环及 MuMu 保数据验收

- 已完成改动：围绕 [v1.90.3 归档方案](../archive/plans/2026-11-26-v1.90.3-主页光学质感顶栏像素伙伴与阻尼弹簧方案.md)（基线 `5e3f6da5`）完成 `M1–M3` 实现、三轮跨厂商 `codex/gpt-6.2-sol (high)` 独立审查、两轮返工+局部直修及真机窄屏悬浮标题/短语同行修复（`b8595aa`），构建原签名自测包 `1.90.3+130`（`64,214,866` B，SHA-256 `9e8aa9c0...`）并在 MuMu「学习通」与真机 `HUAWEI CDY-AN00` 完成双端保数据验收。
- 当前 commit 与状态：已汇总合入 `v1.91.0` 正式发布（`5ab698b`）。
- 下一步待办：已随 `1.91.0+131` 正式发布。

## 2026-11-26 · v1.90.2 (1.90.2+129) 课程学期同批 clazzId 推断修复与 MuMu 保数据验收

- 已完成改动：完成 `chaoxing_api_parser.dart` 保守提取 `createtime` 与 `course_term_catalog.dart` 同批 `clazzId` 队列推断（`CourseTermSource.clazzCohort`），通过全量门禁（`+2054 ~1`），构建自测包 `1.90.2+129`（SHA-256 `f950b33b...`）并在 MuMu `emulator-5558` 保数据覆盖验收通过。
- 当前 commit 与状态：已汇总合入 `v1.91.0` 正式发布（`5ab698b`）。
- 下一步待办：已随 `1.91.0+131` 正式发布。
