# 审查整改实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax for tracking.

**Goal:** 修复审查报告 F01–F15，落实可验证的 R01/R02/R03/R05 防线及可靠作业网页入口。

**Architecture:** 沿用 Flutter/Material/Journal 和现有原生 MethodChannel。核心状态统一串行，账号切换使用 owner 校验及备份后清理旧账号活跃缓存；不额外引入数据库或依赖。App 直达不猜协议，先提供浏览器入口。

**Tech Stack:** Flutter/Dart、Kotlin、现有 Android SDK。

**Spec:** docs/reviews/2026-11-05-全项目审查.md；覆盖边界见同目录审查覆盖清单。

## Global Constraints

- 保留当前包名、签名、依赖锁和视觉体系；不发布 APK、不使用真实账号做测试。
- 回归测试先失败再实现；纯文案/配置按风险检查。各任务只改分配文件，主代理整合后统一提交。
- 旧时间不猜时区：无偏移截止保留原值但降为待确认，重新同步后恢复可信；新时间 UTC 落盘。
- owner 缺失的旧安装仅能绑定当前已保存的账号；成功换号前备份旧活跃数据，再清理跨账号范围、通知和组件。切号失败不得污染旧身份。
- 设备依赖项目如无法实际运行，记录未验收项；不将源码改动等同于设备验证通过。

## Review Focus

- 持久化失败、未来 schema 和失败切号不得删除或混合旧记录。
- 默认未同意协议、大字号和 TalkBack，保存异常后可以重试。
- 未登录通知及直接深链保留经过验证的内部目标，换账号不得打开前账号缓存。
- URL 拒绝异常 scheme/host/userinfo/端口和身份冲突；浏览器启动成功不等于页面加载成功。
- 取消下载、超大流和 WebView 结束/退出必须清理资源；不扩大原生可导出面。

## Task 1：数据与恢复（主代理）

**Files:** services/assignment_store.dart、models/{assignment,widget_snapshot,sync_report}.dart、local/local_assignment_repository.dart 及核心测试。

**Interfaces:** 保留 `updateCompletion` 的 Future<void> 兼容性，增加 `Future<bool> hideAssignment(String id)` 返回明确结果供详情页使用；新增原生清理可由安全存储 clear 调用。账号切换后清空活跃旧集合并 owner 校验；提醒重排统一队列。

- [x] 写切号/时间/部分失败重启/附属缓存损坏/提醒交错失败测试并运行 RED。
- [x] 实现 F01/F03/F05/F06、R01，保持现有解析业务。
- [x] 运行核心回归，记录 GREEN 与迁移选择。

## Task 2：协议、退出与设置（界面代理）

**Files:** features/{login,profile,reminder_settings,sync_status,help_feedback}_screen.dart、新协议内容页面、对应 UI 测试。

**Interfaces:** 不修改 Store；继续调用 logout/saveReminderRule。登录默认未同意；保留主代理之外的路由行为，导航代理会负责登录成功目标。

- [x] 写可读协议/勾选语义/退出取消/保存失败/同步选中状态回归并运行 RED。
- [x] 实现 F02/F07/F08/F09/F11/F12，服务说明和隐私事实对应真实实现。
- [x] 运行 UI 回归并核对窄屏/大字号。

## Task 3：导航与作业网页（导航代理）

**Files:** main.dart、app/{app_deep_links,app_shell}.dart、features/assignment_detail_screen.dart、services/external_link_service.dart、新作业链接验证服务及其测试。

**Interfaces:** 使用主代理的 `Future<bool> hideAssignment(String id)`；登录成功目标修改由该代理与界面代理协调，避免同时编辑 login_screen。原生代理提供 `openBrowser` MethodChannel，参数 `{url:String}`，返回 bool；Dart 捕获平台异常，Android 使用显式浏览器选择。

- [x] 写登录后目标恢复、子页索引、详情北京时间、隐藏失败和链接验证/启动回归并运行 RED。
- [x] 实现 F04/F10/F13/F14；详情添加主按钮打开网页、保留刷新及主动复制入口，隐藏降为次要动作。
- [x] 运行相关回归；不实现未经验证的学习通 scheme。

## Task 4：原生、更新与升级探针（原生代理）

**Files:** Android 原生/资源、services/app_update_service.dart、tool/android_upgrade_probe、相关测试。

**Interfaces:** `openBrowser({url})` 仅允许 HTTPS，明确浏览器选择/处理；清理验证网站存储在结束和账号退出执行，不触碰其他 App 数据。

- [x] 为下载上限/异常流和升级样例断言写可执行回归并运行 RED。
- [x] 实现 F15、R02 备份排除、R03 生命周期清理与错误注释修正、R05 下载字节/总时限。
- [x] 运行回归并编译 Android；设备迁移和真实协议仍单独记录。

## Integration and delivery

- [x] 全套测试、静态分析、跨时区回归、Android debug 构建。
- [x] 用合成数据渲染修改页面；确认异常、空链接和大字号。
- [x] 独立审查整份 diff，修正重要问题并重跑相关检查。
- [x] 更新实施记录、文档与覆盖状态；commit/push GitHub，不发布 APK。

## Rulings

- 复用当前干净检出并使用修复分支，不另建工作树；遵从平台默认复用检出的要求。
- 审查阶段的只读限制不作为本次实现测试的限制；本次使用合成测试与本地工具链，不执行真实学习通账号请求。
- 各独立范围并行实现；主代理合并接口、复核测试并统一提交，不允许代理分别提交共享工作区。

完成记录：见 docs/reviews/2026-11-05-整改实施记录.md。设备验收和未经验证的App协议不标为完成；本计划复选框指本轮源码实施与可用检查。
