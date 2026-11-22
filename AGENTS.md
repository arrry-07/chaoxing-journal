# 学习通课业手记

## Context Routing Matrix（分层读取矩阵）

| 层级 | 读取规则 |
| --- | --- |
| L0 热层 | 默认必读本文件与 [PROJECT_STATE.md](docs/ai-workflow/PROJECT_STATE.md)。两份合计最多 80 行。日常 `dev` 以这两份建立项目上下文，修改前核对分支、HEAD、工作区、暂存区及相关代码和测试。 |
| L1 温层 | 按目标点读 [文档索引](docs/README.md)、[验证规则](docs/ai-workflow/VALIDATION.md)、[路线图](docs/ROADMAP.md)、[反馈台账](docs/待处理体验反馈.md)、`docs/guides/`、`docs/plans/` 当前方案及有效交接。查发布证据时从状态页进入最近两版记录。 |
| L2 冷层 | `docs/archive/**` 默认禁读。所有 AI Agent 日常开发、排查及审读时严禁主动扫描、遍历或读取归档；仅在用户明确点名追溯某个历史版本时，按该版本定向访问。全仓内容检索用 `rg -g '!docs/archive/**'`，子代理同样遵守。 |
| Skill 路由 | 动手出方案、改代码、查疑难 Bug、审代码或打包发版前**必查** [Skill 强制路由表](.agents/rules/skill-routing.md)，命中场景须先 `read_file` 加载对应 `SKILL.md`（提示词再长也不得跳过）。 |

## 日常开发与正式发布

- 日常在 `dev` 工作。每项独立改动通过定向检查后单独提交（功能迭代同步更新 [dev 进度](docs/ai-workflow/PROJECT_STATE.md#dev-当前迭代进度)），随后自动轻量推送 `origin/dev`（无需重复确认），细则见[日常推送门禁](docs/ai-workflow/VALIDATION.md#dev-日常推送门禁)。
- 推送 `origin/dev` 前必查 `git status` 与本次提交 Diff，严禁纳入凭据、Cookie、账号响应、敏感日志、`docs/feedback/`、`scripts/demo-video/`、个人材料或 `.apk` 等大体积二进制；仅推 `dev` 到 `origin/dev`，严禁顺手合入 `main`、建正式 PR 或打正式 Tag（正式发版须等明确指令）。
- 推送完成后，在最终回复末尾固定附两行供代码走查：最新 `origin/dev` 提交号（完整 SHA 与简短信息），以及对比链接 `https://github.com/arrry-07/chaoxing-journal/compare/main...dev` 与核心修改文件的 `dev` 直达链接。
- 本地快检使用缓存依赖，按需运行改动文件的 `dart format`、`flutter analyze --no-pub` 和 `flutter test --no-pub <相关测试文件>`。如需跳过 SDK 更新检查，在 Flutter 子命令前加 `--no-version-check`。
- 修改课业、时间信任或首页筛选时，读[学习通参考实现](docs/guides/开发与贡献.md#学习通参考实现)与[首页课业行为约束](docs/guides/开发与贡献.md#首页课业排序长期约束)。确认逾期在双向时间排序中始终置底，保留 `FB-005` 回归。
- 第三方 API、版本兼容或升级先查锁文件（Flutter 用 `pubspec.lock`），再用 Context7 核对对应版本文档。项目内部逻辑直接检查本地源码和测试。
- 视觉与布局改动须有当前任务的明确要求；功能修复只改必需的可观察界面状态，并在交付中说明。无关视觉问题只记录。
- 保留已有修改和未跟踪的 `docs/feedback/`、`scripts/demo-video/` 及个人材料。凭据、Cookie、账号响应或敏感日志不得进入提交。保持 Flutter、脚本、参考实现与 CI 约定的目录路径。
- MuMu 预览按[自测包步骤](docs/guides/开发与贡献.md#mumu-自测包)执行。只有准备安装预览包时才写入 `X.Y.Z-dev.N+build`。使用原签名覆盖并保留登录态和数据。
- 维护者明确要求正式发版后，从 `dev` 向 `main` 提汇总 PR；紧急 Hotfix 从最新 `main` 起步，发布后同步回 `dev`。正式版使用 `X.Y.Z` 与 `vX.Y.Z`，构建号高于已用预览包。
- 正式发布逐关核对 [CI、原签名 APK、设备及回下载](docs/ai-workflow/VALIDATION.md#集成验收与正式发布)。GitHub 每包必发，Gitee 自动更新小索引、按需手动镜像 APK，细则见[分发指南](docs/guides/更新渠道与国内分发.md)。
- 并行任务先划定文件与资源归属；正式发布的独立审读、Git 与验收责任见[协作与发布审读](docs/ai-workflow/VALIDATION.md#协作与发布审读)。

## 事实源与归档

- [PROJECT_STATE.md](docs/ai-workflow/PROJECT_STATE.md) 维护当前迭代和最近两版入口；[CHANGELOG.md](CHANGELOG.md) 维护已交付行为，版本身份核对源码、Git 和 GitHub Release；测试和产物的详细证据归对应发布记录。
- `docs/plans/` 保留最多两份正在执行或待执行的方案；复杂任务换手时才写交接，`docs/ai-workflow/handoffs/` 只留当前有效的一份。完成或失效即用 `git mv` 移入对应归档。
- 新增计划、交接、验收统一命名 `YYYY-MM-DD-vX.Y.Z-<主题>.md`。正式发布收口的同一提交归档本轮已完成方案、过期交接、第三旧及更早验收与其证据，并滚动归档工程状态。步骤与目标路径见[文档索引](docs/README.md#发布收口与归档)。
