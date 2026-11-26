# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（正式版 1.90.0+127；dev 自测至 1.90.2+129）

- **1.90.0+127 正式基线**：PR `#65` 合入 `ea64137`，annotated Tag `v1.90.0`（`733ea66` → `ea64137`），GitHub Release `458482127`（`latest`），Gitee `update-manual.json` 与 `update-stable.json` 双索引均已同步至 `1.90.0+127`，详见[验收与发布记录](../reviews/2026-11-25-v1.90.0-体验重构配色转场与提醒正式发布验收记录.md)。
- **dev 当前收口（`1.90.2+129` 自测包已通过 MuMu 保数据验收）**：在 `1.90.1+128` 闭环基础上新增无作业/无通知课程的 `backclazzdata` 开课/创建时间补提（禁读模板 `course.createtime`）、`AcademicTerm.fromCourseCreationInstant` 与单调 `clazzId` 同批时段推断（`CourseTermSource.clazzCohort`），通过 `TZ=UTC verify_local_gate.py --mode full`（`+2054 ~1`、`128` Python 单测、`dart analyze` 0 问题）；已构建原签名双 ABI 自测包 `1.90.2+129`（`64,149,178` B，SHA-256 `f950b33b...`）并在 MuMu「学习通」保数据验收通过（`本学期`/`本学年` 15 门、`往期` 23 门、`全部学期` 38 门、`我的课程` 0 未分组、`logcat` 0 崩溃），详见[dev 本地状态](DEV_STATE.md)；未动 `main` / Tag / Release。

## 最近 2 个正式发布版本

- **1.90.0+127（当前正式版，2026-11-26）**。PR `#65` 合入 `ea64137`，`v1.90.0` 指向 `ea64137`（汇总交付 `v1.8.32`–`v1.8.34`）：全站手记钴蓝主色与晴空天蓝逾期语义统一、取消逾期标题灰化与浅色辅助墨色加深、一级零重影瞬切与二级不透明视差横滑（保留 Android 14+ 预测性手势返回）、作业/待办毛玻璃悬浮顶栏与统一 `JournalExpansionTile`、课程「未分组」源头补提/去噪/批量归类与官方活动课自动屏蔽、待办双区滑动与「我的」3 合 1 精简、全套 4 渠道内置提示音有声 `v2` 通知（`SQLite v9`）及冷启动仅读稳定通道收敛。Gitee `manual` 与 `stable` 均推进至 `1.90.0+127`。[验收与发布记录](../reviews/2026-11-25-v1.90.0-体验重构配色转场与提醒正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.90.0)
- **1.8.31+124（上一正式版，2026-11-25）**。PR `#64` 合入 `77b5e8a`，`v1.8.31` 指向 `77b5e8a`（汇总交付 `v1.8.27`–`v1.8.31`）：首页手动课业混排与置顶持久化、`M1–M7`（待办/完整课程筛选、实色对比度提升与非危险红收敛、中文本地化、日历彩点图例、待办详情、`personal_schedule_v2` 与系统静音提示），以及向后兼容存储升级与待办附件（拍照/9 图/20 MB 文件/全屏画廊/系统打开/生命周期清理）。[验收与发布记录](../reviews/2026-11-25-v1.8.31-体验升级与待办附件验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.31)

## 待补证与按需入口

- 隔离 API 26/30/31/32/33/34/35 已覆盖 4 批 22 类 `androidTest` 0 失败；物理 OEM 真机复测 `v2` 有声渠道与锁屏/Doze/后台限流、自然 `9010`、`backclazzdata` 新字段存在率与官方活动课精度、真实改期/`completeTime` 样本仍待按样本补证。
- `FB-002`、30 天发布时间/活动性质核实、`AssignmentStore` 解耦及云端同步/反馈（`FB-015` / Supabase）规划见[反馈台账](../待处理体验反馈.md) 与 [路线图](../ROADMAP.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
