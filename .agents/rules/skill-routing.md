---
description: 学习通课业手记任务级必调 Skill 强制前置路由表
trigger: always_on
---

# 学习通课业手记 · 任务 → 必调 Skill 强制路由表

在动手修改代码、输出设计/重构方案或执行验收发版命令**之前**，只要当前任务命中下表任一场景，**必须先调用 `read_file` 读取对应本地 `SKILL.md` 并按其步骤执行**——即便用户提示词已经写得很详细，也严禁凭模型自身经验跳过加载。

| 任务场景（含日常中文口语信号） | 必调主 Skill（先读再动） | 按需协同 / 明确排除边界 |
| --- | --- | --- |
| **1. 模糊新需求探讨 / 多方案路线权衡**（“想加个…怎么设计好”“先聊下思路”） | `brainstorming` | 需严苛挑刺盘问隐含假设时改读 `grilling`；**需求明确的小步修改/单点修复直接施工，不触发本项** |
| **2. 整理用户口语反馈 / 群聊吐槽进台账**（“把这段吐槽整理成问题单”） | `feedback-to-md` | 仅提取现象、诉求与 `FB-xxx` 编号，不读源码、不混写技术方案 |
| **3. 疑难 Bug / 偶现异步交错 / 同步或时间信任状态异常排查** | `diagnosing-bugs` | 先建立离线合成夹具或最小确定性红灯复现回路再改代码；单行拼写/明显编译报错豁免 |
| **4. 明确要求修改视觉 UI / 浅深色主题 / 排版与交互精修** | `impeccable` | 检索色板/对比度搭配 `ui-ux-pro-max`；审查按压/过渡细节手感搭配 `emil-design-eng`；无明确 UI 修改要求时只做最小状态改动 |
| **5. Flutter 布局溢出 / 约束报错 / 窄屏大字截断适配**（`RenderFlex overflowed`、括号截断） | `flutter-fix-layout-issues` | 新建跨宽度弹性布局搭配 `flutter-build-responsive-layout`；勿套用 Web CSS 动效技能（`animate`/`mobile-native`） |
| **6. 核心解析 / 时间信任 / 首页排序（FB-005）回归单测与组件测试** | `tdd`（逻辑接缝回归）<br>`flutter-add-widget-test`（Widget 交互） | 涉及 `AssignmentStore` 等大体量模块接口收敛或解耦时先读 `codebase-design` |
| **7. 第三方 Flutter/Dart 依赖 API 核对与升级** | `find-docs`（或调 `context7-docs` MCP） | 先查 `study_assistant-1.1.0/local_app/pubspec.lock` 锁定版本；本仓内部逻辑直接读源码与测试 |
| **8. 独立分支 / PR 代码审查与 PR 正文撰写** | `code-review`（独立双轴审查）<br>`pr`（写 PR 正文） | 仅在主对话单独要求双轴代码审查时走 `code-review`（无 `.gitnexus/` 不走 `gitnexus-review`）；**`/goal` 内的 Gate 子代理审查按[验证规则的审读要求](../../docs/ai-workflow/VALIDATION.md#协作与发布审读)直审，禁套 `code-review` 再嵌套开子代理**；查远端 CI 配 `github` |
| **9. 收口验收、自测/正式 APK 打包、MuMu 验收与 GitHub/Gitee 发版** | 收口验收用 `verified-delivery`，APK 与发版用 `release-chaoxing-journal` | 路径位于 `C:/Users/Administrator/.gemini/config/skills/<技能名>/SKILL.md`。验收直接用仓内 `verify_local_gate.py` 和适用的 `verify_apk_and_report.py`；跨节点续接读 `chaoxing-release-fast-path` 判断证据是否仍有效。 |
| **10. 工程方案 / 风险分档与独立审查 / 分阶段交付** | 全局 `staged-release-gate`（`C:/Users/Administrator/.gemini/config/skills/staged-release-gate/SKILL.md`） | 分档、是否分窗及委派以全局技能为准。跨模块先读[架构导航](../../docs/architecture/ARCHITECTURE.md)，实际编排 `/goal` 时再读技能的自动化参考。项目检查、MuMu 早预览与发布权限见[验证规则](../../docs/ai-workflow/VALIDATION.md)。 |
