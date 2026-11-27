---
name: chaoxing-release-fast-path
description: "学习通课业手记跨轮次、跨 Git 节点（PR → main → Tag）或交接续接验收/发版时的证据复用判定器（配合 release-chaoxing-journal 与 verified-delivery 使用）。触发场景：续接发版、判断旧测试/APK 构建/MuMu 验收日志能否复用、避免重复跑全量测试（reuse evidence, fast-path release, continue acceptance）。不用于：单独启动发版、开发中途编码、只读审查、普通咨询或仅写交接文档。"
---

# Chaoxing Release Fast Path

Companion skill for one job: decide which prior evidence is still valid so the
same change scope is not fully re-verified at every turn or Git node.

It never replaces or weakens `release-chaoxing-journal`, `verified-delivery`,
or the repository `AGENTS.md`. Those govern scope, cadence, and hard gates; on
any conflict or doubt, follow them and rerun the affected check. This skill
adds no permissions and removes no required check.

## When to use

- Continuing acceptance or release of the same change scope across turns,
  PR-head to main to Tag/Release nodes, or a handoff.
- Deciding whether an existing test, build, device, or remote result may be
  reused instead of rerun.

Do not activate mid-development, for read-only review or consultation, or for
writing a handoff document itself. Do not start a release flow from this skill
alone; load the governing skill first.

## Reuse decision

Use the repository's `docs/ai-workflow/VALIDATION.md` when present to select
the scope. Judge each result against the inputs that particular check reads,
with its intact original log available:

- tests/analysis: source and calling dependencies, tests/fixtures, resources,
  dependency locks, command, and relevant environment/toolchain;
- builds: complete build inputs, version, locked dependencies, signing,
  entrypoint, parameters, and the still-present output hash;
- device checks: exact APK hash, device/API, permissions/data state, scenario;
- remote checks: current revision/object/status, not a cached local success.

Record what was reused and why it remains valid.

- A new Git node alone is not a mismatch. Compare relevant bytes/dependencies;
  revision-sensitive commands must also match their Git range. Old CI cannot
  establish the required status of a new commit.
- Any mismatch: rerun only the affected checks, not the full historical matrix.
- Final integrated acceptance newly runs core checks per `AGENTS.md` once for
  that scope; later Git nodes check validity rather than re-enter acceptance.
  New integrated changes or missing evidence require affected checks again.
- Do not claim equivalence when dependency impact is unknown; widen checking
  conservatively. Do not alter cache keys to force a hit. If a conservative
  cache misses, either rerun or explicitly document a separately reviewed
  prior-log reuse; never describe that as a tool cache hit.
- Never treat a missing, failed, or skipped check as passed.

## Ledger and reporting

- Continue the existing delivery checklist or ledger for the same scope;
  initialize once per scope, not per message or per Git node.
- Keep the working ledger in conversation: version, commit/diff, commands, log
  paths, artifact hash, device/remote objects, open limits. Persist milestones
  to the existing `PROJECT_STATE.md` or release record; do not create extra
  ledger files or duplicate complete logs.
- Report reused evidence with its basis separately from newly run evidence,
  plus version/commit/artifact hash, device and remote objects, and every
  unverified or blocked item.
