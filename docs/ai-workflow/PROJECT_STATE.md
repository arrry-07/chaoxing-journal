# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（正式版 1.90.0+127；main 与 dev 已同步）

- **1.90.0+127 已正式发布收口**（PR `#65` 合入 `ea64137`，annotated Tag `v1.90.0` `733ea66` → `ea64137`，GitHub Release `458482127` 于 2026-11-26 公开并设为 `latest`），详见[验收与发布记录](../reviews/2026-11-25-v1.90.0-体验重构配色转场与提醒正式发布验收记录.md)。
- **验证与分发交付**：`v1.8.32`–`v1.8.34` 均通过多轮异构 Gate PASS（最终 Gate 3 `Carbon high` 0 阻断 / 0 中级 / 0 次要）；PR `#65` / `main` / Tag `v1.90.0` 全量三时区与 Android Gradle/Lint CI、`site-release-dispatch` 及 `gitee-release-sync`（含 `promote_stable=true`）全部 `success`；原签名双 ABI 正式包（`64,054,782` B，SHA-256 `c3a85faa...`）五方回下载一致，在 **MuMu「学习通」**（API 35）保数据覆盖通过全量 5 项浅/深主题检查且 `logcat` 零崩溃；Gitee `update-manual.json` 与 `update-stable.json` 双索引均回读确认为 `1.90.0+127`（未上传 Gitee APK 镜像）。
- **当前分支基线**：`v1.8.33` / `v1.8.34` 方案与 `v1.8.26` 验收均已随本次发布收口归档，`docs/plans/` 已清空；`main` 与 `dev` 已同步至本收口提交，详见[dev 本地状态](DEV_STATE.md)。

## 最近 2 个正式发布版本

- **1.90.0+127（当前正式版，2026-11-26）**。PR `#65` 合入 `ea64137`，`v1.90.0` 指向 `ea64137`（汇总交付 `v1.8.32`–`v1.8.34`）：全站手记钴蓝主色与晴空天蓝逾期语义统一、取消逾期标题灰化与浅色辅助墨色加深、一级零重影瞬切与二级不透明视差横滑（保留 Android 14+ 预测性手势返回）、作业/待办毛玻璃悬浮顶栏与统一 `JournalExpansionTile`、课程「未分组」源头补提/去噪/批量归类与官方活动课自动屏蔽、待办双区滑动与「我的」3 合 1 精简、全套 4 渠道内置提示音有声 `v2` 通知（`SQLite v9`）及冷启动仅读稳定通道收敛。Gitee `manual` 与 `stable` 均推进至 `1.90.0+127`。[验收与发布记录](../reviews/2026-11-25-v1.90.0-体验重构配色转场与提醒正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.90.0)
- **1.8.31+124（上一正式版，2026-11-25）**。PR `#64` 合入 `77b5e8a`，`v1.8.31` 指向 `77b5e8a`（汇总交付 `v1.8.27`–`v1.8.31`）：首页手动课业混排与置顶持久化、`M1–M7`（待办/完整课程筛选、实色对比度提升与非危险红收敛、中文本地化、日历彩点图例、待办详情、`personal_schedule_v2` 与系统静音提示），以及向后兼容存储升级与待办附件（拍照/9 图/20 MB 文件/全屏画廊/系统打开/生命周期清理）。[验收与发布记录](../reviews/2026-11-25-v1.8.31-体验升级与待办附件验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.31)

## 待补证与按需入口

- 隔离 API 26/30/31/32/33/34/35 已覆盖 4 批 22 类 `androidTest` 0 失败；物理 OEM 真机复测 `v2` 有声渠道与锁屏/Doze/后台限流、自然 `9010`、`backclazzdata` 新字段存在率与官方活动课精度、真实改期/`completeTime` 样本仍待按样本补证。
- `FB-002`、30 天发布时间/活动性质核实、`AssignmentStore` 解耦及云端同步/反馈（`FB-015` / Supabase）规划见[反馈台账](../待处理体验反馈.md) 与 [路线图](../ROADMAP.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
