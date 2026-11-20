# 当前工程状态

更新时间：2026-11-20（Asia/Shanghai）。本文件为滑动窗口工作摘要，接手时须核对现场 Git、源码与远端状态。**维护约定：始终只保留“当前目标 + 最近 2 个已发布版本 + 下一补丁待办”，正文控制在 80 行以内；更早版本与发布前候选记录滚动归档至[工程状态历史归档](../archive/PROJECT_STATE_HISTORY.md)。**

## 当前目标与范围

- **当前工作流口径（2026-11-20 轻量化优化）**：
  - **两段式分工与攒批发布**：常规修复优先先做只读会诊并输出带定位与替换口径的原子方案，再集中施工、离线合成回归与定向自测；将同周期 2–4 个独立问题合入一个补丁版本一次性走完 PR、CI、MuMu 验收与正式 Release，避免单点小修反复走全套发版流程（紧急热修或明确单点指令除外）。
  - **本地快检 vs. 云端 CI**：开发/施工阶段本地只跑 `flutter analyze --no-pub`、`check_changed_format.py` 及本次修改直接涉及的定向 `test/*_test.dart`；1500+ 全量 Flutter 测试、三时区核心套件与 Gradle 检查交由 PR/main/Tag GitHub Actions CI 承接。
  - **一键验包与验收模板**：正式包与候选包统一运行 `python scripts/verify_apk_and_report.py <apk> --expected-version <X.Y.Z+CODE>`，自动完成大小、SHA-256、双 ABI、16 KiB 对齐、ZIP CRC、包元数据与 v2 证书核对并输出标准 Markdown 验收段落。
  - 完整规则见 [AGENTS.md](../../AGENTS.md) 与 [持续迭代与验证范围](VALIDATION.md)。

## 最近 2 个正式发布版本

- **当前正式发布版本：1.8.19+86（2026-11-20）**：
  - **对象与产物**：[PR #55](https://github.com/arrry-07/chaoxing-journal/pull/55) 和补充 [PR #56](https://github.com/arrry-07/chaoxing-journal/pull/56) 已合并，发布源码 `9e3f7d762c60796249fcf7afae03d734e09832f0`，annotated Tag `v1.8.19` 对象 `2e0cdb37b6041bf2db707bd3e1bf9c328ba807ea`，GitHub Release `452760540` 已公开并设为 latest。原签名 APK `60,711,854` 字节，SHA-256 `b57b73b3484b7d87e394cc79e38d9ebbd3052f5cdb946882f67e88f954ca3ec3`。
  - **范围与验收**：修复作业开始／未开放状态的诊断、课程考试补查、考试通知年份与归档、同步课程名和嵌套课程目录。独立审读发现的旧记录降级、缓存参与当轮核对及标题日期冲突已修复。main CI `44744585631` 与 Tag CI `44747728980` 通过，草稿及匿名回下载同哈希。原 MuMu 保留首次安装时间、登录态及 80 项课业，设备 APK 与发布包一致，应用内检查更新返回 1.8.19 (86) 已是最新版本。
  - **分发**：Gitee index `44749667737` 成功，manual 为 `1.8.19+86`、指向 GitHub 且无 `backupApkUrl`，stable 为 `1.8.0+67`，Gitee APK 镜像仍为 `v1.7.52`。详见[正式发布记录](../reviews/2026-11-20-2202-1.8.19同步诊断与考试通知时间验收与发布记录.md)。

- **上一正式发布版本：1.8.18+85（2026-11-20）**：
  - **对象与产物**：PR [#53](https://github.com/arrry-07/chaoxing-journal/pull/53) 合并为 `main` `b541d2ff93e779b29b5f4825ec84761ee6bba569`，annotated Tag `v1.8.18`（object `4631b0f9bfe0783b3d0dea3f0ee5ccb05e95bb58`），GitHub Release `452429233` 已公开且非预发布，发布时设为 `latest`。正式包 `chaoxing-journal-1.8.18.apk` `60,646,402` 字节，SHA-256 `a67a2927ba6dacd6c4f392d7dd19ed08812309c319dc4a060c891c16426476d8`（`.journal`、`1.8.18+85`、min26/target36、ARM64/x86_64、v2 原证书 `d36a5715...`、非 debuggable、16 KiB 对齐通过）。
  - **CI、设备与分发**：PR push/pull CI `44697329689` / `44697393350`、main `44698657267`、Tag `44699799661` 全绿；最终全量 `1502 passed / 1 optional skipped / 0 failed`。MuMu 原实例保数据覆盖保留 `firstInstallTime=2026-11-04 19:05:10`；真实刷新账号考试 `3 条 / 0 待确认`，三场线代显示 `2026年6月9日 / 6月24日 / 7月4日` 且各 `2 条来源`；通知默认 `全部 (73)`、收件箱 `全部 (102)` 并含平台竞赛邀请；start-only 讨论作业显示“截止时间待确认”；应用内检查更新显示“已是最新 1.8.18 (85)”。Gitee `index` `44702186384` 成功，`manual=1.8.18+85` 指向 GitHub 正式包且无 backup，`stable=1.8.0+67`，APK 批量镜像仍为 `1.7.52+59`。详见[1.8.18 发布记录](../reviews/2026-11-20-1.8.18账号考试身份合并通知范围与备份兼容验收与发布记录.md)。

## 下一补丁待办（2026-11-20 更新）

- 课程考试完整读取、连接失败暂停后恢复、真实仅 PC 样本，以及自然 9010 验证后续接继续待确认。
- 补真实通知年份独立佐证和改期呈现，沿用前版 30 天新发来源、课程通知自然故障、首登耗时、备份和设备矩阵的待办。
- 逐项影响、证据与下一步见[发布遗留清单](../待处理体验反馈.md#2026-11-20--181986-发布遗留与-1820-待办)。

## 快速参考与归档

- 历史版本与发布前候选记录：[工程状态历史归档](../archive/PROJECT_STATE_HISTORY.md)
- 剩余问题台账交接：[1.8.16 全量剩余问题闭环交接](handoffs/2026-11-19-1320-1.8.16全量剩余问题闭环交接.md)
- 文档索引与开发规范：[文档索引](../README.md)、[持续迭代与验证范围](VALIDATION.md)、[开发与贡献](../guides/开发与贡献.md)、[贡献约定](../../CONTRIBUTING.md)
- 保留无关未跟踪目录：`docs/feedback/`、`scripts/demo-video/`（提交时勿纳入）。

## 新对话接手提示

> 请先读取实际仓库的 `AGENTS.md` 和 `docs/ai-workflow/PROJECT_STATE.md`，核对当前分支、HEAD、未提交修改与暂存区，再按我本轮给出的目标继续。开发阶段本地只跑 `flutter analyze --no-pub` 与受影响的定向测试，全量测试与三时区交由云端 CI；仅按需读取相关计划、验收记录或历史归档，保留已有修改，不把历史报告当作当前已验证结果。
