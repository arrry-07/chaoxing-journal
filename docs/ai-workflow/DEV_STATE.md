# dev 本地状态

> 阶段收口或停机交接提交时更新本文件（同一阶段中间小提交无需重复刷写）；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-26 · v1.90.1 (1.90.1+128) dev 闭环：课程学期投票、有声 v3 全渠道、紧凑密度修复、1.90.0 收口与 MuMu 保数据验收

- 已完成改动：围绕 [v1.90.1 方案](../plans/2026-11-26-v1.90.1-课程学期分组有声通知v3紧凑密度与1900收口方案.md)（基线 `8260461`）分 3 组互斥完成 `M1–M4` Stage 1 实现（组 1/3 `DeepSeek V4.1 Flash high` + 组 2 `Gemini 4 Hydrogen high` + 集成共享测试，提交 `7646720`，通过 `TZ=UTC verify_local_gate.py --mode full` 2042+39 项、128 项 Python 单测与 `run_android_tests.py --local-fast`）。独立 `Gemini 4 Neon (high)` Gate 1 初审报出 3 中级 + 2 次要问题（`noticeOnly` 考试漏用 `publishedAt` 投票、试听清铃静音/零音量分支顺序、`ManualHomeCard` 紧凑 0.85x 缺 `minHeight: 48` 兜底、静音态重复横幅、旧 mock 残留），经 `DeepSeek V4.1 Flash high` 返工修复（`ab7fd77`，7 组 195/195 绿）并由新独立 `Neon (high)` Gate 2 复审返回 **`PASS`（0 阻断 / 0 中级 / 1 次要）**；总控直修 `reminder_status_screen.dart` 静音文案并升至 `1.90.1+128`（`65fae7d`）。在 `D:\campus-tools\build-work\cx1901-128-20261126` 用 JDK 17 原签名构建双 ABI 自测包 `D:\campus-tools\artifacts\cx1901-preview\chaoxing-journal-1.90.1+128.apk`（`64,083,642` B，SHA-256 `ce09e0c79022f654c76eda09bd90f68cd5f3425940b8b6cd588d3fc813d0c8a4`，`verify_apk_and_report.py` 全过），在 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖通过（`firstInstallTime=2026-11-04 19:05:10` 保留、`base.apk` 哈希一致，4 条 `v3` 渠道生效且旧 `v1`/`v2` 全退役、`STREAM_NOTIFICATION=0` 告警、清铃试听、3 秒切桌面测试待办提醒横幅、紧凑/标准对比、课程/待办折叠区与深色模式均正常，`logcat` 0 崩溃/0 溢出，截图存 `D:\campus-tools\artifacts\cx1901-preview\screenshots`）。
- 当前 commit 与状态：Stage 1 `7646720`、Gate 1 返工 `ab7fd77`、自测升版 `65fae7d` 与本状态收口提交已推至 `origin/dev`（未动 `main` / Tag / Release / Gitee），L0 行数 `<= 80`；明确「未实测」项：`androidTest` 真机/模拟器运行（仅编译与 Lint 通过）、物理真机锁屏 3 秒外放响铃与实体侧键通知音量归零告警。
- 下一步待办：由维护者安装 `1.90.1+128` 自测包做物理真机音频/锁屏验证，随后按需规划 `v1.90.2` 第二波迭代（主页色彩/光学质感、阻尼弹簧与像素伙伴）或授权 `v1.91.0` 正式发版。

## 2026-11-26 · v1.90.0 (1.90.0+127) 正式发布收口（PR #65 / Tag v1.90.0 / Gitee 双索引同步）

