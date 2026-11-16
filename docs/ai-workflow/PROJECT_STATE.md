# 当前工程状态

更新时间：2026-11-15（Asia/Shanghai）。这是工作摘要，接手时须核对现场；以下早期机制初始化记录保留为历史，当前任务以末尾最新条目为准。

## 当前目标与范围

- 当前正式版本为 `1.7.59+66`，一期35/42课程活动补拉已发布；main与Tag `v1.7.59`均为 `cdc8477ff3f7250c333b0c399e7ab88534dba33a`，PR #31已合并。详见末尾最新条目与[验收及发布记录](../reviews/2026-11-15-1.7.59课程活动补拉验收与发布记录.md)。下方早期条目保留各自历史基线。
- 下一补丁优先补拉77 AI实践：用户亲自打开官方课程任务页，明确其属于课程作业且要拉取。此前排除77只是一期开工时的范围，1.7.59尚未支持；主代理正在调查个人状态接口。
- 独立IM已取得当前账号token和6个加入群，当前云历史只读到1张签到卡，不足证明无群作业；产品 `groupHistory` 仍未启用。
- 本轮仅收口限定五份文档，不改业务源码、不提交/切分支/构建、不生成交接，保留 `scripts/demo-video/` 及并行工作。

## 现场基线（机制初始化历史）

- 实际仓库：`D:/codex/学习通助手`；Flutter 应用：`study_assistant-1.1.0/local_app`。
- 当前聊天入口：`C:/Users/Administrator/Documents/ChatGPT/学习通助手`；此目录不是 Git 仓库，其 `AGENTS.md` 仅指向实际仓库，不维护第二份状态。
- 初始化核对的分支：`codex/v1.6.71-release`；HEAD：`6e8aeecb8a843ddb52af018e8f8d61876f81ed34`。这是添加工作流文档前的基线，不是后续提交的动态指针。
- 本地跟踪信息显示领先 `origin/codex/v1.6.71-release` 一个提交；初始化时未 fetch，不据此断言远端最新状态。
- 工作区有较多既有修改：通知相关 Android/Dart 实现与测试、CHANGELOG、README、文档索引及指南；还有未跟踪的原生测试、通知服务、演示脚本和其他来源待确认文件。初始化时暂存区为空。文件可能被并行任务继续修改，接手须重新运行 `git status` 与 `git diff`。

## 本次已完成

- 根 `AGENTS.md` 增加状态更新、证据区分、接手与按需交接规则。
- 建立本文件作为唯一的当前状态入口；旧[下一阶段续接](../下一阶段续接.md)保留历史内容并指向本文件。
- 当前聊天目录增加本地入口指引。尚无需要归档的交接，本次不创建 `handoffs/` 或重复 Skill。

## 验证与证据

- 现场已读取项目规则、贡献约定、CI、旧续接文档、当前通知优化计划/验收记录，并核对 Git 基线及修改范围。
- 本次仅修改工作流 Markdown；已检查精确文件差异、相对链接目标及聊天入口，`git diff --check` 通过。只对本任务四个文件写入，没有整理、暂存或删除既有业务修改。
- 既有本地报告 `docs/reviews/2026-11-11-作业通知与白天提醒优化验收.md` 记载全量 Flutter 测试 665 passed / 1 skipped、静态检查、Kotlin/JVM、lint、Debug 构建与部分 API 35 模拟器检查通过。报告及其计划在初始化时均未跟踪；本次只读取记录，未复跑、核对原始日志或证明当前继续变化的工作区仍对应这些结果。
- 不把旧报告、历史发布或远端 CI 的通过结论自动转用于当前未提交代码。本次不运行 Flutter/Android 测试或构建，因为没有业务变更。

## 未完成与限制

- 通知任务的真实账号后台同步、真实学习通通知、Doze/整机重启、实体手机和 TalkBack 等范围，原报告列为未验证；其后是否有新证据须向当前任务记录核对。
- 通知业务改动的提交、推送及交付状态须现场核查；本机制的文档交付不代表它们已完成。
- 状态维护由 agent 在适用任务节点执行，没有后台保证；意外退出前未保存的对话细节不保证恢复。
- 旧续接中的版本、设备端口和临时授权仅用于追溯，不直接作为当前指令或当前设备事实。

## 下一步

- 本机制已就绪：后续按根规则在适用节点更新；本任务 Git 交付结果以实际 `git log` 和远端核对为准，不在此硬编码自身提交哈希。聊天目录入口留在本机。
- 接手通知优化时：先确认当前工作区和负责该任务的最新记录，再核对已有验收证据与源码范围；优先补齐当前目标所需的验证，不无条件重跑全部历史流程。
- 用户说“保存进度”时更新本文件；说“准备交接”时才创建任务交接并给出接手提示。

## 2026-11-11 七项体验方案补充

- 用户要求将七项体验改进细化为 DeepSeek 可直接执行的方案，已新增[执行方案](../plans/2026-11-11-七项体验改进-DeepSeek执行方案.md)。本轮仅编写方案，未修改业务代码、未运行业务测试或构建、未发布 APK。
- 方案按当前代码明确了排序持久化与统一列表、首次同步内存预览及正式提交边界、Android 设置直达与回退、图标选稿、规划说明、登录文案、学习通网页入口取证和验收步骤。
- 本轮勘察基线为 `codex/v1.6.72-release` / `6161c65`，工作区仍有通知任务修改。首次同步延迟根因和可用的学习通原生作业入口尚未实机确认；方案不把推测当结论。
- 下一步由执行者按方案开工检查重新核对当前源码和差异；图标需要先出稿再由用户选定，其他工作可独立推进。本文保留上方原任务记录。

## 按需参考

- 2026-11-11 按用户要求在根 AGENTS.md 增加主动并行与代理协作规则，七项方案和第八项补充已加入具体分工。强调同文件单写、共享接口集成、构建资源协调、主代理验收与Git归属；没有工具时可批量/串行执行，不强制多代理。本轮仅改文档，不改变业务实现或全局代理配置。

- 2026-11-11 新增[第八项：国内直连更新](../plans/2026-11-11-第八项-国内直连更新.md)，与七项方案一起执行。已核对更新服务和官方托管资料；清单及APK均需国内可达，保持补丁静默策略。免费候选仍需实际包大小/网络验证，付费服务待用户提供规模预算并批准，尚未开通或更改更新代码。原七项方案新增的用户文字已保留，不纳入本轮提交。

- [文档索引](../README.md)、[开发与贡献](../guides/开发与贡献.md)、[贡献约定](../../CONTRIBUTING.md)。
- 本地通知任务计划：`docs/plans/2026-11-11-作业通知与白天提醒优化实施方案.md`；验收记录见上文。它们不属于本次提交范围，远端是否存在需另行确认。

新对话接手提示：

> 请先读取实际仓库的 AGENTS.md 和 docs/ai-workflow/PROJECT_STATE.md，核对当前分支、HEAD、未提交修改与暂存区，再按我本轮给出的目标继续。仅按需读取相关计划和验收记录，保留已有修改；不要把历史报告当作当前已验证结果，也不要仅因接手就提交、发布或扩大任务范围。

## 2026-11-12 1.6.72 发布现场

- 当前工作副本分支：`codex/v1.6.72-release`；任务提交 `5d54370`；PR #10 已正常合并，远端 main 为 `fa3e109`。工作区只剩用户既有的七项体验方案修改和 `scripts/demo-video/` 未跟踪目录，不纳入本任务。
- 最终候选版本：`1.6.72+54`；候选 APK SHA-256：`ED7A2B970B00FFDC9A037E7C68B0CDA82A4073ED4CC720CDBC009FF5F847785F`。
- 全量 Flutter 测试：`667 passed / 0 failed`（启用 `RUN_STORAGE_BENCHMARK=true`）；`flutter analyze`、格式、版本元数据、Kotlin JVM、API 35 instrumented tests、`lintDebug`、APK ABI/签名/ZIP/对齐检查通过。
- 主 MuMu `学习通`：最终候选覆盖安装，登录态保留；真实账号无界面 Worker 曾返回 `SUCCESS`；时区切换与恢复后调度记录保持可用。
- 物理 HUAWEI `CDY-AN00` / API 29 / ARM64：最终候选覆盖安装；用户开启厂商自启动/关联启动/后台活动后，未启动 Activity 的整机重启恢复了 8 条 Job/Work 相关记录和 56 条 Alarm 记录；Doze 进入/退出保持调度；强制停止后重开恢复 54 条 Alarm。
- 物理真机 `connectedDebugAndroidTest` 曾卸载/重装应用，`firstInstallTime` 发生变化；之后 UI 仍观察到登录态，本轮没有重新输入账号密码，数据连续性不能作为完整保留证据。
- 真实官方学习通通知尚未自然到达。用户已明确接受该缺项，不计入本轮完成条件；当前账号为学生，不能发布测试作业，已停止主动等待和轮询，不能用合成通知替代。
- 已补充完成：通知权限/通道故障、监听撤销/恢复、测试通知热点击与冷启动、普通进程回收、横幅/声音投递管线、锁屏隐私、物理真机时间/时区和 TalkBack 服务绑定与关键页面语义。
- 已完成 commit、push、PR、main/PR/Tag CI、最终 main Release 构建、回下载校验、Tag `v1.6.72` 和非 latest 公开发布；最终 APK SHA-256 `9E79790B4966A13503F3E718FA7850D1245027C94E46E057EE2B35700488CB27`，latest 仍为 `v1.6.7`。
- 真实 GitHub 网络验收以新版代码、旧版本 `1.6.7` 手动查询发现 `1.6.72`，启动提示/横幅均为 false；详见 `docs/reviews/2026-11-11-1.6.72真机验收与发布记录.md`。

## 2026-11-12 八项执行方案按现场修订

