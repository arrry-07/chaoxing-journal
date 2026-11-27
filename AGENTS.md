# 学习通课业手记

## Context Routing Matrix（分层读取矩阵）

| 层级 | 读取规则 |
| --- | --- |
| L0 热层 | 默认必读本文件与 [PROJECT_STATE.md](docs/ai-workflow/PROJECT_STATE.md)。两份合计最多 80 行。日常 `dev` 以这两份建立项目上下文，修改前核对分支、HEAD、工作区、暂存区及相关代码和测试。 |
| L1 温层 | 按目标点读 [文档索引](docs/README.md)、[验证规则](docs/ai-workflow/VALIDATION.md)、[路线图](docs/ROADMAP.md)、[反馈台账](docs/待处理体验反馈.md)、`docs/guides/`、`docs/plans/` 当前方案及有效交接。查发布证据时从状态页进入最近两版记录。 |
| L2 冷层 | `docs/archive/**` 与 `docs/architecture/*.html`、`*.svg` 默认禁读（已由根 `.ignore` 默认排除搜索）。所有 AI Agent 日常开发、排查及审读时严禁主动扫描或读取归档与渲染 HTML；仅在用户明确点名追溯某个历史版本时定向访问。 |
| Skill 路由 | 动手出方案、改代码、查疑难 Bug、审代码或打包发版前**必查** [Skill 强制路由表](.agents/rules/skill-routing.md)，命中场景须先 `read_file` 加载对应 `SKILL.md`（提示词再长也不得跳过）。 |

## 日常开发与正式发布