- 已完成改动：跑完 [v1.8.34 归档方案](../archive/plans/2026-11-25-v1.8.34-配色统一无重叠转场悬浮详情顶栏与体验精修方案.md) Stage 1 实现（`42366be`）、两轮返工收口（`106cc6c` / `330d6d1`）及三轮异构 Gate 审查（最终 Gate 3 `Gemini 4 Carbon high` 返回 `PASS`，0 阻断 / 0 中级 / 0 次要）并冻结正式版 `1.90.0+127`（`60ea569`）；PR `#65` 合入 `main`（`ea64137`），annotated Tag `v1.90.0`（`733ea66` → `ea64137`）与 PR/main/Tag 全量 CI（`45664400509` / `45668542409` / `45674222702`）、`site-release-dispatch`（`45677293557`）及 `gitee-release-sync`（`45677293556` + `promote_stable=true` `45677436429`）全部 `success`。在干净 ASCII 目录 `D:\campus-tools\build-work\cx1900-127-20261126` 用 JDK 17.0.21 原签名构建双 ABI 正式包 `D:\campus-tools\artifacts\cx1900-127\chaoxing-journal-1.90.0.apk`（`64,054,782` B，SHA-256 `c3a85faa518afc203bcb7514bb8472630e416fcb4d3ffeb63a987d26e756d13f`，`verify_apk_and_report.py` 全过），完成 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖 5 项浅/深主题验收（截图存 `D:\campus-tools\artifacts\cx1900-127\screenshots`，`logcat` 0 崩溃）、GitHub Release `458482127` 公开设 `latest` 与五方回下载校验，以及 Gitee `update-manual.json` / `update-stable.json` 双索引公网回读核验（未上传 Gitee APK 镜像），并归档 `v1.8.33` / `v1.8.34` 方案与 `v1.8.26` 验收记录。
- 当前 commit 与状态：发布代码与 Tag `v1.90.0` 固定在 `ea64137b98312f2fe20d4cc529fb5573067da369`（不动 Tag），本次随 `[skip ci]` 收口文档提交同步推送至 `origin/main` 与 `origin/dev`，L0 行数 `<= 80`，工作区干净。
- 下一步待办：下一轮迭代可先做轻量收口（清理 `AssignmentStore` 剩余手写会话校验、复用剩余 2 处 `JournalExpansionTile` 与修正 3 处旧文案口径），随后按需求推进真机 OEM 有声通知/真实样本补证或立项 `FB-015` 云同步与 `FB-017` App 内反馈。

## 2026-11-25 · 研发流程与本地门禁四项提效优化（工具脚本 + 规则文档）

- 已完成改动：落地四项本地门禁与 `/goal` 闭环提效优化并完成两轮双轴代码审查收口加固：① [verify_local_gate.py](../../scripts/verify_local_gate.py) 为 Flutter 单测接入默认 `--timeout 30s`（`--test-case-timeout none` 正确透传禁用）与外层进程树超时熔断（quick 300s / full 900s，`os.read` 增量 UTF-8 解码实时捕获裸 `\r` 与 `HH:MM:SS` 卡死用例帧，覆盖超时与 `KeyboardInterrupt` 进程树清理），回归见 [test_verify_local_gate.py](../../scripts/test_verify_local_gate.py)；② [run_android_tests.py](../../scripts/run_android_tests.py) 新增 `--local-fast` 持久化 ASCII 白名单增量镜像快检（彻底清理白名单外 `ios/`/`test/`/`tool/` 历史残留、2s 窗口防同 tick 等长文件漏拷、拦截源/目标目录重叠或嵌套、执行前预删旧 `.local_fast_pub_stamp` 并校验 `pubspec+SDK 版本+插件注册类` 按需运行 `flutter pub get --offline --enforce-lockfile`、完整 `.properties` 转义/反转义根除 `[PropertyEscape]`，一次跑通 `:app:testDebugUnitTest` + `:app:compileDebugAndroidTestKotlin` + `:app:lintDebug`），回归见 [test_run_android_tests.py](../../scripts/test_run_android_tests.py)；③ 同步更新 [AGENTS.md](../../AGENTS.md)、[VALIDATION.md](VALIDATION.md)、[开发与贡献.md](../guides/开发与贡献.md)、[.agents/rules/skill-routing.md](../../.agents/rules/skill-routing.md) 与全局 `staged-release-gate` 技能（含 Windows 下 Python `subprocess.run` 调 `acp-mcp-call` 标准方式），固化标准档软上限（≤ 4–5 模块 / ≤ 25–30 文件）、Stage 1 原生快检硬要求与 Gate 3 窄补丁（≤ 10 文件）增量终审。
- 当前 commit 与状态：仅变更门禁脚本、脚本单测与工作流规则文档（已合并入 `v1.90.0`），L0 行数 `52 <= 80`。
- 下一步待办：已随 `1.90.0+127` 正式发布。