- 修订前本地为 `codex/v1.6.72-release-docs` / `da1ba37`；fetch后远端main为 `ce216c7`（PR #11合并），两者跟踪文件树一致。工作区只有用户原方案末尾补充和演示目录，无未提交通知业务修改。
- 两名只读子代理分别核查界面与设置/更新链路。七项新增体验尚未实施；已将通知已发布基线、已有权限恢复刷新、已有启动补丁过滤及缺失接口写入原方案，不再等待旧通知任务提交。
- GitHub查询确认v1.6.72正式资产57,523,043字节、digest与发布记录一致、latest仍v1.6.7。第八项改用正式包核对Gitee大小门槛并估算流量；匿名直链、国内网络与服务开通仍待验证，预算为少于10人/月10元、无云账号域名，未获付费开通授权。
- 本轮只修订两份执行方案及状态摘要，未修改业务代码、未复跑667项测试或设备验收。保留真实官方通知链路的用户接受缺项，不重新启动等待。下一步按更新后的方案实施和取证。

## 2026-11-12 1.7.3 正式发布

- 最终 main：`db9dce5c47ec87bdee77241115fbcd8fd7a4bced`（PR #12）；Tag `v1.7.3`，公开且 latest。
- 正式资产：`chaoxing-journal-1.7.3.apk`，57,698,755 字节；SHA-256 `e387e0b8fa9a1bcf92a10e88b68c5b70a273acdeed8d25e65ae1293889da9426`。`SHA256SUMS.txt` 93 字节，SHA-256 `6349559f77c703d1fada8a220a12a902b65603283a08527e6b227a2c7ff75a4b`。
- 全量 Flutter 测试 `729 passed / 0 failed`；上海/洛杉矶时区用例各 35 项通过。PR head、main 和 Tag 的 Flutter checks 均成功；ASCII 导出后的 Flutter analyze、Debug/Release、双 ABI、ZIP、签名、aapt、zipalign 通过。
- S9280 API35 模拟器同签名覆盖成功并保留原有数据；V2284A API35 首次安装和登录页启动成功，新图标在 Launcher 刷新后正确显示。最终物理设备安装因原 HUAWEI 设备离线未复验。
- 公开 Release 草稿和公开后均完整下载 APK；GitHub digest、下载哈希、ZIP CRC 和两个模拟器安装后的 base.apk 哈希均为上述 SHA-256。GitHub latest API 已返回 `v1.7.3`。
- 仍有限制：学习通同账号原生/网页布局对照、API26/31 最终设置页逐项点击、最终包 TalkBack/实体 ARM64 未复验；国内生产托管仍无项目 Gitee 仓库、域名或凭据，1.7.3 默认继续使用 GitHub。详见 `docs/reviews/2026-11-12-1.7.3体验改进与发布记录.md`。

## 2026-11-12 1.7.4 原图标恢复与重发

- 按维护者要求撤回 1.7.3 自定义桌面图标，恢复 1.6.72 及以前的猫头像；10 个普通/圆形 PNG 的 Git blob 与 `v1.6.72` 完全一致。删除 1.7.3 新增的自适应、单色、候选 SVG 和生成脚本，业务代码与国内更新配置未改。
- 业务提交 `e71cc0bca071082fe8a6bd96741113cc8a9d3c7e` 经 PR #14 合并；最终 main 与 Tag 提交为 `0769ccf4a07181d66ca3d607e1bc474c4cb2e10a`。PR push/PR、main、Tag 三组 CI 均成功。
- Tag `v1.7.4` 已公开并设为 GitHub latest。正式 APK 57,785,643 字节，SHA-256 `3994e1e413010ccffa08a79fedbecb7af8dee8d375289225d019b47842374f54`；`SHA256SUMS.txt` SHA-256 `f2e5fc697d7868ee620ec9a15ad9d9eec921e11460923c590ce3445a5184370c`。
- `v1.7.3` Tag、APK 与校验文件保持不变，Release 改为预发布并注明由 1.7.4 取代。已安装 1.7.3 的用户需手动检查或网页覆盖安装；旧 1.6.7 仍可从 latest 发现 1.7.4。
- Flutter 全量测试 `729 passed / 0 failed`；上海/洛杉矶时区各 35 项通过；ASCII 干净导出 analyze、原生 JVM、`:app:testDebugUnitTest`、`:app:lintDebug`、双 ABI Debug/Release、签名/ZIP/对齐检查通过。聚合 Gradle 测试中的第三方 shared_preferences DataStore 12 项失败未计为通过，详见 1.7.4 发布记录。
- S9280 API35 同签名覆盖后 `firstInstallTime` 保持并进入原有首页；V2284A API35 首次测试安装进入登录页；两台桌面均显示猫头像，安装后 `base.apk` 哈希与公开 APK 一致。
- 草稿与公开 Release 均完整匿名回下载，大小、哈希、GitHub digest 与 ZIP CRC 一致。最终图标仍待维护者后续自行选型，国内生产托管未配置。详见 `docs/reviews/2026-11-12-1.7.4原图标恢复与重发记录.md`。

## 2026-11-12 下一阶段计划与图标预览

- 当前执行入口为[国内更新与体验收尾方案](../plans/2026-11-12-下一阶段-国内更新与体验收尾执行方案.md)；旧两份计划顶部已标记历史规格，避免重做1.7.3/1.7.4完成内容。本轮仅写计划和生成预览，没有改业务或部署国内源。
- 本轮GitHub资产查询确认1.7.4为57,785,643字节、digest与发布记录相同；Gitee官方单附件100M/总1G限制已复核。生产匿名直链、清单地址和大陆网络仍待验证，不能只凭包小宣称已配置。
- 用户将自行注册并登录Gitee。实机许可已给出：其他问题收尾后由用户连接并确认具体手机；不重复申请许可，未确认目标前不操作设备。付费托管/域名仍需报价确认。
- 用户图标偏好已变为接近旧头像的可爱风，可偏二次元，不要求体现软件用途。本轮已生成A软萌猫头像、B慵懒猫团子、C猫耳动漫角色、D奶油小狐狸四张预览；未选定前保留1.7.4原图标，不发布候选。

## 2026-11-12 P1 修复（提醒链路/原生桥/编辑页）

- 按用户“先修 P1”要求处理审查发现：`ReminderDatabase.applyPlan` 允许仍有效的 CANCELLED 截止事件重新激活（隐藏后恢复不再永久丢提醒）；`BackgroundReminderGateway` 的 `isSessionCurrent` 改为 fail-closed，`loadPlanState`/`applyPlan` 改为严格通道调用并抛出 `BackgroundReminderGatewayException`；旧插件提醒清理只按 `a:` payload/清单 ID 取消，不再按 `assignment_deadlines` channel 误删原生已投递通知，并增加一次性迁移标记；个人清单/备注与手动日程编辑页增加未保存修改的 `PopScope` 确认。
- 新增回归：`test/background_reminder_gateway_test.dart`、`test/unsaved_edit_guard_test.dart`、`test/notification_ordering_test.dart` 的原生通知保留用例、`assignment_store_background_reminder_test.dart` 的一次性清理标记用例，以及 `ReminderDatabaseAccountTest` 的 CANCELLED→PENDING instrumented 用例。
- 验证：`dart analyze` 无问题；`dart format` 174 文件 0 改动；全量 Flutter 测试 `736 passed / 1 skipped / 0 failed`；上海/洛杉矶时区各 35 项通过；ASCII 副本 `:app:compileDebugAndroidTestKotlin` 通过（NDK 28.2，未在设备运行 instrumented 测试）。
- 未验证：instrumented 用例需设备运行；F1 修复未在真机通知栏复核；主线程/冷启动/取消语义等 P2 未在本轮处理。此处为当轮提交前记录；后续已提交／推送，当前状态见下一节。保留 `scripts/demo-video/` 未跟踪。

## 2026-11-12 当前小版本重核与完整执行方案

