# 当前工程状态

更新时间：2026-11-21（Asia/Shanghai）。本文件为滑动窗口工作摘要，接手时须核对现场 Git、源码与远端状态。**维护约定：始终只保留“当前目标 + 最近 2 个已发布版本 + 下一补丁待办”，正文控制在 80 行以内；更早版本与发布前候选记录滚动归档至[工程状态历史归档](../archive/PROJECT_STATE_HISTORY.md)。**

## 当前目标与范围

- **当前工作流口径（2026-11-20 轻量化优化）**：
  - **两段式分工与攒批发布**：常规修复优先先做只读会诊并输出带定位与替换口径的原子方案，再集中施工、离线合成回归与定向自测；将同周期的 2–4 个独立问题合入同一个补丁版本一次性走完 PR、CI、MuMu 验收与正式 Release，避免单点小修反复走全套发版流程（紧急热修或明确单点指令除外）。
  - **本地快检 vs. 云端 CI**：开发/施工阶段本地只跑 `flutter analyze --no-pub`、`check_changed_format.py` 及本次修改直接涉及的定向 `test/*_test.dart`；1500+ 全量 Flutter 测试、三时区核心套件与 Gradle 检查交由 PR/main/Tag GitHub Actions CI 承接。
  - **一键验包与验收模板**：正式包与候选包统一运行 `python scripts/verify_apk_and_report.py <apk> --expected-version <X.Y.Z+CODE>`，自动完成大小、SHA-256、双 ABI、16 KiB 对齐、ZIP CRC、包元数据与 v2 证书核对并输出标准 Markdown 验收段落。
  - 完整规则见 [AGENTS.md](../../AGENTS.md) 与 [持续迭代与验证范围](VALIDATION.md)。

## 最近 2 个正式发布版本

- **当前正式发布版本：1.8.21+88（2026-11-21）**：
  - [PR #58](https://github.com/arrry-07/chaoxing-journal/pull/58) 合入 `30d5d70306783f22364db08b9df6946e18fd2788`（应用目录同 `4f6e7eb`），annotated Tag `v1.8.21` 对象 `080b989c029d84c0b76a8613270fef636424786e`，GitHub Release `453099223` 已公开为 latest。原签名包 60,777,470 字节，SHA-256 `d7a498451c1a656a1de73d92e2c3be3ffbf41f4a3ed06647455b548d437087e0`。
  - 修复正常考试降级假 `partial` 与 `lastSyncAt` 阻断，收敛 Vue 课程入口探测上限至 3 门防刷新风暴，补齐跳转型 PC 考试、`9010`/跨域验证 Cookie 导入去重、PC 补充熔断恢复与跨年改期锚定。PR `44797283557`/`44797297297`、main `44799227994`、Tag `44801135958` 全绿（UTC 1549 passed / 1 skipped），草稿及匿名回下载同哈希。原 MuMu 保留 `firstInstallTime` 与本机数据，单次真实刷新推进最近完整同步至 `03:01`（40 门课 `课程入口` 8 次、0 HTTP 失败，首页 `03:01 更新`、问题明细为空）。
  - Gitee `index` `44865145027` 成功，`manual=1.8.21+88` 指向 GitHub 且无 `backupApkUrl`，`stable=1.8.0+67`，APK 镜像仍为 `v1.7.52`。MuMu 检查更新显示当前已是最新。详见[验收与发布记录](../reviews/2026-11-21-1220-1.8.21同步完成态收口与验证续接验收与发布记录.md)。

- **上一正式发布版本：1.8.20+87（2026-11-20）**：
  - [PR #57](https://github.com/arrry-07/chaoxing-journal/pull/57) 合入 `4b5ca5009e49f2f2c9254b112c561cfdf7ea2bea`，annotated Tag `v1.8.20` 对象 `c8811f7df904d6217e92be1e67f5f307594e7892`，GitHub Release `452858212` 已公开。原签名包 60,711,854 字节，SHA-256 `e9f921bae2c38cbceced9c63d1b378caec0281eeccc267ab538847e2905b053e`。
  - 修复课程考试分页保留、PC 熔断隔离、人工验证后的跨阶段暂停、通知年份与改期文案。PR/main/Tag CI 通过，MuMu 保数据覆盖并通过单次刷新与检查更新，Gitee `manual=1.8.20+87`。详见[验收与发布记录](../reviews/2026-11-20-2328-1.8.20考试读取恢复与通知改期验收与发布记录.md)。

## 下一补丁待办（2026-11-21 更新）

- **P1**：收集自然 9010 触发后的跨域验证续接/取消/换账号/重启、真实连续失败恢复、跨年及改期通知（含 `completeTime`）与仅 PC 可见课程考试样本；同账号可比耗时对比；小步加固 `enrichNotices` 缺年锚定覆写、`verifyInBrowser()` Cookie 解析容错及 `clazzId` 驼峰兼容。
- **P2**：继续按[反馈清单](../待处理体验反馈.md)补齐课程群云历史（FB-002）、30 天新发字段、课程通知自然故障、隔离完整备份演练与实体机矩阵。

## 快速参考与归档

- 历史版本与发布前候选记录：[工程状态历史归档](../archive/PROJECT_STATE_HISTORY.md)
- 剩余问题台账交接：[1.8.16 全量剩余问题闭环交接](handoffs/2026-11-19-1320-1.8.16全量剩余问题闭环交接.md)
- 文档索引与开发规范：[文档索引](../README.md)、[持续迭代与验证范围](VALIDATION.md)、[开发与贡献](../guides/开发与贡献.md)、[贡献约定](../../CONTRIBUTING.md)
- 保留无关未跟踪目录：`docs/feedback/`、`scripts/demo-video/`（提交时勿纳入）。

## 新对话接手提示

> 请先读取实际仓库的 `AGENTS.md` 和 `docs/ai-workflow/PROJECT_STATE.md`，核对当前分支、HEAD、未提交修改与暂存区，再按我本轮给出的目标继续。开发阶段本地只跑 `flutter analyze --no-pub` 与受影响的定向测试，全量测试与三时区交由云端 CI；仅按需读取相关计划、验收记录或历史归档，保留已有修改，不把历史报告当作当前已验证结果。
