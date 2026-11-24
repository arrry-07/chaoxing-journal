# Context Routing Matrix（分层读取矩阵）

| 层级 | 何时读 | 文档 |
| --- | --- | --- |
| L0 热层 | 默认必读，两份合计最多 80 行 | [项目规则](../AGENTS.md) · [当前迭代和正式基线](ai-workflow/PROJECT_STATE.md) |
| L1 温层 | 验证、验收与发布 | [验证规则](ai-workflow/VALIDATION.md) · [最近两版的验收导航](验收.md) · [变更日志](../CHANGELOG.md) |
| L1 温层 | 需求与在途工作 | [路线图](ROADMAP.md) · [反馈台账](待处理体验反馈.md) · `plans/` 当前方案与 `ai-workflow/handoffs/` 有效交接由状态页按需链接 |
| L1 温层 | 安装、开发、隐私、分发与取证 | [安装与使用](guides/安装与使用.md) · [开发与贡献](guides/开发与贡献.md) · [隐私与安全](guides/隐私与安全.md) · [更新渠道与国内分发](guides/更新渠道与国内分发.md) · [专题取证](research/) |
| L2 冷层 | 默认禁读，仅在用户明确点名追溯某个历史版本时定向访问 | [归档目录](archive/) |

所有 AI Agent 在日常开发、排查及审读时严禁主动扫描、遍历或读取 `docs/archive/**`。搜索内容时排除归档，例如 `rg -g '!docs/archive/**'`。日常 `dev` 先读 L0，再按当次任务选 L1 和相关源码、测试。

## 唯一事实源（SSOT）

- 当前进度、正式基线和两版验收入口由 [PROJECT_STATE.md](ai-workflow/PROJECT_STATE.md) 维护。正式版本身份核对应用源码、Git Tag 与 GitHub Release。
- 已交付的用户可见变更查 [CHANGELOG.md](../CHANGELOG.md)。源码对象、CI、设备、哈希与分发结果查对应验收记录。验证策略统一维护在 [VALIDATION.md](ai-workflow/VALIDATION.md)。
- 产品优先级查[路线图](ROADMAP.md)，未闭环反馈及补证动作查[反馈台账](待处理体验反馈.md)。[验收导航](验收.md)只维护入口。

## 发布收口与归档

| 活跃目录 | 保留范围 | 退役去向 |
| --- | --- | --- |
| `docs/plans/` | 正在执行或待执行，最多两份 | `docs/archive/plans/` |
| `docs/ai-workflow/handoffs/` | 最新一份仍有效的交接 | `docs/archive/handoffs/` |
| `docs/reviews/` | 最近两个正式版本的验收与发布记录及对应证据 | `docs/archive/reviews/` |
| `docs/ai-workflow/PROJECT_STATE.md` | 当前迭代和最近两个正式版入口 | `docs/archive/PROJECT_STATE_HISTORY.md` |

新增计划、交接、验收文件使用 `YYYY-MM-DD-vX.Y.Z-<主题>.md`：`dev` 分支开发阶段的计划与交接一律使用当前或本轮对应的 `dev` 修订号（如 `v1.8.27`、`v1.8.28`、`v1.8.29`），严禁提前使用未获授权的下一正式版号（如 `v1.9.0`）；仅在维护者明确下达正式发版指令进入 Stage 2 时，才切换并命名下一正式版号（如 `v1.9.0`）。用完或失效即归档。每次正式发布收口提交用 `git mv` 移走本轮完成的方案、失效交接和滑出窗口的验收记录及证据，并滚动工程状态。同步更新状态页、验收导航和受影响的内部链接，再检查链接与活跃数量。计划或交接为空时，目录随新文档创建。
