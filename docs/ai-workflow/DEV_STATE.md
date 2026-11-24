# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办。

## 2026-11-24 · v1.9.0 Stage 1：置顶修复完成、隔离 androidTest 阻塞

- 已完成改动：`assignment_manual_pin_test.dart` 新增可控仓库夹具与 6 项回归（修前 #1/#2/#5/#6 实测红灯，修后 10/10 全绿）；`assignment_store.dart` 将 `_savePins` 改为 `Future<bool>`（`StaleSessionWriteException` 返回 `false` 且不设 `_error`/`_recoveryWarnings`，`LocalStorageLeaseReleaseException` 仍返回 `true` 并记恢复告警），`_togglePinKey`/`reorderPinned` 写后守卫改为 `!persisted || !stillOwned()`，`_prunePins` 仅在 `persisted` 且会话未变时清 `_pinsNeedSave`，`saveNotebook` 补 `_pinsNeedSave ||` 重试入口与 `_prunePins` 后会话守卫（源码净增 20 行）。
- 当前 commit 与状态：代码与回归 `ef0e39a` 已推送 `origin/dev`；`verify_local_gate.py --tests <8 文件>` 退出码 0（Flutter 105 项、`dart analyze` 0 问题、9 组 Python 99 项、L0 55 行）。M3 在隔离 MuMu `127.0.0.1:16384`（API 32、`x86_64`、`Asia/Shanghai`）用 ASCII 镜像构建（`D:\campus-tools\build-work\androidtest-1828-20261124-153020`）实跑 3 批 21 类 112 项：batch1 19 通过/1 失败、batch2 80 通过、batch3 10 通过/2 假设跳过。失败项为 `AssignmentNotificationPublisherTest#unknownTimeNewAssignmentPublishesSilentlyOnSilentChannel`：同批 `aDisabledChannelKeepsNewAssignmentPending` 先把 `assignment_updates` 建为 `IMPORTANCE_NONE` 并删除，Android 按同 id 重建时恢复旧 `importance`（应用侧 `createNotificationChannel` 无法改回），而发布前对 `CHANNEL_UPDATES` 的预检先于静默通道切换，故返回「对应通知通道已关闭」。该用例单跑 `STATUS_CODE=0`；最小复现对日志 `repro-channel-order-pair.log`、完整批次日志 `androidtest-3batches.log` 均在上述构建目录。保护实例 `127.0.0.1:16448` 仍 `1.8.27+121`、`firstInstallTime=2026-11-04 19:05:10`。
- 下一步待办：M3 未达方案「0 失败」判据，Stage 1 停工待裁决：修复 Kotlin `androidTest` 通道夹具（需扩项，超出本方案非目标）或接受该环境性失败并记录豁免；处理后再补跑 M3、完成 M4 状态回写并进入独立 Gate。

## 2026-11-24 · v1.9.0 下一阶段只读调查与方案定稿（置顶持久化与隔离设备 androidTest）

- 已完成改动：在基线 `0604293` 完成只读源码核实，并用仓外临时测试确认修前行为：`_savePins` 吞掉 `StaleSessionWriteException` 后，`_togglePinKey`（`togglePin`/`toggleManualPin`）与 `reorderPinned` 误返回 `true` 且污染内存 `_pinned`、`_prunePins` 误清 `_pinsNeedSave` 阻断后续 `refreshAssignments()`/`saveNotebook()` 补写重试；同时核对 `saveNotebook` 缺 `_pinsNeedSave ||` 与 `_prunePins` 后会话守卫，而 `_afterAssignmentsChanged` 及其 13 处提醒更新调用方已有 `_isSessionCurrent(snap)` 保护。已输出 Stage 1 → Gate → Stage 2 规格书 [v1.9.0 置顶持久化与隔离设备仪器测试方案](../plans/2026-11-24-v1.9.0-置顶持久化与隔离设备仪器测试方案.md)。
- 当前 commit 与状态：未改应用/测试/脚本代码（`pubspec.yaml` 仍 `1.8.27+121`）；仓外复现测试 `1 passed / 0 failed`（实测确认 4 项修前异常）；核验隔离 MuMu `127.0.0.1:16384`（API 32、`x86_64`、`Asia/Shanghai`）在线可重装，保护实例 `127.0.0.1:16448`（API 35、`1.8.27+121`、`firstInstallTime=2026-11-04 19:05:10`）完好，并确认工作树 `android/local.properties` 指向 `C:\rea-tools\android` 故隔离构建须用纯 ASCII 镜像写入 `D:\campus-tools\android` + `JDK 17` 预编译后传 `--skip-build`。
- 下一步待办：按 [v1.9.0 置顶持久化与隔离设备仪器测试方案](../plans/2026-11-24-v1.9.0-置顶持久化与隔离设备仪器测试方案.md) 执行 Stage 1（M1 红灯回归 → M2 最小修复 → M3 隔离 MuMu 112 项实跑取证 → M4 状态回写），完成后停机进入独立 Gate 审查。

