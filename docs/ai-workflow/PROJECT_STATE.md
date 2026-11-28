# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（正式版 1.93.0+136；dev 与 main 已同步收口）

- **1.93.0+136 正式基线（当前最新）**：PR [#72](https://github.com/arrry-07/chaoxing-journal/pull/72) 合入 `e7e3408`，annotated Tag `v1.93.0`（`5f4b3f32` → `e7e3408`），GitHub Release `460984901`（`latest`，`64,738,962` B，SHA-256 `59e54262...`）与 Gitee `v1.93.0` Release（`1378249`）APK 镜像均已就绪并完成匿名完整回下载与 `aapt`/`apksigner`/SHA-256 核验；MuMu「学习通」（API 35）保数据覆盖双主题 12 屏审图 **`OVERALL: PASS`**（`logcat` 0 崩溃/0 溢出，4 条 `v3` 渠道就绪，真实账号本学期 0「提交未知」）；Gitee `update-manual.json` 与 `update-stable.json` 双清单均已切至 `1.93.0+136`（Gitee 主链 + GitHub 备用，`site-release-dispatch` 因未配 `SITE_DISPATCH_TOKEN` 明确失败）。详见[验收与发布记录](../reviews/2026-11-28-v1.93.0-UI精修Clawd屋顶舞台统计口径性能与Gitee自动镜像正式发布验收记录.md)。
- **dev 当前状态**：`dev` 与 `origin/main` 已按本轮收口提交对齐；下一轮 `dev` 修订自 `1.93.1+137` 起步。详见[dev 本地状态](DEV_STATE.md)。

## 最近 2 个正式发布版本

- **1.93.0+136（当前正式版，2026-11-28）**。PR `#72` 合入 `e7e3408`，`v1.93.0` 指向 `e7e3408`（汇入 `v1.92.1` 拆缝、`v1.92.3` 非 UI 修复及 M1–M6）：无阴影暖纸细边与「我的」页降噪及 GitHub Star 引导、首页 `31dp` 屋顶净空带 Clawd 文字舞台与 3 套新动作及四主页统一 `34dp` 尺寸、无 `courseKey` 三层学期归属根治跨学期「提交未知」并隔离纯广播分母、`45°` 斜纹逾期段与内嵌「各课程待处理 · 共 N 门」、LRU 拼音零分配排序/单槽投影缓存/`> 32 KiB` 解析与写盘校验移入 `Isolate.run` 及 Gitee 两步同步改造。[验收与发布记录](../reviews/2026-11-28-v1.93.0-UI精修Clawd屋顶舞台统计口径性能与Gitee自动镜像正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.93.0)
- **1.92.0+132（上一正式版，2026-11-26）**。PR `#67`–`#69` 最终合入 `55e5d6e`，`v1.92.0` 指向 `55e5d6e`：应用级单一真源 `ClawdCompanionController` 与三档显示、等高 `38dp` `ClawdTitleStage`、去蓝星暖纸反差萌气泡、四主栏轻客串、零体积 8 项原生 `48 kHz` 8-bit 芯片音效、试听异步化与 DND 检测、`JournalExpansionTile` 统一及会话守卫收口。[验收与发布记录](../reviews/2026-11-26-v1.92.0-Clawd2.0文字舞台8bit音效与轻量收口正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.92.0)

## 待补证与按需入口

- 隔离 API 26/30/31/32/33/34/35 已覆盖 4 批 22 类 `androidTest` 0 失败；物理 OEM 真机（120Hz、锁屏外放、Doze）、多校 `backclazzdata`/活动课精度、自然 `9010`、`FB-002`、改期/`completeTime` 样本及 Gitee APK 跨境补传仍待按节奏补证；下一步优先立项 Supabase `FB-017`/`FB-015` 及收口 `chaoxing_local_client`/`Isolate.run`/小组件日差轻债，详见[反馈台账](../待处理体验反馈.md)、[路线图](../ROADMAP.md)与[架构导航](../architecture/ARCHITECTURE.md)。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)
