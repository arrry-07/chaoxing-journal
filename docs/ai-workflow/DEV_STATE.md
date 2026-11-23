# dev 本地状态

> 每项独立改动提交前更新本文件；只保留最近 5 条，更早记录随发布收口归档。
> 每条固定三段：已完成改动 / 当前 commit 与状态 / 下一步待办。

## 2026-11-24 · 工作流规则：改动落盘与 Gate 增量复审

- 已完成改动：新增本状态文件；`AGENTS.md` 与 `VALIDATION.md` 写入「每项改动提交前更新状态与相关文档」及「Gate 返工复审按增量执行」规则。
- 当前 commit 与状态：功能返工 `dd29cbc` → `38ca50b` → `0773ba3` → `e46538f` 已推送 `origin/dev`；本提交为工作流规则，`pubspec` 仍 `1.8.26+120`，未触碰 `main`/Tag/Release。
- 下一步待办：按增量复审 `ba707c5..e46538f` 复核 4 个返工 commit；通过后等维护者发版指令进入 Stage 2。

## 2026-11-24 · v1.9.0 Stage 1 Gate 返工

- 已完成改动：修复时间信任 `displayAt` 与 Tier 1、`reorderPinned` 筛选子集；首页抽离 `home_manual_actions.dart` / `home_manual_sections.dart`（`assignment_list_screen.dart` 净减 22 行）；`assignment_store.dart` 净增 40 行；手动卡片、编辑器删除守卫、空态与工具栏修复；`androidTest` 全限定类名、`cwd`、崩溃判错；`freeze_release.py` dev/formal 双模式与 CRLF、`check_release_metadata.py` 拒绝 `-dev.N`/前导零/`Y>99`。
- 当前 commit 与状态：`e46538f` 已推送 `origin/dev`；本地门禁 88 项 Flutter 测试 + 9 组 Python 单测全绿；`pubspec` 仍 `1.8.26+120`，未触碰 `main`/Tag/Release。
- 下一步待办：Gate 增量复审通过后，等维护者明确发版指令再进入 Stage 2。
