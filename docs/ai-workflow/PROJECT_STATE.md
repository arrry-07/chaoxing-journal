# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（正式版 1.90.0+127；dev 自测至 1.90.3+130）

- **1.90.0+127 正式基线**：PR `#65` 合入 `ea64137`，annotated Tag `v1.90.0`（`733ea66` → `ea64137`），GitHub Release `458482127`（`latest`），Gitee `update-manual.json` 与 `update-stable.json` 双索引均已同步至 `1.90.0+127`，详见[验收与发布记录](../reviews/2026-11-25-v1.90.0-体验重构配色转场与提醒正式发布验收记录.md)。
- **dev 当前收口（`1.90.3+130` 自测包已通过 MuMu 保数据浅/深双主题验收）**：在 `1.90.2+129` 基础上围绕[v1.90.3 方案](../plans/2026-11-26-v1.90.3-主页光学质感顶栏像素伙伴与阻尼弹簧方案.md)交付 `M1` 主页光学纸感层次（随滚动淡出双径向氛围光晕、`JournalGroupedCard`/`JournalSliverGroupedCard` 双层柔影与顶边细高光、仅「今天/置顶」钴蓝微染与 3dp 柔光竖条）、`M2` 顶栏暖陶珊瑚橙像素伙伴（纯 `CustomPainter` 5 态、零 `pumpAndSettle()` 超时单次空闲定时器、悬浮顶栏迷你联动、无框状态行旋转星芒与 2 秒互动短语、`DisplayPreferences.showPixelBuddy` 一键开关）及 `M3` 全站高频阻尼弹簧微交互（`criticalSpring`/`pressSpring`/`popSpring`/`criticalCurve`、`JournalPressableScale`、`JournalMicroBounce`、统计 4 档滑块、折叠箭头、弹窗上拉橡皮筋回弹与原位完成微弹）；经三轮跨厂商 `gpt-6.2-sol (high)` 独立审查与两轮返工+最终 2 文件直修，通过 `TZ=UTC verify_local_gate.py --mode full`（`+2092 ~1` 0 超时/0 失败、128 项 Python 单测、`dart analyze` 0 问题）及终版 10 文件 117/117 定向门禁；已构建原签名双 ABI 自测包 `1.90.3+130`（`64,214,866` B，SHA-256 `0eee2067...`）并在 MuMu「学习通」保数据完成 15 张浅/深双主题与单次刷新（`15:09` → `15:44`）目视验收（`logcat` 0 崩溃/0 溢出），详见[dev 本地状态](DEV_STATE.md)；未动 `main` / Tag / Release / Gitee。

## 最近 2 个正式发布版本

- **1.90.0+127（当前正式版，2026-11-26）**。PR `#65` 合入 `ea64137`，`v1.90.0` 指向 `ea64137`（汇总交付 `v1.8.32`–`v1.8.34`）：全站手记钴蓝主色与晴空天蓝逾期语义统一、取消逾期标题灰化与浅色辅助墨色加深、一级零重影瞬切与二级不透明视差横滑（保留 Android 14+ 预测性手势返回）、作业/待办毛玻璃悬浮顶栏与统一 `JournalExpansionTile`、课程「未分组」源头补提/去噪/批量归类与官方活动课自动屏蔽、待办双区滑动与「我的」3 合 1 精简、全套 4 渠道内置提示音有声 `v2` 通知（`SQLite v9`）及冷启动仅读稳定通道收敛。Gitee `manual` 与 `stable` 均推进至 `1.90.0+127`。[验收与发布记录](../reviews/2026-11-25-v1.90.0-体验重构配色转场与提醒正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.90.0)
- **1.8.31+124（上一正式版，2026-11-25）**。PR `#64` 合入 `77b5e8a`，`v1.8.31` 指向 `77b5e8a`（汇总交付 `v1.8.27`–`v1.8.31`）：首页手动课业混排与置顶持久化、`M1–M7`（待办/完整课程筛选、实色对比度提升与非危险红收敛、中文本地化、日历彩点图例、待办详情、`personal_schedule_v2` 与系统静音提示），以及向后兼容存储升级与待办附件（拍照/9 图/20 MB 文件/全屏画廊/系统打开/生命周期清理）。[验收与发布记录](../reviews/2026-11-25-v1.8.31-体验升级与待办附件验收与发布记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.31)

## 待补证与按需入口

- 隔离 API 26/30/31/32/33/34/35 已覆盖 4 批 22 类 `androidTest` 0 失败；物理 OEM 真机复测 `v2` 有声渠道与锁屏/Doze/后台限流、自然 `9010`、`backclazzdata` 新字段存在率与官方活动课精度、真实改期/`completeTime` 样本仍待按样本补证。
- `FB-002`、30 天发布时间/活动性质核实、`AssignmentStore` 解耦及云端同步/反馈（`FB-015` / Supabase）规划见[反馈台账](../待处理体验反馈.md) 与 [路线图](../ROADMAP.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
