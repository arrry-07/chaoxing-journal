# 当前工程状态

<a id="dev-当前迭代进度"></a>

## 当前迭代进度（正式版 1.92.0+132；dev 与 main 已同步收口）

- **1.92.0+132 正式基线（当前最新）**：PR `#67` / `#68` / `#69` 最终合入 `55e5d6e`，annotated Tag `v1.92.0`（`5b7bf90e` → `55e5d6e`），GitHub Release `459719737`（`latest`，`64,607,886` B，SHA-256 `f5fffb04...`），Gitee `update-manual.json` 与 `update-stable.json` 双索引均已推进至 `1.92.0+132`（未传 APK 镜像）；已完成 MuMu「学习通」保数据浅/深双主题 6/6 项实机验收（0 崩溃/0 溢出，4 条 `v3` 有声渠道就绪），详见[验收与发布记录](../reviews/2026-11-26-v1.92.0-Clawd2.0文字舞台8bit音效与轻量收口正式发布验收记录.md)。
- **dev 当前状态**：`1.92.3+134` 日常集成 PR `#71`（云端 CI Run `45976367229` 全绿）已合入 `main`（`0087205`）并同步 `dev`（触发 `main` CI Run `45978296798`）；按维护者实机反馈完整回退 `v1.92.2`/`v1.92.3` 全部 UI 改动至 `v1.92.1` 基线，保留 4 项非 UI 功能修复（北京时间自然日差 UTC 跨夏令时口径、置顶/按课程/整月完整日期、日历说明第 3 条文案修正、课程关注 `operationError` + `accountEpoch` 守卫撤销），双架构原签名包（`64,607,886` B，SHA-256 `f61cf7c0...`）及 MuMu「学习通」+ 华为 `CDY-AN00` 真机 23/23 保数据视觉验收 **`OVERALL: PASS`**，两份方案已归档至 `docs/archive/plans/`，未改正式文档/未打 Tag/未发正式 Release，详见[dev 本地状态](DEV_STATE.md)。

## 最近 2 个正式发布版本

- **1.92.0+132（当前正式版，2026-11-26）**。PR `#67`–`#69` 最终合入 `55e5d6e`，`v1.92.0` 指向 `55e5d6e`：应用级单一真源 `ClawdCompanionController` 与三档显示设置、等高 `38dp` 物理像素对齐 `ClawdTitleStage`（右侧安全区 6 套有限巡逻/摸头爱心短驻留/拎起弹簧落回、0 遮挡标题与 4 按钮）、去蓝星纯粹状态行与避让 `home-sync-status` 的暖纸反差萌气泡、四主栏紧邻标题轻客串（含 `NoTransitionPage` 切页即响应与二级页暂停冒泡）、零体积 8 项原生 `48 kHz` 8-bit 芯片音效、试听异步化与勿扰检测、`JournalExpansionTile` 全仓统一及 `AssignmentStore` 6 处会话守卫收口。Gitee `manual` 与 `stable` 均推进至 `1.92.0+132`。[验收与发布记录](../reviews/2026-11-26-v1.92.0-Clawd2.0文字舞台8bit音效与轻量收口正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.92.0)
- **1.91.0+131（上一正式版，2026-11-26）**。PR `#66` 合入 `5ab698b`，`v1.91.0` 指向 `5ab698b`（汇总交付 `v1.90.1`–`v1.90.4`）：首页悬浮顶栏浅/深双主题渐变毛玻璃与 `18dp` 5 色标渐隐羽化裙边、顶栏 `14×12` 物理像素对齐 Clawd 像素伙伴、主页光学纸感层次与全站阻尼弹簧微交互、课程活动投票与同批 `clazzId` 队列学期精准归类、全套 4 渠道有声 `v3` 通知（`SQLite v10` 安全迁移与通知音量归零告警）及紧凑密度触控修复。Gitee `manual` 与 `stable` 均推进至 `1.91.0+131`。[验收与发布记录](../reviews/2026-11-26-v1.91.0-悬浮顶栏羽化Clawd像素伙伴光学质感与有声v3正式发布验收记录.md) · [GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.91.0)

## 待补证与按需入口

- 隔离 API 26/30/31/32/33/34/35 已覆盖 4 批 22 类 `androidTest` 0 失败；物理 OEM 真机复测 `v3` 有声渠道锁屏外放/通知音量归零/Doze/120Hz 高刷/8-bit 外放与移除动画联动、多校 `backclazzdata` 与 `clazzId` 分布、官方活动课精度、自然 `9010` 及真实改期/`completeTime` 样本仍待按样本补证。
- `FB-002`、30 天发布时间核实及云端同步/反馈（`FB-015` / `FB-017`）规划见[反馈台账](../待处理体验反馈.md) 与 [路线图](../ROADMAP.md)；`v1.92.1` 架构导航图已同步至 `a33f066`（见[架构导航](../architecture/ARCHITECTURE.md)）。
- [仓库规则](../../AGENTS.md) · [文档路由](../README.md) · [验证范围](VALIDATION.md) · [历史工程状态](../archive/PROJECT_STATE_HISTORY.md)（仅按用户点名的版本追溯）
