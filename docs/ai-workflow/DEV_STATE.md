# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办。

## 2026-11-24 · v1.9.0 Stage 1 Gate 增量返工

- 已完成改动：切号回归实际恢复账号 B 后检查手记和置顶隔离。360dp 常规字号手动卡片避让完成按钮，并与学习通卡片对齐拖拽手柄。置顶保存后仅检查会话归属，学习通空课名保留为空，缺年考试投影仅用于普通时间轴。仪器测试脚本识别结果 `shortMsg`、`INSTRUMENTATION_FAILED` 与停在 `STATUS_CODE=1` 的用例。
- 当前 commit 与状态：本记录所在提交基于 `d97ba40`，版本为 `1.8.26+120`。本地门禁通过，含 7 个 Flutter 文件 91 项、9 组 Python 共 99 项、Dart 分析 0 问题及 `FB-005` 回归。隔离旧实现触发 5 个 Flutter 回归失败，仪器测试清单覆盖 21 个类，受保护设备 dry-run 拒绝执行。门禁日志 `chaoxing-v1.9.0-gate-20261124-112723.log`。
- 下一步待办：对 `d97ba40..HEAD` 做 Gate 增量复审。MuMu 实机界面、隔离仪器测试和云端全量 CI 待相应验收，正式发布须等复审通过及维护者授权。

## 2026-11-24 · 工作流规则：审查提示词轻量化

- 已完成改动：`VALIDATION.md` 增补「审查/复审提示词只给基线、范围、必读文件、硬边界与输出格式，不替审查模型罗列检查清单」；跨会话记忆同步更新。
- 当前 commit 与状态：本提交为工作流文档；功能 HEAD 仍 `e46538f`，`pubspec` 仍 `1.8.26+120`，未触碰 `main`/Tag/Release。
- 下一步待办：用轻量复审提示词复核 `ba707c5..HEAD`，通过后等维护者发版指令。

## 2026-11-24 · 工作流规则：改动落盘与 Gate 增量复审

- 已完成改动：新增本状态文件；`AGENTS.md` 与 `VALIDATION.md` 写入「每项改动提交前更新状态与相关文档」及「Gate 返工复审按增量执行」规则。
- 当前 commit 与状态：功能返工 `dd29cbc` → `38ca50b` → `0773ba3` → `e46538f` 已推送 `origin/dev`；本提交为工作流规则，`pubspec` 仍 `1.8.26+120`，未触碰 `main`/Tag/Release。
- 下一步待办：按增量复审 `ba707c5..e46538f` 复核 4 个返工 commit；通过后等维护者发版指令进入 Stage 2。

## 2026-11-24 · v1.9.0 Stage 1 Gate 返工

- 已完成改动：修复时间信任 `displayAt` 与 Tier 1、`reorderPinned` 筛选子集；首页抽离 `home_manual_actions.dart` / `home_manual_sections.dart`（`assignment_list_screen.dart` 净减 22 行）；`assignment_store.dart` 净增 40 行；手动卡片、编辑器删除守卫、空态与工具栏修复；`androidTest` 全限定类名、`cwd`、崩溃判错；`freeze_release.py` dev/formal 双模式与 CRLF、`check_release_metadata.py` 拒绝 `-dev.N`/前导零/`Y>99`。
- 当前 commit 与状态：`e46538f` 已推送 `origin/dev`；本地门禁 88 项 Flutter 测试 + 9 组 Python 单测全绿；`pubspec` 仍 `1.8.26+120`，未触碰 `main`/Tag/Release。
- 下一步待办：Gate 增量复审通过后，等维护者明确发版指令再进入 Stage 2。
