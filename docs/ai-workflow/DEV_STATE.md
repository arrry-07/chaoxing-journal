# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-24 · v1.8.29 增量 Gate 通过与 1.8.29+123 自测包收口

- 已完成改动：增量 Gate 在 `e915990` 通过（0 阻断）；版本提交 `87a4207` 仅改 `pubspec.yaml` 与 `AppVersion` 至 `1.8.29+123`；从该提交 `git archive` 的干净 ASCII 镜像、本机缓存 `--no-pub` 构建原签名双 ABI Release APK，并完成 MuMu「学习通」保数据覆盖与纯离线基础冒烟。
- 当前 commit 与状态：版本 `87a4207`，收口文档随后单独提交；APK `62,109,666` 字节、SHA-256 `0749a144c9d32bcf453a0ae26383d41aaa9243e231076acc67f5d29548de0f3a`，`1.8.29 (123)`、min26/target36、ARM64/x86_64、非 debuggable、v2 证书 `d36a5715...`、16 KiB 对齐与 ZIP 472 条目 CRC 全通过。MuMu `127.0.0.1:16448` 覆盖成功，`firstInstallTime=2026-11-04 19:05:10` 保留、设备 `base.apk` 哈希一致；纯离线阻断 UID 10042 出站 6 包、0 线上请求成功，登录态/40 门课程/首页课业保留，关于我们 `1.8.29 (123)`，混排与置顶/取消置顶正常，提醒设置页正常，logcat 0 条 `FATAL/FlutterError/RenderFlex overflowed`；未新建临时条目、置顶已取消、首页保持「时间近到远」，证据在 `D:\campus-tools\build-work\cx1829-preview-87a4207-20261124-202406`。
- 下一步待办：按 [ROADMAP](../ROADMAP.md#dev-下一阶段) 规划下一轮；正式发版仍等维护者指令后进入 Stage 2（目标 `1.90.0`，构建号高于 `+123`），`docs/plans/` 保持 3 份现状；本轮未触碰 main/Tag/Release/Gitee。

## 2026-11-24 · v1.8.29 Stage 1 完成（会话守卫收敛 + 离线边界 + 双 API 矩阵）

- 已完成改动：Stage 1 主体为 `7f27920`（5 处会话守卫、净减 13 行、13 项回归）、`caff7b6`（9 项离线边界回归，UTC/上海/洛杉矶全绿）、`4b1a6b8`（API 33+ 授权、API 矩阵与多设备脚本）、`da3b27d`（Doze 真实状态）与 `306c031`（文档收口）；本轮按 Gate 返工清单提交 `404fa82`，补齐 1a/1c/2a/2b/3 守卫回归、9010 Cookie 解锁与下游断言、矩阵 c/d 清理和广播对账，以及镜像 SDK 优先级、Doze ManifestError 透传、OEM 通道解析（Python 22 项）。
- 当前 commit 与状态：`HEAD=404fa82`；隔离 MuMu API 32 为 4 批 22 类 116 项、111 通过/5 假设跳过/0 失败，API 35 为 116 项、115 通过/1 假设跳过/0 失败；API 35 batch4 4/4、聚合通知 8/8 均 `STATUS_CODE 0`，Doze `IDLE → reset`；API 32 OEM 禁用 Doze 记 `unsupported`，d 项仍通过。最终门禁 14 份 Flutter 208 项、9 组 Python 112 项、`dart analyze` 0 问题、L0 `32 + 25 = 57` 行；日志 `D:\campus-tools\build-work\androidtest-matrix-20261124-200655\androidtest-matrix.log`，Gradle 日志 `D:\campus-tools\build-work\androidtest-matrix-build-20261124-200033\gradle-build.log`。
- 下一步待办：增量 Gate 已于 `e915990` 通过（0 阻断），随后完成 `1.8.29+123` 自测包收口（见上一条）；`docs/plans/` 保持 3 份，正式发版仍待维护者指令。

## 2026-11-24 · 固化 dev 分支开发命名规范、下一正式版 1.90.0 与方案更名

- 已完成改动：根据维护者纠正，先在 `2516d8c` 更新规则/技能与 `v1.8.27`/`v1.8.28` 方案命名，随后明确 `1.8.x` 之后下一正式版从 `1.90.0` 起步（之后按 `1.91.0…1.99.0 → 2.0.0` 递增，`dev` 仍按 `Z` 递进并在 `1.90.0` 发布后从 `1.90.1` 起步），同步更新 `scripts/freeze_release.py`（`_expected_formal_base`）、`check_release_metadata.py`、dispatch 工作流描述、对应 Python 契约单测及全部规则/文档；同时将未跟踪新方案就地重命名为 [2026-11-24-v1.8.29-设备提醒矩阵与同步边界加固方案.md](../plans/2026-11-24-v1.8.29-设备提醒矩阵与同步边界加固方案.md)（保持未跟踪以维护 `docs/plans/` 追踪数量至 M6 归档 `v1.8.27`）并同步内部路径与 `1.90.0` 指向。
- 当前 commit 与状态：规则、版本脚本与单测均经 `verify_local_gate.py --skip-flutter-tests` 验证通过，L0 保持 `32 + 24 = 56 <= 80` 行，`pubspec.yaml` 与 `AppVersion` 仍为 `1.8.28+122`。
- 下一步待办：由维护者拍板启动 [2026-11-24-v1.8.29-设备提醒矩阵与同步边界加固方案.md](../plans/2026-11-24-v1.8.29-设备提醒矩阵与同步边界加固方案.md) Stage 1（M6 归档 `v1.8.27` 后入库）；正式发版待明确指令后按 `1.90.0` 冻结。

## 2026-11-24 · 1.8.28+122 自测包收口（置顶持久化 + 隔离 androidTest + 工作流固化）

- 已完成改动：Gate 通过后固化「Stage 1 → 独立 Gate → 升 `Z+1` 原签名自测 → MuMu 基础冒烟与核心路径 → dev 文档 → 下一轮提示词」闭环（`AGENTS.md`、`VALIDATION.md`、开发指南），明确 Gate 后直接打自测包、不逐轮询问 A/B；版本升至 `1.8.28+122`（仅 `pubspec.yaml` 与 `AppVersion`）；从 `772fe67` 的 `git archive` 干净 ASCII 输入、本机缓存 `--no-pub` 构建原签名双 ABI Release APK，并完成 MuMu「学习通」保数据覆盖与实屏验收。
- 当前 commit 与状态：工作流 `0343a06`、版本 `772fe67`；APK `62109666` 字节、SHA-256 `039dd33ea1d091d8bbdae42924b67b4fc5fe1d9fdd457cf8976623c138464087`，包名 `com.example.studyassistant.journal`、`1.8.28 (122)`、min26/target36、ARM64/x86_64、非 debuggable、v2 证书 `d36a5715...`、16 KiB 对齐与 ZIP 472 条目 CRC 全通过。MuMu `127.0.0.1:16448` 覆盖安装成功，`firstInstallTime=2026-11-04 19:05:10` 保留、设备 `base.apk` 哈希一致；冷启动 2335ms，全程 logcat 0 条 `FATAL/FlutterError/RenderFlex overflowed`。实屏核对：登录态、40 门课程与 80 项课业保留，「关于我们」显示 `1.8.28 (122)`；手动待办与学习通作业按时间混排；置顶/取消置顶、拖拽调序在杀进程重启后保持；逾期项默认置底且可手动置顶；完成与撤销、统计 24/39 与往期 33/41 下钻、日历议程、提醒设置页均正常。截图与日志在 `D:\campus-tools\build-work\cx1828-preview-772fe67-20261124-170537`；临时条目 `QA1828-*` 已删除、置顶已清空、首页恢复「时间近到远 / 全部 / 全部」。未刷新学习通线上接口；仅误触外链打开一次作业页并取消签到弹窗，未提交任何内容。
- 下一步待办：按 [ROADMAP](../ROADMAP.md#dev-下一阶段) 的下一轮候选方向规划；正式发版仍等维护者主动下达指令后进入 Stage 2（目标 `1.90.0`，构建号顺延高于 `+122`）。

## 2026-11-24 · 1.8.28 Stage 1 完成：置顶持久化修复与隔离 androidTest 112 项通过

- 已完成改动：`assignment_manual_pin_test.dart` 新增可控仓库夹具与 6 项回归（修前 #1/#2/#5/#6 实测红灯，修后 10/10 全绿）；`assignment_store.dart` 将 `_savePins` 改为 `Future<bool>`（`StaleSessionWriteException` 返回 `false` 且不设 `_error`/`_recoveryWarnings`，`LocalStorageLeaseReleaseException` 仍返回 `true` 并记恢复告警），`_togglePinKey`/`reorderPinned` 写后守卫改为 `!persisted || !stillOwned()`，`_prunePins` 仅在 `persisted` 且会话未变时清 `_pinsNeedSave`，`saveNotebook` 补 `_pinsNeedSave ||` 重试入口与 `_prunePins` 后会话守卫（源码净增 20 行）。维护者批准的扩项：`AssignmentNotificationPublisherTest` 改用复用型合成关闭通道 `synthetic-disabled-updates-tests` 并走 internal 重载，移除对生产 `CHANNEL_UPDATES` 的 setUp/tearDown 删除；`run_android_tests.py` 的 `_run` 显式 `encoding="utf-8", errors="replace"`，`test_run_android_tests.py` 增 1 项回归。
- 当前 commit 与状态：`ef0e39a`（修复 + 6 回归）、`3de0f59`（夹具与脚本，3 文件）已推送 `origin/dev`。M2 定向门禁退出码 0（8 文件 105 项、`dart analyze` 0 问题）；扩项后 M4 最终门禁 9 组 Python 100 项全过、L0 55 行。M3 用新 ASCII 镜像 `D:\campus-tools\build-work\androidtest-1828-20261124-155743`（JDK 17 + `D:\campus-tools\android`，`:app:testDebugUnitTest :app:lintDebug :app:assembleDebug :app:assembleDebugAndroidTest` 全部成功）在隔离 MuMu `127.0.0.1:16384`（API 32、`x86_64`、`Asia/Shanghai`）实跑：batch1 `20/0/0/0`、batch2 `80/0/0/0`、batch3 `10/0/2/2`，合计 112 项 110 通过、2 假设跳过、0 失败；`AssignmentNotificationPublisherTest#unknownTimeNewAssignmentPublishesSilentlyOnSilentChannel` 为 `STATUS_CODE=0`；跳过项为 `FeedbackEmailLaunchTest#systemCanOpenTheFixedMailtoDraftWhenAHandlerExists`（无邮件客户端）与 `RealAccountHeadlessEntryTest#realSessionRunsDaytimeBackgroundCheck`（未传 `-e realAccount true`）。未设 `PYTHONUTF8` 直接运行脚本退出码 0，日志 `androidtest-3batches.log`、`gradle-build.log` 均在该构建目录。保护实例 `127.0.0.1:16448` 仍 `1.8.27+121`、`firstInstallTime=2026-11-04 19:05:10`。
- 下一步待办：Stage 1 已完成并停机，进入本方案独立 Gate 审查（建议 Diff 区间 `bff9e7c..HEAD`）；Gate 通过后再决定升 `1.8.28+122` 打 MuMu 自测包或进入 `v1.9.0` Stage 2。