- 现场核对：`codex/p1-reminder-fixes` 本地／远端均为 `4a367991f2e35153bb13adf017c76baa57a588fe`，远端 main 为 `144874a`；[当前 PR](https://github.com/arrry-07/chaoxing-journal/pull/16) 未合并、非 draft、两项检查成功，Auto-fix 开启、auto-merge 关闭。正式版仍是 `1.7.4+56`／latest `v1.7.4`；核对时无 `v1.7.5*` 标签，`1.7.5+57` 仅为下一补丁建议，发布前须再查占用。
- 已读取[当前提交的 CI 原始日志](https://github.com/arrry-07/chaoxing-journal/actions/runs/43185486702)：UTC 全量 `736 passed / 1 skipped`、上海／洛杉矶各 `35 passed`、分析与 Debug/ABI 检查成功。这不是本轮复跑；未来修复不能继承。现有 Java 合成检查和 Debug 构建未执行 Kotlin 应用单测／数据库设备测试，方案补上对应门禁。
- 已将原[下一阶段方案](../plans/2026-11-12-下一阶段-国内更新与体验收尾执行方案.md)原位扩展为“当前小版本：可靠性修复、体验收尾与国内分发完整执行方案”。优先补现有 PR 与租约／原生失败语义，再做分页预览、持久化失败恢复、编辑路由保护、规则保存、日历待确认入口、体检错误反馈、取消及有界性能／键盘验证；每项含文件、最小步骤、新增测试、验收和停止条件。不再把 Gitee、未选图标和实机等待绑定为所有修复的前置。
- 源码复核确认：写租约双重同步会阻住释放者；同步合并成功／失败提前返回漏释放租约；部分关键原生写操作仍吞错；legacy 已投递迁移漏清且新旧 ID 区间重叠；恢复事件未刷新课程／标题。两个 PR 审查线程本轮尚未修复、回复或 resolve。其他体验发现区分源码缺口与需组件／设备复现，不宣称实机卡顿或丢稿已验证。
- 国内源仍无本项目生产 URL／匿名完整下载证据；Gitee 官方 100M／1G 规则已复核，不代表匿名下载保证。原猫头像继续保留；仓库内图标证据是 1.7.3 旧 A/B，不能当四个可爱风新候选或已选稿；旧候选 README 已加撤回／失效命令警告。物理手机未确认，不连接或操作设备；真实官方通知的接受缺项保持不变。
- 本轮只修改执行方案、文档索引、该状态与旧图标说明，没有业务改动、版本变更、提交／推送、新 APK 或发布。原有 `scripts/demo-video/demo_main.dart` 未跟踪文件保留。下一步从方案 A0/A1/A2/A3 的失败测试和最小修复开始，依赖共享接口由主代理统一集成。

## 2026-11-12 A 批次：租约、迁移与控制失败语义

- 业务提交 `590752a`（`codex/p1-reminder-fixes`）：移除写租约多余对象锁并加入取消检查；新增按请求的租约确认／取消／引擎销毁生命周期，迟到取得不再泄漏；旧插件已投递提醒改由原生按插件点击操作与调度缓存证明归属，保留同 ID 原生通知并处理插件缓存并发；恢复／更新截止事件时同步课程与标题；关键原生控制、登录切换、隐私清理、退出与提醒体检不再把失败伪装成成功，退出失败保留旧账号哈希待重试。
- 回归：`background_reminder_gateway_test.dart`、`assignment_store_background_reminder_test.dart`、`notification_ordering_test.dart` 新增租约确认、取消竞态、迁移保留、失败重试与退出重试用例；`BackgroundLeaseRequestsTest`、`BackgroundExecutionCoordinatorTest`、`LegacyAssignmentNotificationMigratorTest` 与扩展的 `ReminderDatabaseAccountTest` 覆盖原生侧。
- 验证：`dart analyze` 无问题；`dart format` 174 文件 0 改动；全量 Flutter 测试 `766 passed / 1 skipped / 0 failed`；上海／洛杉矶时区各 `35 passed`；ASCII 副本 `:app:testDebugUnitTest` 与 `:app:compileDebugAndroidTestKotlin` 通过（NDK 28.2，未在设备运行 instrumented 测试）。
- 未验证：设备上的真实 PendingIntent 身份匹配、通知投递／保留、旧账号原生清理重试、主线程耗时与冷启动；未修改版本号、未构建 Release、未发布 APK。B 批次及国内源、图标、实机验收保持未完成。

## 2026-11-12 B 批次：同步预览、保存恢复与日常交互

- 业务提交 `ce206c1`：V3 多页作业每页校验后发布内存预览，后页失败只撤回该课程并保留旧正式记录；journal／课程写入在 false／异常后 reload 核验真实持久值，首次持久化前标记保存阶段，本机写失败归为 storage；个人备注、手动日程与提醒规则共用离开守卫，覆盖底部页签、通知深链和路由替换，规则保存中锁定草稿控件；日历新增“无截止／截止待确认”临时范围，不覆盖已保存筛选；提醒体检区分读取失败、不支持和真实零值；会话清理／销毁取消在途请求，规划弹层在大字＋键盘下改为紧凑滚动。
- 新增／扩展回归：`v3_pagination_preview_test.dart`、`calendar_scope_test.dart`、`unsaved_edit_guard_test.dart`、`reminder_settings_screen_test.dart`、`reliability_recovery_test.dart`、`reminder_health_test.dart`、`daily_plan_planner_test.dart`、`chaoxing_local_client_test.dart` 与 `assignment_query_test.dart`。
- 验证：`dart analyze` 无问题；`dart format` 177 文件 0 改动；全量 Flutter 测试 `799 passed / 1 skipped / 0 failed`；上海／洛杉矶时区各 `35 passed`。未运行原生 instrumented 测试、未连接真机、未构建 Release 或发布 APK。
- 未验证：键盘／TalkBack 实机体感、真实账号首次同步分页耗时、系统通知投递、Store 销毁取消的设备级行为；B7 的退避取消与跨会话迟到结果仅覆盖客户端取消路径，完整的设备级取消矩阵仍待后续。国内源、图标与实机验收保持未完成。

## 2026-11-12 C 批次：1.7.5 候选与原生 CI 门禁

- 候选提交 `21d6104`：版本提升为 `1.7.5+57`，同步 `AppVersion`、CHANGELOG、README 和安装指南；CI 新增 `:app:testDebugUnitTest`、`:app:compileDebugAndroidTestKotlin`、`:app:lintDebug`。npm/依赖未变，`pubspec.lock` 未改。
- 版本核对：核对时无 `v1.7.5` Tag；GitHub latest 仍为 `v1.7.4`。1.7.5 按小补丁处理，不设 latest、不触发启动提示。
- 验证：`tool/check_release_metadata.py` 通过（1.7.5+57）；`dart analyze` 无问题；格式 177 文件 0 改动；全量 Flutter 测试 `799 passed / 1 skipped`；上海／洛杉矶时区各 `35 passed`。
- ASCII 副本使用 `ANDROID_HOME=D:/campus-tools/android` 构建：Debug 与 Release 均成功；`:app:testDebugUnitTest`、`:app:compileDebugAndroidTestKotlin`、`:app:lintDebug` 通过。
- 候选 APK：`app-release.apk`，57,851,367 字节，SHA-256 `79c40fe20b8903bfa91cec036a3c98b71b00804e8d80c41edab49c8cf0c839fc`；`aapt` 为 `com.example.studyassistant.journal` / versionCode 57 / versionName 1.7.5 / minSdk 26 / targetSdk 36；ABI 仅 `arm64-v8a`、`x86_64`；APK Signature Scheme v2 有效，证书 SHA-256 `d36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a`；`zipalign -c 4`、ZIP CRC 通过；未声明 debuggable。
- 未验证：候选未安装到模拟器或实体手机，未运行 instrumented 测试；真实账号同步与通知投递未复验。候选尚未合并、打 Tag 或发布；国内源与图标仍未完成。

## 2026-11-12 暂停现场：1.7.5 发布门禁修复（未完成，已存 stash）

- 原因：执行方案 P1/P2 的 R1–R6 修复进行到一半，用户需关机暂停。进行中的 18 个文件已存入本地 Git stash：`stash@{0}` / `wip: 1.7.5 release gates R1-R6 partial (2026-11-12 pause)`；工作区只保留已完成的下载入口修正和本状态。未合并、未打 Tag、未发布 1.7.5。
- 已完成并验证（stash 内容）：原生迁移拆分 `LegacyAssignmentCache`（读取 v18 Gson 的 `id`、保留非目标/未知记录）、`LegacyAssignmentMigrationState`（原生 v3 事实）、`NativeReminderTasks`、迁移/租约终态修改；`AssignmentNotificationPublisher` 增加真实点击 token 比较与迁移门禁；`ReminderDatabase.eventsForNotification`；Store 的迁移闸门、隐私待清理保护、唯一 sync requestId、保存阶段取最新快照；点击型取消结果与退避取消；`unsaved_edit_guard` 新核心；`update-manifest.ps1` 显式 ApkUrl/初始化模式与脚本测试。
- 验证现场：Dart `analyze` 无问题；ASCII 副本原生 `:app:testDebugUnitTest` 与 `:app:compileDebugAndroidTestKotlin` 通过（约 40 个原生单测）。Dart 定向运行仍有 13 个失败，主要是 `chaoxing_local_client_test` 的取消/会话旧断言，以及 `unsaved_edit_guard_test` 因新守卫尚未接入页面调用方；不能把这些失败当作已修复。
- 尚未完成：R4 页面/Shell/通知调用方接入新守卫（`navigate`/`showUnsavedEditDialog`/`invalidate`）；R6 区分“显式取消”与 `clearSession` 旧 stale 语义并更新测试；R2 登录/Worker/隐私端到端回归；R3 原生迟到控制测试收口；R5 Store 撤回窗口测试；PowerShell 脚本真实执行；全量 Flutter、双时区、构建、隔离模拟器与实际设备验收；最终合并、Tag、Release 与匿名回下载。图标/国内源仍保持未完成。
- 恢复步骤：现场核对 `git status` 与 `git stash list`；执行 `git stash pop stash@{0}`（不要 drop），再 `dart analyze`，先修复 guard 调用方与取消测试，再跑定向/全量；stash 不含 `scripts/demo-video/`，该未跟踪目录保持原样。
- 当前远端/本地已提交 HEAD 仍为 `39ebf88`（1.7.5+57 候选、PR16 两项 CI 已通过），README/安装指南已恢复 1.7.4 有效下载入口并标注 1.7.5 未发布。下一轮不要从“旧候选已构建”直接发布。

## 2026-11-13 恢复执行：1.7.5 发布门禁修复闭环

- 已恢复并删除暂停 stash；业务提交 `ad6d395` 完成 R1–R6：插件 v18 缓存 `id`/点击 token 归属、未知记录保留、AlarmManager 取消、原生 v3 迁移事实与投递门禁；租约终态不可复活且每次同步唯一 requestId；plan 数据库/闹钟/通知发布移出主线程；草稿批准限定一次导航/一个 revision，账号替换失效旧弹窗并退出私有编辑页；保存阶段取最新撤回快照；显式取消不再变成成功空同步；清单脚本补显式 APK URL/基线初始化并修缺失路径错误。
- 验证：`dart analyze` 无问题；格式 177 文件 0 改动；全量 Flutter `812 passed / 1 skipped`；上海/洛杉矶各 `35 passed`；原生单元测试 40 项通过；隔离 API35 x86_64 模拟器实际运行 instrumented 16 项（15 通过，真实账号 1 跳过）；PowerShell 清单脚本 `66 passed / 0 failed`。
- 最终候选（本轮源码重建）：`chaoxing-journal-1.7.5.apk` 57,867,751 字节，SHA-256 `0732c5b99cf7dc2a956a9f95d5a6844b8cd20c0cd187c44a5bffbdb394df0bdf`；包名 `com.example.studyassistant.journal`、code 57、name 1.7.5、min26/target36、ABI arm64-v8a/x86_64、v2 证书 `d36a571510e046dd196d7384f849f82b4fcff05ce3affb334765d5c752265d8a`、`zipalign -c -P 16 4` 通过。隔离模拟器先装公开 1.7.4（SHA `3994e1e…`）再同签名覆盖候选，`firstInstallTime` 保持 `2026-11-13 02:43:02`，版本 1.7.5 且 MainActivity 正常前台。
- 未完成：PR 尚未合并、Tag/Release 未创建；README/安装指南仍指向 1.7.4，CHANGELOG 仍标候选；最终 main 构建/公开回下载/旧客户端手动更新验证待执行。国内源生产部署和新图标仍未具备外部条件。

## 2026-11-13 1.7.5 正式发布

- PR `#16` 正常合并，main 提交 `0127aa371805b65acbb6211562e501df0ad7c80d`；annotated Tag `v1.7.5` 指向同一提交。main CI `43284580711` 与 Tag CI `43284985962` 均成功；PR push/PR checks 成功。
- 正式 APK：`chaoxing-journal-1.7.5.apk`，57,867,751 字节，SHA-256 `104f902b1cbc564b098afc1ac9849b2ad62521fc827d2a9499b40845c7c7ed47`；`SHA256SUMS.txt` 93 字节；同签名证书 `d36a5715…265d8a`；ABI arm64-v8a/x86_64；v2 签名、ZIP CRC、16KiB 对齐通过。
- Release：<https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.5>，已公开、非预发布、显式 `latest=false`；GitHub latest 仍为 `v1.7.4`。公开 URL 未登录完整下载 APK 与校验文件，`sha256sum -c`、ZIP 和证书核对通过。
- 设备：专用 API35 x86_64 模拟器从公开 1.7.4 同签名覆盖到最终 1.7.5，`firstInstallTime` 保持，MainActivity 前台；未操作物理手机。实体手机真实账号/后台/Doze/TalkBack、真实官方学习通通知（既有接受缺项）仍未验证；国内生产源与新图标未交付。
- 文档已切到 1.7.5 下载/安装/版本记录，新增 1.7.5 完整验收记录并更新索引/路线图/验收基线。后续文档提交不移动 Tag；应用源码以 `0127aa3` 为准。

## 2026-11-13 启动更新提示修复

- 用户明确改为进入应用自动提示新版，覆盖此前补丁仅手动规则。启动检查现在与手动检查同样读取正式 Release 列表（排除草稿/预发布），清单优先 manual/旧单清单，只有 stable 配置时兼容 stable；移除 Controller 同 minor 拦截。保留忽略版本、前台展示、单次冷启动检查和主动下载安装。
- 更新专项 52 项通过；dart analyze 无问题。尚未构建或发布包含此修复的 APK，不能声称已安装1.7.5自动获得新逻辑。随后维护者明确下一小版本采用1.7.51而非此前建议的1.8.0；旧客户端仍有 major/minor 门禁，首次需手动检查或网页覆盖安装，之后由新逻辑提示后续补丁；不覆盖v1.7.5资产。

## 2026-11-13 九项反馈整理与近期方案

- 现场核对：`codex/startup-update-prompt` / `830405c`，业务版本仍 `1.7.5+57`；启动修复已在分支，未发布新 APK。开始时仅有既有 `scripts/demo-video/` 未跟踪目录，保留原样。
- 新增[近期体验修复执行方案](../plans/2026-11-13-近期体验修复执行方案.md)，覆盖反馈 #1/#3/#7/#6/#4：原生入口先取证；电池设置优先定位本应用；更新弹窗优化；猫形单色通知图标；新增未截止并保留无截止日期。明确文件、失败边界、测试与发布顺序，尚未实施。
- 路线图拆分长期 #8/#9/#5/#2：学习通考试、章节、课程通知、教务考试、官方授权登录，先研究/手动可信读取，再推进保存、日历、提醒及后台同步。无可用接口不承诺实现。
- 维护者最新版本规则：`1.7.5 → 1.7.51 → 1.7.52 → 1.7.53`，versionCode 独立递增；多个小问题合并发布，冻结时统一升版，升版必交正式 APK/Release/校验/下载文档。下一候选 `1.7.51+58`，实际冻结前核对占用。
- 本轮仅更新文档与方案，未修改业务代码、未升版、未运行新的业务测试/构建或操作设备；75 个本地 Markdown 链接目标存在，`git diff --check` 通过。Git 交付以分支实际日志为准。此前 812 项全量和 52 项更新专项证据不自动覆盖待实施方案。

## 2026-11-13 近期体验方案执行中

- 在 `codex/startup-update-prompt` / `947f7a1` 工作区实施五项方案；尚未冻结版本、提交或发布。既有未跟踪 `scripts/demo-video/` 保留。课程双作业官方入口对照未取得，入口明确为学习通内网页，未声称原生直达。
- 已实现本应用详情优先的电池设置、更新弹窗与失败类型、猫形通知小图标，以及独立的“未截止”筛选；保留旧 `noDeadline` 偏好。独立审查发现的取消检查和校验失败分类问题已补回归修复。
- 此时 Dart 分析、全量格式检查通过；Flutter 全量 818 通过、1 跳过，上海/洛杉矶时区测试通过。原路径 Gradle 因 Windows 中文路径限制失败；逐文件校验的 ASCII 副本原生单元测试、仪器测试编译及 lint 通过。
- 新建 API26 隔离模拟器：全新安装、按顺序运行的仪器测试 15 通过、1 真实账号跳过；原生发布器和插件分别发出合成通知并观察到猫图标，桥接打开本应用详情并返回 `appDetailsFallback`。旧测试渠道夹具与系统异步入列问题已补前置断言及等待，不将初次失败伪装成通过。API35 系统应用详情入口可打开；API31、厂商设备和真实账号仍待验证。
- 截至此记录源码仍为 `1.7.5+57`，后续应完成剩余显示/设备核验后再检查远端版本占用、冻结、构建与发布；实际工作区和测试日志为准。临时测试副本在 `D:/campus-tools/build-work/experience-20261113-91b802bc`，其中探针入口仅供验证，不能作为发布入口。
- API35 隔离实例使用同签名合成探针覆盖安装，插件通知在深色通知栏和状态栏显示猫图标；锁屏尝试未进入锁屏，不能计为锁屏验收。截图位于 `D:/campus-tools/build-work/experience-plugin-dark-api35.png`。尚未构建最终版本 APK，也未完成 PR、CI 或发布。
- 用户明确普通验收使用 MuMu，真机由用户方便时自行连接，不作为本轮发布等待条件。候选 `1.7.51+58` 已在提交 `075d701` 冻结并推送，候选 APK 从该提交导出构建，SHA-256 `A82F9E2CDEF4ABE4414BCD0C7BD615FB85C38CAD32681D90948F028F0802699E`；包名、版本、双 ABI、原签名、ZIP 和对齐检查通过。
- MuMu（Android 15）已完成候选覆盖验收：从 `1.7.4+56` 同签名覆盖到 `1.7.51+58`，`firstInstallTime` 保持 `2026-11-04 19:05:10`，原登录态与课程数据保留，首页正常。筛选表显示独立的“未截止”和“无截止日期”；选择“未截止”后，年份不可信的旧作业被排除，强制结束并重启后筛选仍保留，随后已清除恢复默认列表。提醒设置中的“本应用电池与后台设置”实际进入本应用详情，返回后回到助手。更新弹窗、测试通知猫形图标和深色状态栏图标已通过截图核对。
- PR #17 的候选 push/PR CI、合并后 main CI 与 Tag CI 均成功。候选与最终 MuMu 验收详情见[1.7.51 验收与发布记录](../reviews/2026-11-13-1.7.51近期体验修复验收与发布记录.md)。

## 2026-11-13 1.7.51 正式发布

- PR #17 正常合并，main 提交 `7bfd035a9c8d82108de60722c14dd006f96a2afc`；annotated Tag `v1.7.51`（object `18ee7df084774a9423c089fbe87b4465c6215522`）指向同一提交。main CI `43376978958` 与 Tag CI `43378170234` 均成功。
- 最终 APK 从 main 的干净 ASCII 导出、使用锁定依赖和原签名重建：`chaoxing-journal-1.7.51.apk`，57,867,911 字节，SHA-256 `1e69ec393d78a26f14a49189c8b6f9a4bc16dfec82d4cefa62c40ad66799ca84`；包名、1.7.51+58、min26/target36、双 ABI、v2 原证书、ZIP CRC 和 16 KiB 对齐通过。
- 最终 APK 已在 MuMu Android 15 覆盖：`firstInstallTime` 保持 `2026-11-04 19:05:10`，登录态、课程数据与首页正常；设备拉回 `base.apk` 与本地正式 APK 哈希一致。API31、锁屏、TalkBack、实体手机后台/Doze 和真实作业原生直达仍未验证，按用户约定不阻塞发布。
- Release <https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.51> 已公开、非预发布并设为 latest；`releases/latest` API 返回 `v1.7.51`。`SHA256SUMS.txt` 94 字节、SHA-256 `c09e2d51bc85fcab4c7046bca3eb16e9f0ca8e70d153d8f96c969557d702a806`。
- 草稿和公开后均完整下载 APK 与校验文件，大小、哈希、ZIP、v2 签名和证书一致。README、安装指南、CHANGELOG、路线图、文档索引、验收基线与本状态已切到正式 1.7.51；后续纯文档提交不移动 Tag，应用源码以 `7bfd035` 为准。

## 2026-11-14 1.7.53 作业数据体验与设置收口正式发布

- 现场从 `7b6ab7a` / `1.7.52+59` 起步，保留既有 `pubspec.lock` 意向与未跟踪 `scripts/demo-video/`；因 Gitee/GitHub `v1.7.52` 已正式发布，冻结前改用未占用的 `1.7.53+60`。
- 功能提交 `5860944` 经 PR #19 合并到 main `0705a9e34b7cab3fc66c8da6506240e221cba303`；annotated Tag `v1.7.53`（object `404320130d6d41b2744f4f1510143d7730a0893f`）指向同一提交。PR CI `43468063352`、main CI `43470960963`、Tag CI `43474590304` 均成功。
- 实现统一 `deadlineBucketAt(now)`、三期限筛选与旧偏好迁移、`lpinyin 2.0.3` 拼音/英文/数字自然排序、四设置入口、登录/卡片排版、邮件草稿桥。独立代码审查发现的日历/提醒冲突、默认排序额外计算和卡片无日期文案问题已修复并补回归。
- 验证：Flutter 全量 `854 passed / 1 skipped`；上海/洛杉矶各 `35 passed`；`dart analyze` 无问题；格式 184 文件 0 改动；原生 JVM 39 项、instrumented 编译、lint 通过；API35 仪器套件 15 passed/1 skipped，另邮件实际启动 1 passed；PowerShell 69、Python Gitee 25、工作流 8 项通过。
- 正式 APK：`chaoxing-journal-1.7.53.apk`，58,852,146 字节，SHA-256 `b3d1f25f9ab636e4f3b00a3f9e7cd68c2b5ac7a999b2769b0e25dd5b58fcc9b8`；`SHA256SUMS.txt` 94 字节；包名、60/1.7.53、min26/target36、双 ABI、v2 原证书、ZIP CRC 和 16 KiB 对齐通过。
- Release <https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.53> 已公开、非预发布并设为 latest；公开匿名完整回下载得到的 APK/校验文件大小、哈希、ZIP、签名和对齐一致。
- MuMu Android 15 从 `1.7.52+59` 同签名覆盖到正式包，`firstInstallTime` 保持 `2026-11-04 19:05:10`，登录态、7 门课程与作业保留；实际核对三筛选、五排序、四入口/二级页、Gmail 成功启动与无客户端回退，设备 `base.apk` 哈希与正式 APK 一致。
- 文档已切到 1.7.53，新增执行方案、完整验收记录和截图证据；后续文档提交不移动 Tag，应用源码以 `0705a9e` 为准。
- 未完成：Gitee `v1.7.53` APK 尚未由维护者本机上传，Gitee manual 仍为 `1.7.52+59`，必须在新 APK 匿名回下载校验后通过现有 workflow 更新；群聊漏拉、年份/状态补全、音效、完整反馈服务、API31、锁屏、TalkBack 与实体手机后台/Doze 仍未验证。

## 2026-11-14 1.7.53 UI 边界纠正

- 维护者明确纠正：本轮任务是修复功能，并未要求 UI 大重构；以后未被明确要求时不得顺手修改布局、排版、字体、字号、字重、颜色、图标、动画、导航结构或设置分组。该约束已写入根 `AGENTS.md`。
- 字体核查：从 `7b6ab7a` 到 `5860944` 没有修改 `journal.dart`、字体资源或字体主题；新增的 `lpinyin` 仅用于排序键，不复用为界面字体。因此没有进一步回退字体。
- 已在 `codex/revert-unrequested-ui` 恢复登录协议区和作业卡片的 1.7.52 视觉结构，同时保留期限分类、排序、状态冲突待确认和邮件草稿功能。
- 按维护者当前明确要求，仅重新启用“学习与同步”收纳：顶层保留“同步学习通 / 个人安排 / 显示与小组件 / 学习记录”，二级页继续进入原有功能路由；其余 1.7.53 视觉改动不恢复。
- 验证现场：定向登录/作业卡/设置测试 `33 passed`；全量 Flutter `855 passed`；`dart analyze` 无问题；ASCII 副本以原签名重建 Release 并覆盖 MuMu，`firstInstallTime` 保持 `2026-11-04 19:05:10`。未创建新 Tag、未发布新 APK、未上传 Gitee `v1.7.53`。

## 2026-11-14 1.7.54 发布节奏与筛选时间栏修复正式发布

- 功能提交 `9b74f41` 经 PR #22 合并到 main `06eb2df4e60fbf9c6a8e4639d04450204889597b`；annotated Tag `v1.7.54`（object `9f80247fe150dd5999b6dfa0c6263d0465cc1c75`）指向同一提交。版本 `1.7.54+61`。
- 期限筛选固定为“全部 / 未截止 / 已逾期”，全部第一；旧 7 天/30 天/待确认偏好归一为全部，无截止偏好归一为未截止。
- 截止时间、课程名称和作业名称排序统一在卡片左上角显示“日期在上、时间在下”，正文不再重复小字截止日期。
- GitHub 发布规则改为每个正式包必发；Gitee workflow 删除 `schedule` 与逐 Release 触发，只保留 `workflow_dispatch` 的手动批量镜像。长期路线图按产品定位重排，作业拉取完整性、截止可信度与同步可靠性列为 P0。
- 验证：Flutter 全量 `856 passed`；上海/洛杉矶各 `35 passed`；`dart analyze` 无问题；格式 190 文件 0 改动；原生合成检查 41+38 项、PowerShell 69、Gitee synchronizer 25、workflow 8 和 `actionlint` 通过。PR CI `43550735940`/`43550770956`、main CI `43552014357`、Tag CI `43552683041` 均成功。
- 正式 APK：`chaoxing-journal-1.7.54.apk`，58,852,146 字节，SHA-256 `6f9a2e3d4e2cbf491c5382a2be8d864a72816d5578e50490df2d5dbe1bd8fc62`；`SHA256SUMS.txt` 94 字节，SHA-256 `4454827559a23680043a2516e53936b4031166f664fb877ce4a24f00ee81fc79`。包名、61/1.7.54、min26/target36、双 ABI、v2 原证书、ZIP CRC 与 16 KiB 对齐通过。
- Release <https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.54> 已公开、非预发布并设为 latest。草稿资产与公开匿名资产均完整回下载并通过哈希、digest、ZIP、签名和对齐核对。
- MuMu Android 15 从 `1.7.53+60` 同签名覆盖到正式包，`firstInstallTime` 保持 `2026-11-04 19:05:10`，登录态与课程作业保留；实际核对三筛选项顺序，以及课程名称/作业名称排序的左上角日期时间。设备 `base.apk` 哈希与正式 APK 一致。
- 文档新增执行方案、完整发布记录和三张 MuMu 证据；后续文档提交不移动 Tag，应用源码以 `06eb2df` 为准。
- 未完成：Gitee manual 仍为 `1.7.52+59`，本版按新规则不逐包上传，等待下一次维护者选择的批量点；Gitee 大陆多网络、群聊漏拉、年份/状态补全、音效、完整反馈服务、API31、锁屏、TalkBack 与实体手机后台/Doze 仍未验证。

## 2026-11-14 1.7.55 GitHub + Gitee 双更新渠道正式发布

- 按用户要求本对话只做阶段一，不改首页作业 UI。功能提交 `f5cd6c0` 经 PR #24 合并到 main `9a31a88c1bdad569999f5cf91ac046e9e1a57198`；annotated Tag `v1.7.55`（object `074b2427a87ec87b79dd899cad5ed37728709c96`）指向最终 main，版本 `1.7.55+62`。
- 客户端默认官方源并行检查 Gitee manual 与 GitHub Release；同版本优先 GitHub 元数据，摘要/大小一致时 Gitee 主、GitHub 备，冲突只保留 GitHub。Gitee `404/410/408/429/5xx` 可使用备用 APK；忽略版本键稳定为显示版本并兼容旧键。
- Gitee 新增 Release published 自动 `index`，只更新小索引、不下载/上传 APK、不清附件、不推进普通补丁 stable；未镜像版本使用 GitHub `apkUrl` 且省略 backup。`latest` 与无 tag index 使用最高公开正式 Release。
- 验证：Flutter 全量 `871 passed / 1 skipped`；上海/洛杉矶各 `35 passed`；Gitee synchronizer `33`、workflow `10`、PowerShell 清单 `69` 通过；ASCII `flutter analyze`、格式 191 文件 0 改动、原生合成 41+38、Gradle JVM/仪器测试编译/lint 通过。`actionlint` 因本机 GitHub 下载 TLS 失败未安装，未宣称通过。
- PR CI `43567883131`、`43568386752`，main CI `43570064108`，Tag CI `43570850225` 均成功。正式 APK 58,852,230 字节，SHA-256 `36da9805eb6dd9dc69c28a89344fdcf94218de6ead68908eba8108f95acf5d60`；草稿与公开匿名完整回下载、digest、ZIP、v2 原证书、双 ABI 和 16 KiB 对齐均通过。
- Release <https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.55> 已公开、非预发布并设为 latest。MuMu 从 `1.7.54+61` 同签名覆盖，`firstInstallTime` 保持 `2026-11-04 19:05:10`，登录态与课程作业保留，设备 `base.apk` 哈希一致。
- Release 自动索引 run `43571846398` 成功：stable `1.7.4+56`、manual `1.7.55+62`、deleted `[]`；manual 的 `apkUrl` 为 GitHub 正式包且无 `backupApkUrl`。手动重跑 `43572300683` 输出 `changed=false`。隔离 `emulator-5554` 的 `1.7.53+60` 冷启动已从 Gitee 索引发现 `1.7.55`；该实例无登录态，只验证发现，不验证安装。
- 文档新增[1.7.55 双更新渠道验收与发布记录](../reviews/2026-11-14-1.7.55双更新渠道验收与发布记录.md)及两张证据；后续文档提交不移动 Tag，应用源码以 `9a31a88` 为准。
- 未完成：Gitee APK 仍停在 `1.7.52+59`，需维护者选定批量点后上传并完整校验；Gitee 大陆多网络、旧客户端完整下载/安装、API31、锁屏、TalkBack 与实体手机后台/Doze 仍未验证。首页作业日期分组 UI 留到独立对话以 `1.7.56+63` 发布。
- 下一对话交接：[2026-11-14 1.7.56 首页作业日期分组 UI 恢复](handoffs/2026-11-14-1.7.56-home-assignment-ui.md)。

## 2026-11-14 1.7.56 首页作业日期分组恢复正式发布

- 功能提交 `3aee756` 经 PR #27 合并到 main `ac253def270e180637ca4db3c30e6b0b5d30dfe8`；annotated Tag `v1.7.56`（object `c42d2377aca858a7d53e66f772e2fbb6cf75b2ea`）指向最终 main，版本 `1.7.56+63`。
- 首页五种排序统一复用可信日期 timeline：日期变化插入“11月14日 周六”式标题和分隔线，同时保持原 `sortedItems` 顺序；卡片左栏仅保留 `HH:mm`，正文不重复日期，语义保留完整截止信息。
- 无可信日期不生成标题；默认分组、待确认占位、“今天截止”、提交状态和逾期样式未改。未修改更新渠道、登录、日历、统计、设置、字体、颜色、图标或其他页面。
- 验证：定向 UI/排序/语义/窄屏大字体 `33 passed`；Flutter 全量 `875 passed / 0 failed`；上海/洛杉矶各 `35 passed`；元数据、格式、中文与 ASCII analyze、ASCII 原生 JVM/仪器测试编译/lint 通过。
- PR push/PR CI `43578134906`/`43578158098`、main CI `43579124538`、Tag CI `43579767584` 均成功。正式 APK 58,852,226 字节，SHA-256 `e051c04c755d0cf2ddfaf77f3967b931848092f4d2594bad41507e8522c9f837`；包名、63/1.7.56、min26/target36、双 ABI、v2 原证书、ZIP CRC 和 16 KiB 对齐通过。
- Release <https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.56> 已公开、非预发布并设为 latest；草稿认证下载与公开匿名回下载的大小、哈希、ZIP、签名一致。
- MuMu Android 15 从 `1.7.55+62` 同签名覆盖到最终包，`firstInstallTime` 保持 `2026-11-04 19:05:10`，登录态、课程作业和原筛选/排序偏好保留；设备 `base.apk` 哈希与正式 APK 一致。
- Gitee index run `43580639928` 成功：`manual=1.7.56+63` 指向 GitHub 且无 backup，`stable=1.7.4+56`，`deleted=[]`；APK 工具安装步骤 skipped，本轮未下载/上传 APK。
- 文档新增[1.7.56 首页作业日期分组恢复验收与发布记录](../reviews/2026-11-14-1.7.56首页作业日期分组恢复验收与发布记录.md)及 MuMu 证据；后续文档提交不移动 Tag，应用源码以 `ac253def` 为准。
- 未完成：Gitee APK 仍按批量点维护，本版未上传；Gitee 大陆多网络、实体手机后台/Doze、TalkBack、API31、锁屏及真实账号提交操作未在本轮重新验证。

## 2026-11-14 1.7.57 登录失败原因修复（已发布）

- 现场从 `codex/login-response-fix` 的 4 个未提交登录修复改动接手；基线 main `be68a52`（1.7.56 已发布）。保留既有未跟踪 `scripts/demo-video/`。
- 修复范围：登录失败读取平台 `mes/msg/msg2/message/errorMsg` 消息字段，安全验证/风控原因不再被统一替换为“请检查账号和密码”；无具体原因时提示“学习通未确认登录，请稍后重试”；Store 不再改写登录错误；新增默认关闭、仅记录响应结构的 `AUTH_DIAGNOSTICS` 诊断开关。不含 UI 改动。
- 验证：定向 30 项、全量 Flutter `881 passed / 1 skipped`（跳过为需 `RUN_STORAGE_BENCHMARK=true` 的容量基准）、截止 35 项本地通过、`dart analyze lib test` 无问题（build/ 下 6 条提示属 git 忽略的本机调查临时文件）、格式 0 改动、元数据/changed-format 通过、原生合成 41+38、Gitee 脚本测试通过。双时区与 Gradle 门禁由 CI 覆盖。
- 冻结 `1.7.57+64`：GitHub/Gitee 均无 `v1.7.57` 占用。提交 `9ee469c` → PR #29 → main `56cbf76`；push CI `43591358232`、PR CI `43591383773`、main CI `43592250319`、Tag CI `43592929259` 均成功。annotated Tag `v1.7.57`（object `7c8654b`）。
- 最终 APK 从 main 干净 ASCII 导出（325 个应用输入逐一哈希核对）原签名构建：58,852,146 字节，SHA-256 `6dcfff22c076c271d99912cd1ded4da724e394cbbf3d6a05786efaf1e27b7e17`；包名 `.journal`、64/1.7.57、min26/target36、双 ABI、v2 原体验证书 `d36a57…`、ZIP CRC 与 16 KiB 对齐通过。首次构建遇 Kotlin daemon 缓存关闭失败（Windows 文件锁），停 daemon 清理后重建成功，未改构建参数。
- MuMu Android 15（`127.0.0.1:16448`）从 1.7.56+63 同签名覆盖，`firstInstallTime` 保持 `2026-11-04 19:05:10`，登录态与 7 门课程作业保留，“关于我们”显示 v1.7.57 (64)，设备 `base.apk` 哈希与正式包一致。
- Release <https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.57> 已公开、非预发布并设为 latest（`published_at=2026-11-14T12:50:41Z`）；草稿认证回下载与公开匿名回下载（8 连接分段）的大小、哈希、清单、签名、对齐一致；旧 Release 与历史草稿未动。
- Gitee index run `43596793159` 成功：`manual=1.7.57+64` 指向 GitHub 同版本 APK 且无 backup，`stable=1.7.4+56` 不变；本轮未上传 Gitee APK。发布后 MuMu“检查更新”实际显示“当前已是最新版本”。
- 文档新增[1.7.57 登录失败原因修复验收与发布记录](../reviews/2026-11-14-1.7.57登录失败原因修复验收与发布记录.md)，更新验收基线与文档索引；文档提交不移动 Tag，应用源码以 `56cbf76` 为准。交接见[1.7.57 发布完成交接](handoffs/2026-11-14-1.7.57登录失败原因修复发布完成交接.md)。
- 未完成：登录拒绝文案实机触发未执行（不退出真实账号），由 30 项定向测试覆盖；Gitee APK 仍按批量点维护，本版未上传；实体手机后台/Doze、TalkBack、API31、锁屏、真实官方学习通通知链路（已接受缺项）未在本轮重新验证。

## 2026-11-14 首页单条作业与截止年份补全（1.7.58 已正式发布）

- 用户确认“我的课程”有多门，首页只有一条年份待确认作业。基线 `main / 166f6be`；功能提交 `0c59d53` 经 PR #30 合并到 main `f8e544b09bc9930f0112fb7e1583886666072ebd`，保留既有 `scripts/demo-video/`。
- MuMu `127.0.0.1:16448` 在 1.7.57 实际刷新：7 门课程全部关注，无首页课程/搜索偏好，无隐藏记录；本机 3 条正式作业中 2 条已提交、1 条待交。用官方 App 现有会话只读核对正式接口，7 门课程返回的合计亦为 3 条；这不证明未接入群聊等其他来源的完整性，也不能把空课直接记为漏拉。
- 已取得真实只读样本并定位日期问题：HTML 签名列表没有绝对开始时间，而同作业正式 API 的绝对开始时间与详情月日开始时间匹配到分钟；既有 HTML 路径没有向日期解析传递该证据。修复仅在缺年份时补查同课正式 API，复用既有身份/分页校验及严格开始时间匹配，不替换 HTML 列表/状态，不改视觉。
- 已观察合成回归修复前失败（应为绝对截止、实际 null）；独立审查的补充接口熔断、取消传播两项均先复现失败后修复并复核关闭。14 项新增边界、相关 51 项定向、全量 Flutter `895 passed / 1 skipped` 及 2 项真实响应私有回放通过；跳过项仍为需显式开启的容量基准。CI 上海/洛杉矶各 49 项，原生单测/仪器编译/lint、分析及双 ABI 构建通过；push `43604049860`、PR `43604085319`、main `43604915964`、Tag `43606103524` 成功。
- 正式包 `1.7.58+65` 从最终 main 的 326 个规范 Git 输入导出并核对；58,852,146 字节，SHA-256 `ec071279e612cd07388442aa85a0def0b5e2a54430eeab678904bd1a69275974`，原 v2 证书、SDK/ABI、ZIP CRC 与 16 KiB 对齐通过。MuMu 同签名覆盖保留 firstInstallTime、登录态和 7 门课程/3 条作业/提交状态，设备回拉 APK 哈希一致；实际刷新 `success / 7 成功 / 0 失败 / issues=[]`，原待确认作业恢复可信截止，首页显示日期标题与逾期状态。
- annotated Tag `v1.7.58`（object `81b933f2d9a7924a21f81f27583d4b3983b9689a`）指向最终 main。Release id `445367427` 已公开、非预发布并设为 latest（`published_at=2026-11-14T15:14:32Z`）；草稿认证回下载与公开匿名完整回下载的大小、哈希、清单、签名、对齐均一致；发布后 MuMu“检查更新”显示“当前已是最新版本”。完整验收记录见[1.7.58 截止年份补全验收与发布记录](../reviews/2026-11-14-1.7.58截止年份补全验收与发布记录.md)。
- Gitee index 自动 run `43609106687` 首次因读取 `/api/v5/user` 失败，核对对象状态后原样重跑成功；公开 manual 实测 `1.7.58+65` 指向 GitHub 正式包、哈希一致且无 backup，stable `1.7.4+56`，APK 镜像仍为批量点 `1.7.52+59`，本轮未上传镜像。
- 私有样本、构建/回放日志、APK 与 MuMu 证据在忽略目录 `artifacts/2026-11-14/course-investigation/`、`D:/campus-tools/build-work/release-1.7.58-final/` 和应用 `build/course_runtime_replay_test.dart`；真实响应和截图不得提交、外发或纳入构建导出。额外强停后冷启动命令组被自动审查拒绝（仅返回 blocked by policy），本轮未执行该项；安装后的实际启动/刷新已通过。实体手机后台/Doze、TalkBack、API31、锁屏、真实通知链路和群聊/消息来源仍为未完成项。

## 2026-11-15 P0 跨来源作业漏拉调查交接（仅文档）

- 用户再次明确“很多作业拉取不到”是尚未解决的核心问题；此前确认“我的课程有多门、首页只有一条、主页还没刷新好”。1.7.58 只修复可信开始时间证据下的签名作业截止年份，未解决群聊/消息、活动、考试或教务等来源覆盖，不能把正式接口某次 7 门课程 0 失败当作作业完整。
- 新增[P0 跨来源作业漏拉调查交接](handoffs/2026-11-15-P0跨来源作业漏拉调查交接.md)：记录当前 `main / 81b6fe1` 基线、已连接的正式课程作业路径、首页/本地记录/合并过滤边界、逐来源样本采集矩阵、八项可证伪假设、定位丢失层的阶段门、真实案例验收口径与隐私禁止事项。下一轮先取得至少 2–3 个真实脱敏遗漏案例；无样本只做采集与只读诊断准备，不改解析、不猜根因、不升版发布。
- 本轮只新增交接并更新文档入口，未修改业务代码、未运行业务测试/构建、未操作设备、未发布；既有未跟踪 `scripts/demo-video/` 保留。应用源码锚点仍为 Tag `v1.7.58` 指向的 `f8e544b`。

## 2026-11-15 课程群作业跨来源根因调查（一期修复前历史）

- 用户明确缺失来自课程群发布、收件箱未通知的作业，要求自行搜索 GitHub 和接口取证，MuMu 可能缺聊天历史。已更新交接的取证路径，使用当前账号服务端响应作为真实样本。
- 以 `main / 2cf9eb1` 为代码基线，7 门课程的 HTML、正式 API、手机 H5 和账号作业列表识别出的 3 个正式作业身份一致。官方 `/v2/apis/active/student/activelist` 另返回 17 条活动，含 3 条随堂练习、1 条个人任务、2 条 AI 实践，其余为签到和讨论。C06 正式作业 0 条，但个人任务有北京时间 `2026-12-02 00:00` 截止，元数据读取成功且 `isDelete=0`，本地 journal 无此身份。
- 真实响应 Dart 回放确认三处缺口：客户端未请求活动及任务源；旧活动解析器丢弃这条个人任务，类型表还含投票/群聊/计时器；解析出的 3 条随堂练习经 `AssignmentQuery.scope` 全部排除。问题已定位，代码修复待实施。
- 任务引擎链也已实际展开 1 组、2 条计划，数量与 `planCount` 一致。`gas/taskmsg` 返回 HTTP 403，独立 IM 群完整历史、真实作业计划及精确个人提交状态仍待覆盖。调查记录见[课程群作业来源与漏拉根因](../research/2026-11-15-课程群作业来源与漏拉根因.md)，含固定 GitHub 来源、接口矩阵和最小修复范围。
- 本轮执行只读接口验证和本机现有代码回放，业务源码及 `1.7.58+65` 保持原基线。原始数据与探针在 Git 忽略的 `artifacts/2026-11-15/cross-source-investigation/` 和应用 `build/`，交付范围为脱敏调查文档、交接与入口更新。既有 `scripts/demo-video/` 保留。

## 2026-11-15 课程活动补拉一期候选验收（历史，已由下方正式发布记录取代）

- 从main `02a8cd6`进入`codex/course-group-homework`，候选`1.7.59+66`，已提交并推送PR，尚未合并或发布。当前工作区的业务修改和新测试均属本任务，既有未跟踪`scripts/demo-video/`保留。实施与证据索引见[执行方案](../plans/2026-11-15-课程群作业完整性修复执行方案.md)。
- 正常完整同步入口的私有真实响应回放保留3份正式作业，并补出1份35个人任务和3份42随堂练习，共7份进入统一范围；35当前样本为pending并确认北京时间12月2日00:00截止，42样本均submitted。持久化、首页/日历/统计/计划、受限官方跳转、个人状态与提醒来源基线已贯通；77排除，正常AI课程正式作业保留。
- 已修复来源隔离/取消、课程索引覆盖、备份恢复身份、重复别名提醒与混合聚合通知失效边界。界面只增加必要来源状态与分类文字。journal/原生SQLite升至2，备份升至4并读旧版；新版备份需新版客户端恢复。
- Dart定向96、62及最终个人状态/真实回放20项通过；原全量975通过/1可选基准跳过不能覆盖后续修改，最终完整CI仍待执行。最新原生unit/测试编译/lint已通过，最终独立QA包22项仪器通过，包含新增5项聚合通知回归；此前旧17项通过，不等同正式包实际刷新已验证。正式包尚未构建或覆盖安装。日志与响应留在忽略的artifacts、local_app/build和ASCII构建目录。
- 独立群云历史二期尚未实施，仅证实SDK源码能力；实际AppKey多端并存、SSO字段与群历史可见范围未实测，不能声称群聊作业已全部覆盖。下一步完成新增原生回归、最终PR/main/Tag CI、原签名包及MuMu真实刷新，再继续二期账号调查。

- 首轮功能提交`1b876b2`已推送并建立[PR #31](https://github.com/arrry-07/chaoxing-journal/pull/31)。该HEAD的CI通过；原签名候选在MuMu真实刷新后为7条记录、5 submitted/2 pending，7课程成功/0失败，新增任务截止可信。实际入口联调发现原生分享桥接仍仅允许work路径，已新增受限课堂路径及身份参数校验；JVM旧用例先失败、修复后53项策略/迁移检查通过，须以随后新HEAD的CI与包重新验证跳转。

## 2026-11-15 1.7.59正式发布与下一补丁范围

- 首轮功能 `1b876b2`、原生桥接修复 `040239ba93107c377589e37d15e734deec3ab4ae` 经[PR #31](https://github.com/arrry-07/chaoxing-journal/pull/31)合并；当前 `main / cdc8477ff3f7250c333b0c399e7ab88534dba33a` 与Tag `v1.7.59`一致。[GitHub Release](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.7.59)已公开且非预发布。文档收口不移动Tag，旧候选不再代表当前状态。
- 一期贯通35/42的采集、个人状态、可信截止、持久化、共享展示范围、受限官方跳转与提醒来源基线；正式作业保留。最终PR与main原始CI日志均为 `988 passed / 1 skipped`，双时区各49项；main [43707730435](https://github.com/arrry-07/chaoxing-journal/actions/runs/43707730435)、Tag [43708761448](https://github.com/arrry-07/chaoxing-journal/actions/runs/43708761448)均成功。dev独立QA仪器日志为22项通过；早期975/1、17项及首轮候选跳转不替代最终证据。
- 正式APK为 `1.7.59+66`、58,983,218字节，SHA-256 `f12d6821034dcd2a436137ee296682de7f1d96a104c003529c6dd46efc64650e`。本机晋升记录确认r2候选到main的335个跟踪输入相同、签名配置相同且无提交号派生元数据；最终与公开回下载身份一致，本轮重新计算公开回下载APK哈希一致。原v2证书、双ABI、SDK与对齐日志已核对。
- 设备覆盖快照显示版本由1.7.58+65变为1.7.59+66、原首次安装时间保留；脱敏运行摘要为7门课程/7条记录、5 submitted/2 pending、同步7成功/0失败。这些摘要未绑定设备端APK哈希及最终原生跳转结果，相关独立核验仍有证据缺口；本轮未读截图、未操作设备。
- Gitee index [43711528680](https://github.com/arrry-07/chaoxing-journal/actions/runs/43711528680)成功；公开清单实测 `manual=1.7.59+66`、`stable=1.7.4+56`，manual指向GitHub同版本APK、大小/哈希一致且无backup。APK镜像仍为 `1.7.52+59`，本版未镜像。
- 最新用户纠正：77 AI实践属于官方课程任务页内要拉取的课程作业，下一补丁优先处理。服务端2条77与用户页面对应，学生入口 `/ai-evaluate/v2/redirect/active/stu` 已确认落到 `/mooc2-ans/ai-evaluate/v2/answer`；个人状态接口仍由主代理调查。1.7.59冻结源码只准入35/42，不能声称1.7.59支持77，也不能把一期历史排除当成当前要求。
- IM脱敏摘要确认SSO归属匹配、当前账号token读取成功及6个加入群，6群当前云历史只返回1张签到卡。不足证明无群作业，也未证明历史留存/可见范围完整或多端并存策略；产品 `groupHistory=notEnabled`，探针未接入产品。
- 证据及限制见[验收与发布记录](../reviews/2026-11-15-1.7.59课程活动补拉验收与发布记录.md)、[执行方案](../plans/2026-11-15-课程群作业完整性修复执行方案.md)、[根因调查](../research/2026-11-15-课程群作业来源与漏拉根因.md)。本轮仅更新获准五份文档，未提交/切分支/构建/发布；保留 `scripts/demo-video/`。主代理继续77协议与个人状态调查，新补丁不能直接继承1.7.59的通过结论。


## 2026-11-15 AI实践77接入与回归

- 分支 `codex/ai-practice-homework`，应用基线仍为1.7.59+66；尚未冻结下一版本、构建或发布新APK。旧Tag/Release不变，保留无关 `scripts/demo-video/`。
- 已定位并接入官方只读 `GET /mooc2-ans/ai-evaluate/v2/answer/load-data`。PPT活动ID、发布UUID与个人发布关联UUID分别使用；页面当前用户、课程/班级、cpi及个人响应关联逐项校验，个人响应personId对应cpi。发布UUID仅本机持久化，不作为业务主键或备份导出字段。
- 77进入正常完整/逐课采集、来源报告、统一范围和双端受限学生入口；备份保持schema4，恢复后的个人状态和截止重新在线核对。最小界面变化仅为同步来源增加“AI 实践”，未改布局/字体/颜色。
- 私有当前账号响应通过正常客户端回放：正式3、35任务1、42练习3、AI实践2，共9条进入统一范围；AI分别待完成/已达标，截止可信。响应、成绩、截图和回放均仅留忽略目录，没有练习、上传、提交或发送消息。
- 首轮全量998通过/1项可选存储基准跳过；审查后补充取消/换会话、混合来源拒绝/限流与77实际备份恢复重同步，定向85项及隔离11项通过，ASCII静态分析无问题，原生AI跳转8项通过。最终全量原始日志 `study_assistant-1.1.0/local_app/build/ai-full-final.log`，结论须读原日志。独立只读审查未发现明确缺陷，指出的三项缺测已补充。
- 下一步：最终diff/全量核对后提交推送，冻结下一补丁并执行PR/main/Tag CI、原签名包、MuMu真实刷新和GitHub发布门禁。群云历史产品源仍未启用，不能宣称覆盖所有群聊作业。

- AI77最终本地集成：`ai-full-final.log` 为1017通过/1项可选基准跳过；`ai-analyze-final.log` 为No issues found；`ai-native-full.log` 为41项加密、53项策略/升级、8项AI入口及更新策略通过。应用元数据仍为1.7.59+66的开发基线，未创建新Tag或APK。

## 2026-11-16 1.8.0 AI实践与考试信息（已正式发布）

- 功能提交800c526经[PR #32](https://github.com/arrry-07/chaoxing-journal/pull/32)合入main `c49ebf314e0c023f321c0eb8e4f2a4c57d5ae201`；Tag `v1.8.0`（object532a37e）指向该源码。后续文档收口不移动Tag，保留既有`scripts/demo-video/`。
- 已接入AI实践77、课程/账号考试及考试通知真实名称/起止/时长/地点字段；完整身份关联当前日程与个人状态，成对唯一借年，访问参数不落盘，隐藏开考弹窗与可见验证分开。首页类型筛选、开考日日历/提醒、受限官方入口、schema5备份兼容旧1–4及SQLite3提醒已贯通。
- 本地最终集成201项通过；PR/main/Tag CI [43750103838](https://github.com/arrry-07/chaoxing-journal/actions/runs/43750103838)、[43751194090](https://github.com/arrry-07/chaoxing-journal/actions/runs/43751194090)、[43752275738](https://github.com/arrry-07/chaoxing-journal/actions/runs/43752275738)均1113通过/1可选基准跳过、双时区各49项，原生/分析/双ABI通过；隔离设备21项仪器证据按不变输入复用。
- 正式APK `1.8.0+67`，59,310,902字节，SHA-256 `5af830a57dccb419b731475ea24497270b3a3b7010ed85205f5c0c93feff504b`；原包名/v2证书、SDK/ABI、ZIP与16KiB对齐通过。350规范应用输入及构建/签名配置与main一致，完整r3候选晋升正式包；早期r1/r2未公开。
- MuMu原实例同签名覆盖、base.apk哈希一致、首次安装时间2026-11-04 19:05:10保留。实际刷新7课程/12记录（9submitted/3pending）、已启用来源成功/无issues；1考试和2通知均有真实名称、可信完整起止及60分钟时长，关联已完成状态，在本地记录保留详情；原9条课业、偏好语义、计划/笔记保留。实体考场未提供时明确说明，不造教室。
- [Release v1.8.0](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.0) id446312101于北京时间2026-11-16 03:41:54公开、非预发布并设latest；草稿认证与公开匿名完整回下载的大小/摘要/身份/签名/对齐均通过。发布后手动检查更新显示“当前已是最新版本”。
- Gitee [index43753863996](https://github.com/arrry-07/chaoxing-journal/actions/runs/43753863996)成功，manual/stable实测均1.8.0+67、指向GitHub同包、无backup，deleted=[]；本版未上传Gitee APK，镜像仍为公开元数据中的v1.7.52批量点，未重下历史镜像。
- 证据及完整限制见[1.8.0验收与发布记录](../reviews/2026-11-16-1.8.0AI实践与考试验收与发布记录.md)。独立群云历史未启用、账号考试非空真实样本及实体手机/Doze/TalkBack/API31/锁屏通知未重验；未开始/改期/取消等以合成回归覆盖，不宣称全来源完整。私有样本/结构/日志留在忽略的artifacts、应用build及ASCII构建目录，不进Git/构建。

## 2026-11-16 1.8.01 体验与考试待办修复（已正式发布）

- 功能a8b03c9、审查修正691bb7a经[PR #33](https://github.com/arrry-07/chaoxing-journal/pull/33)合入应用源码 `fe4727d6042ed240d0717dd1a12d4f6e017123e0`；annotated Tag v1.8.01（object c752ae04）指向该源码。后续分发修正fae4428和文档不移动Tag、不改变应用输入。
- 考试未知字段/横杠占位精简、结束退出待办而保留历史、严格身份投影和冲突字段保护、日历/计划/小组件一致性、4类型3排序及旧偏好兼容已实现；提示5/12秒及销毁/所有权保护、通知冷启动与编辑守卫、协议对齐及主题退出已验证。原生及备份schema5不变。
- 最终PR/push/main/Tag CI43784117519/43784112294/43785175196/43786480082均1171通过/1可选基准跳过，双时区各49，原生/分析/双ABI通过。分发兼容main CI43787370431同矩阵通过。初期失败与修正记录保留于验收记录，不冒称旧失败全量已通过；最终定向74及PR补充49通过。
- 正式1.8.01+68 APK59,310,978字节，SHA-256 `ae6655d3d433ac632dad76ad67041136b7f6ad056d7e1ea07d8a890e86f9d29c`；原包名/v2签名、SDK/ABI、ZIP/对齐通过。359个规范输入及构建参数/配置与main相同，完整r2候选晋升，不重复构建；r1未公开。
- 原MuMu覆盖，设备回拉哈希一致，首次安装时间2026-11-04 19:05:10保留；14条ID/状态、7课程、隐藏0、筛选、个人安排和笔记保留。真实卡片/日历/筛选/主题/普通提示自动消失及r2原始通知冷/热启动通过；带操作提示期限由widget回归覆盖，未声称设备观察过该期限。
- 三次r2刷新14.058/17.633/12.148秒均partial：正式及35/42/77各7课成功，考试6成功/1结构失败、账号考试结构失败、通知成功。不能据此声称完整同步提速或所有来源完整。
- [Release v1.8.01](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.01) id446515277于北京时间2026-11-16 09:45:22公开、非预发布、latest；草稿认证和公开匿名完整回下载的摘要、包信息、签名、ZIP/对齐通过。发布后手动检查更新显示当前已是最新版本。
- Gitee旧Tag自动index43788103449因两位补丁号失败，main脚本35项及workflow10项通过后仅index补跑[43788666316](https://github.com/arrry-07/chaoxing-journal/actions/runs/43788666316)成功，deleted=[]。公开manual=1.8.01+68指向GitHub同包、无backup；stable保持1.8.0+67，APK镜像仍1.7.52+59，本版未镜像、未重下历史包。
- 完整证据及未覆盖项见[验收与发布记录](../reviews/2026-11-16-1.8.01体验与考试待办验收与发布记录.md)，后期项见[执行方案](../plans/2026-11-16-1.8.01体验与考试待办修复执行方案.md)。保留无关scripts/demo-video/；原始响应/截图/日志仅忽略目录，不进Git。
- 用户最新后续任务仅讨论：通知已有月日起止但未展示，需区分采集/解析与可信年份限制；优化考试分组/今日计划位置，核对筛选持久化。尚未授权下一轮编码，不将该反馈记作已解决。

## 2026-11-16 1.8.02 通知原文时间与首页整理（未公开候选，已由1.8.03接续）

- PR#34合入应用main690d7c1，annotated Tag v1.8.02 object d37db582固定不移动；PR/main/Tag CI均1204通过/1可选基准跳过，双时区各49。四项审查修正已关闭。
- r2候选1.8.02+69，SHA-256 0c5d76a5cb68adebb603df3c9122af32e0d6f2bab91430b5e891b547b1123122，原签名/身份/ABI/对齐通过，MuMu保数据验收通过。Release446581392保持草稿未公开，不能声称该版本正式发布；1.8.01仍是公开下载。
- 用户在公开前追加考试时间轴布局，后续由1.8.03接续；本轮不会公开中间候选或覆盖其Tag/APK。

## 2026-11-16 1.8.03 考试时间轴（已正式发布）

- 功能提交5e167a8经[PR #35](https://github.com/arrry-07/chaoxing-journal/pull/35)合入应用源码 `9f57d8a3ff60a463779987d92a33d27a67d0cb3d`；annotated Tag `v1.8.03`（object `8029551549eb11382ddb1fef1e65930213f41c22`）指向该源码。1.8.02 Tag与Release草稿保留，未公开中间版本。
- 考试列表已使用作业式日期标题、分隔线、左侧开考时刻和右侧名称；详情保留完整起止及秒。未注明年份只显示月日，不猜年份或星期，不改变排序、日历、提醒和自动结束依据。今日计划轻入口、筛选持久化及1.8.02通知时间修正一并包含。
- 本地180项相关回归及读屏修正后的11项组件检查通过，lib/test分析无问题。最终PR/push/main/Tag CI [43800780975](https://github.com/arrry-07/chaoxing-journal/actions/runs/43800780975)、[43800774542](https://github.com/arrry-07/chaoxing-journal/actions/runs/43800774542)、[43801650831](https://github.com/arrry-07/chaoxing-journal/actions/runs/43801650831)、[43803621566](https://github.com/arrry-07/chaoxing-journal/actions/runs/43803621566)均1219通过/1可选基准跳过，双时区各49项，原生/分析/双ABI通过。
- 正式1.8.03+70 APK 59,442,050字节，SHA-256 `0e43d8a0503b0f09b6243c6b0c3862bf774a8834f9fb8138ea6546dba2521825`；原包名/v2签名、SDK/ABI、ZIP及16KiB对齐通过。r2完整候选的364项应用输入、签名和构建参数与最终main一致，按证据晋升，不重复构建。
- MuMu原实例覆盖验收通过：真实列表显示11月16日标题、左侧07:06和考试名称，详情保留秒级完整区间；作业样式、今日计划、筛选重启记忆及原14条记录/7课程/笔记均保留。设备回拉APK同哈希，首次安装时间2026-11-04 19:05:10未变；发布后实际检查更新显示当前已是最新版本1.8.03(70)。
- [Release v1.8.03](https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.8.03) id446608223于北京时间2026-11-16 12:34:04公开、非预发布并设latest；APK asset753448807、SUMS asset753448822。草稿认证和公开匿名完整回下载的大小/摘要/身份/签名/对齐均通过。
- [Gitee index43804878614](https://github.com/arrry-07/chaoxing-journal/actions/runs/43804878614)成功，公开manual=1.8.03+70指向GitHub同包且无backup，stable保持1.8.0+67，deleted=[]；镜像批量点仍为1.7.52+59，本版未镜像、未重下历史包。
- 完整证据及未覆盖项见[1.8.03验收与发布记录](../reviews/2026-11-16-1.8.03考试时间轴验收与发布记录.md)。现有部分考试来源结构失败、群云历史未启用、实体手机/Doze/TalkBack/API31/锁屏通知及本版日历全流程未重验；GitHub云端代码审查因额度未完成，不列作通过。

## 2026-11-16 1.8.04 首页排序与筛选修复（实施中）

- 用户反馈考试有明确通知时间却排最后，“未逾期”筛选后考试消失，类型“作业”只显示3份中的1份。基线1.8.03+70，目标1.8.04+71；范围见[执行方案](../plans/2026-11-16-1.8.04首页排序与筛选修复执行方案.md)。
- 已提取共用只读通知时间证据；可信开考优先，无年份唯一通知按当前北京时间年份仅投影到排序和期限筛选，不改模型信任、日历或提醒。显式筛选改为覆盖可见完整目录，未筛选首页仍只显示当前待办。
- 新增双向混排、课程内时间、无年份闰日、当前考试窗口、纯历史课程和三份作业历史回归。独立审查发现的历史课程下拉及通知时长冲突均已修正。最终本地全量1231通过/1可选基准跳过，lib/test分析无问题；真实缓存回放确认默认作业1条、筛选作业3条且当前考试进入未逾期。尚待CI、APK和MuMu验收。