- 日常在 `dev` 工作，通过定向快检后提交并轻量推送 `origin/dev`（无需重复确认；阶段收口或停机交接时同步更新 [dev 本地状态](docs/ai-workflow/DEV_STATE.md)，里程碑/打包收口时更新 [PROJECT_STATE.md](docs/ai-workflow/PROJECT_STATE.md)，不必为每个中间小提交重复刷写），细则见[日常推送门禁](docs/ai-workflow/VALIDATION.md#dev-日常推送门禁)。
- 推送 `origin/dev` 前必查 `git status` 与本次提交 Diff，严禁纳入凭据、Cookie、账号响应、敏感日志、`docs/feedback/`、`scripts/demo-video/`、个人材料或 `.apk` 等大体积二进制；日常默认只推 `origin/dev`，可按需开日常集成 PR（`dev → main`）跑全量 CI 并合入 `main`（不改正式文档/下载链、不打 Tag），严禁顺手冻版或发正式 Release（正式发版须等明确指令）。
- 推送完成后，在最终回复末尾固定附两行供代码走查：最新 `origin/dev` 提交号（完整 SHA 与简短信息），以及对比链接 `https://github.com/arrry-07/chaoxing-journal/compare/main...dev` 与核心修改文件的 `dev` 直达链接。
- 本地快检使用缓存依赖，按需运行 `python scripts/verify_local_gate.py --tests <相关测试>`（自带单测超时熔断；涉 Android/Kotlin 改动同步跑 `python scripts/run_android_tests.py --local-fast`；含中文路径时勿直接运行 `flutter analyze`）。
- 修改课业、时间信任或首页筛选时，读[学习通参考实现](docs/guides/开发与贡献.md#学习通参考实现)与[首页课业行为约束](docs/guides/开发与贡献.md#首页课业排序长期约束)。确认逾期在双向时间排序中始终置底，保留 `FB-005` 回归。
- 第三方 API、版本兼容或升级先查锁文件（Flutter 用 `pubspec.lock`），再用 Context7 核对对应版本文档。项目内部逻辑直接检查本地源码和测试。
- 视觉与布局改动须有当前任务的明确要求；功能修复只改必需的可观察界面状态，并在交付中说明。无关视觉问题只记录。
- 保留已有修改和未跟踪的 `docs/feedback/`、`scripts/demo-video/` 及个人材料。凭据、Cookie、账号响应或敏感日志不得进入提交。保持 Flutter、脚本、参考实现与 CI 约定的目录路径。
- **分级研发闭环**：按全局 `staged-release-gate` 分三档推进：① ≤3 文件局部小修，同窗直改快检推送；② 4–12 文件单模块或常规 UI 迭代，先对照 `ARCHITECTURE.md` 落盘 4 模块规格书，新窗 `Orchestrator (Neon)` 单气呵成实现快检 + 1 次零父历史独立 Gate 审查 + 涉 UI 当轮左移打快包上 MuMu 保数据审图；③ 跨模块/双端/状态机重构跑两段式 `/goal` 闭环；测试按功能模块就地维护契约断言（禁新建 `v192x_*_test.dart` 快照文件），随收口代码同笔提交更新 `DEV_STATE.md` 推 `dev`；正式发版等明确指令。
- **MuMu 验收口径**：采用「基础保数据冒烟 + 本轮及尚未发版的核心改动路径」；涉及学习通线上接口最多集中刷新 1 次，避免高频请求触发 `9010`；未改同步解析时不重复刷线上接口，始终保留登录态、课程与课业数据。
- 支持两段节奏：日常在 `dev` 每完成 1–3 个修订版可先过本地全量门禁再提集成 PR 合入 `main` 跑云端 CI（不修改 `README.md`/`CHANGELOG.md`/`安装与使用.md`，不打 Tag）；维护者明确要求正式发版后，再提轻量版本冻结 PR（升 `Y+1` 归零 `Z` 并同步正式文档）合入 `main`、构建验收并打 Tag 发布。紧急 Hotfix 从**最新正式版 Tag** 起步，发布后同步回 `main` 与 `dev`。正式版采用标准无前导零三段 `X.Y.Z` 与 `vX.Y.Z`（`Y` 上限 `99`，满 `99` 进 `X+1.0.0`），构建号高于全部测试包；每次正式版自动更新 `update-manual.json`，仅在大更新或紧急热修时显式开启 `--promote-stable` 推进 `update-stable.json`（细则见[版本号与迭代规则](docs/ai-workflow/VALIDATION.md#版本号与迭代分级规则)）。
- 正式发布逐关核对 [CI、原签名 APK、设备及回下载](docs/ai-workflow/VALIDATION.md#集成验收与正式发布)。GitHub 每包必发，Gitee 自动更新小索引、按需手动镜像 APK，细则见[分发指南](docs/guides/更新渠道与国内分发.md)。
- 并行任务先划定文件与资源归属；正式发布的独立审读、Git 与验收责任见[协作与发布审读](docs/ai-workflow/VALIDATION.md#协作与发布审读)。

## 事实源与归档

- [PROJECT_STATE.md](docs/ai-workflow/PROJECT_STATE.md) 维护当前迭代和最近两版入口；[CHANGELOG.md](CHANGELOG.md) 维护已交付行为，版本身份核对源码、Git 和 GitHub Release；测试和产物的详细证据归对应发布记录。
- `docs/plans/` 保留最多两份正在执行或待执行的方案；复杂任务换手时才写交接，`docs/ai-workflow/handoffs/` 只留当前有效的一份。完成或失效即用 `git mv` 移入对应归档。
- 新增计划、交接、验收统一命名 `YYYY-MM-DD-vX.Y.Z-<主题>.md`：`dev` 分支日常开发与方案一律使用当前/下个 `dev` 修订号（如 `v1.8.27`、`v1.8.28`、`v1.8.29`），严禁提前冠名未获授权的下一正式版号（如 `v1.90.0`）；仅在维护者明确下达正式发版指令后才切换正式版号。正式发布收口的同一提交归档本轮已完成方案、过期交接、第三旧及更早验收与其证据，并滚动归档工程状态。步骤与目标路径见[文档索引](docs/README.md#发布收口与归档)。

## 架构导航与更新约定

- 跨模块排查、重构或梳理调用链前，先读 [ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) 快速定位入口与不变量；日常严禁读取 `docs/architecture/*.html`（含前端渲染代码，白耗上下文），`*.json` 仅在刷新架构图时读写。
- 架构文档仅为定位导航而非源码真源，动手改码前必须读盘核实实际源码；若发现图文与最新代码脱节，一律以代码为准并在汇报中提示刷新。
- 单文件修 Bug、样式文案微调等小改动不更新架构图；大版本收口、跨模块重构、模块增删拆分或核心数据流/状态机/不变量变更时，基于 `docs/architecture/*.json` 增量修改并重跑 `finalize` 与 `export-svg`，同步更新 `ARCHITECTURE.md` 基线 Commit。