## 2026-11-25 · v1.8.33 (1.8.33+126) 完整 dev 闭环：Stage 1、异构 Gate 终审 PASS 与 MuMu 保数据实测收口

- 已完成改动：通过 `acp-mcp-call delegate_task` 跑完 [v1.8.33 方案](../archive/plans/2026-11-25-v1.8.33-课程过滤更新收敛通知有声与交互精修方案.md) 全部 `M1–M8` 实现（`Gemini 4 Hydrogen high`，`0f6c513`）；经只读 `Gemini 4 Neon (high)` Gate 1 初审报出 5 中级 + 2 次要问题，派新 `Hydrogen (high)` 完成第 1 轮返工并补齐 428 项 Flutter / Python / Gradle 验证（`c510df8`）；经异构 `Gemini 4 Carbon (high)` Gate 2 双锚点复审核销前序 7 项并新捕获 2 中级 + 2 次要问题，由总控直接第 2 轮攻坚修复（`fb2d5b6`），再由新 `Carbon (high)` Gate 3 双锚点终审返回 **`PASS`（0 阻断 / 0 中级 / 0 次要）**；随后升至 `1.8.33+126`（`abff61e`），构建原签名双 ABI 自测包 `D:\campus-tools\artifacts\cx1833-preview\chaoxing-journal-1.8.33+126.apk`（`63,989,286` B，SHA-256 `74036130e03d60ca791fc6d3d9a1c87f520f7c7eea5b48ae38e0ec8290be2f0d`），在 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖完成 M1–M8、浅/深双主题、自动迁 v2 渠道与后台测试通知送达及 `logcat` 零崩溃核验，截图存 `D:\campus-tools\artifacts\cx1833-preview\screenshots`。
- 当前 commit 与状态：Stage 1 `0f6c513`、两轮 Gate 修复 `c510df8` / `fb2d5b6`、自测升版 `abff61e` 已整合交付至 `v1.90.0`。
- 下一步待办：已随 `1.90.0+127` 正式发布。

## 2026-11-25 · v1.8.32 (1.8.32+125) Gate 审查通过与 MuMu 保数据自测收口

- 已完成改动：经零父历史只读 `research (pro)`（`47b126e1`）初审 + 规划模型复核查出 6 项局部问题并一次性修复，通过 11 项定向门禁（`91` 项测试全绿、`dart analyze` 0 问题）推 `origin/dev`（`2d88084`），并由新只读 `research (pro)`（`af207197`）双锚点复审返回 `PASS`（0 阻断 / 0 中级 / 0 次要）；随后升至 `1.8.32+125`（`fab514f`），构建原签名双 ABI 自测包 `D:\campus-tools\artifacts\cx1832-preview\chaoxing-journal-1.8.32+125.apk`（`63,748,670` B，SHA-256 `2d4feaa52fe95c30dc0b8eb0bf3bb239fb3d37c909b88a22f9f805cbfd7fa184`），在 MuMu「学习通」（`emulator-5558`，API 35）保数据覆盖完成 M1–M5 与浅/深双主题目视及全交互验收（`logcat` 0 崩溃），截图存 `D:\campus-tools\artifacts\cx1832-preview\screenshots`。
- 当前 commit 与状态：Stage 1 与 6 项 Gate 修复（`2d88084`）及自测升版（`fab514f`）已整合交付至 `v1.90.0`。
- 下一步待办：已随 `1.90.0+127` 正式发布。
