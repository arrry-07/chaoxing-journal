# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办，每段 1–2 句。
> 只写下一个 AI 接手需要的结论与证据指针（commit、APK SHA-256、构建/截图目录路径各一次），不写操作流水、逐项实测叙述和原始日志；详细测试记录留在构建目录或对应计划/验收文档。

## 2026-11-24 · v1.8.30 设备矩阵补齐：API 26/30/31/33/34 全绿

- 已完成改动：为 `v1.8.30` 设备矩阵新建 API 26/30/31/33/34 隔离 AVD，复用 `1.8.29` 同源 debug/androidTest APK 跑 4 批 22 类 116 项；修复 androidTest 的 minSdk 26 兼容（`ReminderSourceScopeTest`/`ReminderDatabaseMigrationTest` 去掉 `SQLiteOpenHelper.use` 改 `try/finally`，`AssignmentNotificationPublisherTest` 的 v1 渠道断言改为「ensureChannels 不改变既有重要性」并加删除等待）。
- 当前 commit 与状态：API 26/30/31/33/34 分别 111/111/112/114/115 通过、0 失败（其余为 API/环境假设跳过），均 Doze `IDLE → reset`；API 32/35 沿用 `1.8.29` 证据（111 通过/5 跳过 与 115 通过/1 跳过）。日志在 `D:\campus-tools\build-work\androidtest-api{26,30,31,33,34}-20261124.log`；仅测试代码变更，未改 App 源码/版本/签名，未新建预览包。
- 下一步待办：物理 OEM 真机只读体检需设备授权；回归发现的两个 UI/文案问题仍待下一轮产品收口，正式发版仍等维护者指令。

## 2026-11-24 · 1.8.29+123 完整功能回归通过（主实例保数据 + 隔离破坏性）

- 已完成改动：对 `1.8.29+123` 原包（SHA-256 `0749a144…`）在 MuMu「学习通」`127.0.0.1:16448` 完成完整回归：首页混排与双向排序/逾期置底、筛选/搜索、置顶拖拽及冷启持久化、完成撤销、手动待办增删、详情/提醒状态、日历月周与议程、统计 24/39 与往期 33/41 下钻及关注恢复、提醒权限与测试通知、更新检查、40 门课程/42 条通知/桌面小组件与双击返回；仅集中线上刷新 1 次（扫描 38 门，跳过往期/归档 2 门）。隔离 `127.0.0.1:16384`（API 32）完成 1.7.3→`1.8.29` 原地升级、清数据首启、登录校验/协议页、精确闹钟拒绝降级与通知渠道重建。
- 当前 commit 与状态：回归基线 `711d835`；主实例 `firstInstallTime`、登录态、40 门课程与 80 条记录保持，临时条目/置顶/主题/提醒 3 条/统计关注均已恢复；主/隔离 0 条 App `FATAL/FlutterError/RenderFlex`（仅 `uiautomator` 工具自身退出 SIGSEGV）。证据在 `D:\campus-tools\build-work\cx1829-full-regression-20261124-212529`；非阻断问题：关于对话框按钮英文、夜间静音个人日程导致首页持续显示「提醒或小组件需要处理」，另有一条考试通知详情疑似重复待样本核对。
- 下一步待办：按 [ROADMAP](../ROADMAP.md#dev-下一阶段) 规划 `v1.8.30`；`docs/plans/` 保持 3 份现状，正式发版仍待维护者指令（目标 `1.90.0`）。

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