## 2026-11-24 11:55 · 1.8.27+121 首页混排阶段 MuMu 自测

- 已完成改动：`700f95f` 的 `super.repository` 修复已过代码 Gate。阶段自测升至 `1.8.27+121`，使用原签名构建双 ABI 预览包。新流程见 [验证规则](VALIDATION.md#先确定本次终点)。
- 当前 commit 与状态：APK 以 `700f95f` 加本次两个版本字段为构建输入，校验包名、v2 原证书、双 ABI、16 KiB 对齐和 ZIP CRC 通过，SHA-256 `64b813c1c1bde42bb39bb84be5b84d8fdd9e58ea164dcfc00d3385b29f18a9a4`。MuMu「学习通」保数据覆盖成功，安装版本 `1.8.27+121`，首次安装时间仍为 `2026-11-04 19:05:10`，设备 `base.apk` 哈希一致。5 个定向 Flutter 文件 58 项、9 组 Python 99 项通过，严格 Dart 分析 0 问题。原始记录在本机 `cx1827-preview-700f95f-20261124-114748` 构建目录。
- 13:08 界面复验：T3 已接入同一 MuMu「学习通」（Android 15），设备 APK 哈希复核一致。应用正常打开，登录态、40 门课程、既有课业及原筛选保留。新建并选择已同步课程后，带时间的待办按时间与同日学习通作业混排，出现在同日日历议程。长按可置顶，完成后退出首页并自动退顶，撤销恢复到日期组。未置顶的逾期待办在两种时间排序下都进入底部逾期分组。测试条目已删除，首页已恢复「7 天内／时间近到远」。
- 13:08 复测补充：逾期置顶规则已确认为「可手动置顶，未置顶的仍在底部」，方案与开发指南已同步。近到远与远到近两种排序下，学习通逾期作业和手动逾期待办均实测可置顶进入顶部置顶区，取消置顶后回到原逾期位置；混合置顶区可拖拽调序，取消置顶作业后手动待办仍保留。
- 14:52 收尾补测：新建无时间待办落在「无截止日期」分组；统计仍为 `24/39`，手动待办未计入平台分母。勾选完成后条目退出首页并出现带「撤销」的提示，`我的 → 个人安排 → 个人待办与考试` 显示「未安排时间 · 个人已完成」，完成态跨页一致。带时间并开启提前 30 分钟提醒的待办在日历 11 月 25 日议程可见，`dumpsys alarm` 已出现该待办对应的精确闹钟（`2026-11-25 13:30`，`ScheduledNotificationReceiver`），实际弹窗投递需到时间点才能观察。工程脚本：androidTest 清单 21 类/3 批通过；受保护实例 `127.0.0.1:16448` dry-run 被拒绝（退出码 2）；`freeze_release.py --check` 通过；`test_check_release_metadata.py` 7 项通过。全部测试待办（`QA no-date`、`QA remind`、`MuMu QA 1827 followup`）已删除，个人安排页为空，首页恢复「时间近到远」。

## 2026-11-24 · v1.9.0 Stage 1 Gate 增量返工

- 已完成改动：切号回归实际恢复账号 B 后检查手记和置顶隔离。360dp 常规字号手动卡片避让完成按钮，并与学习通卡片对齐拖拽手柄。置顶保存后仅检查会话归属，学习通空课名保留为空，缺年考试投影仅用于普通时间轴。仪器测试脚本识别结果 `shortMsg`、`INSTRUMENTATION_FAILED` 与停在 `STATUS_CODE=1` 的用例。
- 当前 commit 与状态：`640916d` 基于 `d97ba40`，版本为 `1.8.26+120`。本地门禁脚本退出码为 0，7 个 Flutter 文件 91 项（含 `FB-005`）、9 组 Python 共 99 项通过。原日志中 Dart 分析有 1 条 `use_super_parameters`，经 Gate 复审确认为阻断。隔离旧实现触发 5 个 Flutter 回归失败，仪器测试清单覆盖 21 个类，受保护设备 dry-run 拒绝执行。门禁日志 `chaoxing-v1.9.0-gate-20261124-112723.log`。
- 下一步待办：静态分析阻断的处理见上条。MuMu 实机界面、隔离仪器测试和云端全量 CI 待相应验收。

## 2026-11-24 · 工作流规则：审查提示词轻量化

- 已完成改动：`VALIDATION.md` 增补「审查/复审提示词只给基线、范围、必读文件、硬边界与输出格式，不替审查模型罗列检查清单」；跨会话记忆同步更新。
- 当前 commit 与状态：本提交为工作流文档；功能 HEAD 仍 `e46538f`，`pubspec` 仍 `1.8.26+120`，未触碰 `main`/Tag/Release。
- 下一步待办：用轻量复审提示词复核 `ba707c5..HEAD`，通过后等维护者发版指令。

