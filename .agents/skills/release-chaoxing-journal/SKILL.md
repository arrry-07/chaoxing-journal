---
name: release-chaoxing-journal
description: "学习通课业手记（arrry-07/chaoxing-journal）专属版本冻结、原签名 APK 打包、MuMu 保数据覆盖验收、GitHub Release 发布与 Gitee 更新清单同步全流程门禁。触发场景：发版、打正式包/自测预览包、升级构建号、核验签名与 SHA-256、更新通道排查（release, version freeze, sign APK, MuMu acceptance, update manifest）。不用于：日常 dev 局部代码修改、纯文档润色或非本项目的发版。"
---

# Release Chaoxing Journal

## Core principle

Treat release as controlled evidence transfer. Bind every claim to the current
commit, APK hash, device, and remote object.

Use `verified-delivery` for general delivery evidence and the approved project plan for implementation scope. This skill adds project-specific gates and time controls.

## Start here

1. Check branch/status, then read `AGENTS.md`,
   `docs/ai-workflow/PROJECT_STATE.md`, `docs/ai-workflow/VALIDATION.md` when
   present, and the applicable release/update guide. Determine the requested
   endpoint before checking remote release state; docs-only work needs no
   version-occupancy query or app build.
2. Preserve unrelated changes; never stage the whole dirty worktree.
3. Continue one compact ledger per delivery scope: version/build code, base commit, included changes,
   evidence fingerprint, APK hash, device, GitHub objects, Gitee manifests, and
   unresolved limits.
4. Classify the stage as `implement`, `freeze/build`, `device acceptance`,
   `GitHub publish`, or `Gitee distribution`. Read only the matching part of
   [release-runbook.md](references/release-runbook.md), plus
   [gitee-distribution.md](references/gitee-distribution.md) for update work.

## Pace contract

- Batch related fixes. Judge each result by its actual source/dependency/test
  inputs, command, environment, target, and intact original log. A different
  commit ID alone does not invalidate content-based tests; Git-sensitive
  commands and current CI statuses remain bound to their actual revisions.
- Run focused tests while editing. Use the current commands and shell examples
  in `docs/ai-workflow/VALIDATION.md`. Run the required full gate for shared
  contracts and at the final PR/release integration point. After a local
  correction, rerun affected tests and device checks, then verify remaining
  evidence against its inputs. Bind release CI and artifacts to the actual
  source and version. Keep all required timezone and Android CI coverage.
- Target one PR-head cycle, one final-main cycle, and Tag checks. Cancel only
  superseded non-final runs. After pushing the immutable release Tag, overlap
  creating the Draft GitHub Release, uploading assets, and authenticated draft
  redownload verification with the running Tag CI, while keeping Tag CI
  `success` as a hard prerequisite before publishing (`--draft=false --latest`).
- Once the release PR is created or updated (whether PR CI has not started, is
  running, or has already completed) and a formal Release is in scope,
  immediately dispatch one read-only `research` subagent in the background (when
  available) to audit live Git commits/diff, `PROJECT_STATE.md`, `ROADMAP.md`,
  `docs/待处理体验反馈.md`, and touched code while main release gates proceed.
- For docs/workflow-only work, run affected checks and one final main CI; skip a
  local full Flutter run.
- Group release documentation into one final edit that does not move the Tag.
- Treat GitHub Release as mandatory for every formal package. Every published
  Release triggers the repository's two-step progressive Gitee sync: Step A
  updates the small index within seconds, and Step B runs `mode=latest --upload-missing`
  to automatically mirror the verified APK to Gitee Release and switch
  `update-manual.json` to Gitee primary + GitHub backup after anonymous full
  redownload verification. Disclose this coupled effect before publishing if the
  user restricts distribution to GitHub. An explicit exclusion of any Gitee write
  requires resolving that conflict before publication. Separate manual index writes
  or `--promote-stable` runs require authorization; report lag or upload fallback
  if cross-border upload stalls. Never upload or redownload every historical package.
- When infrastructure retries produce no new evidence, diagnose the current
  state before changing method or reporting a blocker. Retry counts are not
  permission to bypass a required gate; external-write timeouts require an
  object-state check before repeating the write.
- Use stage checkpoints rather than a fixed wall-clock deadline. Spend less by
  batching and evidence reuse, never by skipping a release gate.

## Hard gates

- Freeze a coherent source state after checking remote Tags/Releases and
  `versionCode`; Tags and APKs are immutable.
- Build from `lib/main.dart` with locked dependencies and the original package
  and signer. Verify identity, SDK, ABI, signature, ZIP, alignment, and SHA-256.
- Use the existing data-preserving MuMu `学习通` instance. Do not uninstall or
  clear it. Operate a physical device only when connected and authorized. For
  both MuMu emulator and physical devices, drive app launch, taps, swipes, text
  entry, and screenshots through T3 `device_list` -> `device_open` and its
  bound `agent-device` CLI (never hand-rolled `adb shell input`/`screencap`
  scripts; reserve `adb` for `install -r`, `pm path`, `dumpsys`, and `logcat`),
  and delegate `.png` visual audits to a read-only subagent returning text-only
  findings.
- A candidate is not final until bound to final main. Rebuild when any build
  input changed; promote an intact candidate only with recorded equality of
  all build inputs, including revision-derived metadata and private build
  configuration, not just the source tree. Bind GitHub, device, and APK
  evidence to that hash. Check the small Gitee index after every formal GitHub
  publication; an index failure must be disclosed and blocks claiming
  dual-channel completion, not the GitHub release. APK mirror evidence is
  required only for an explicitly selected batch.
- Missing, mismatched, or failed required evidence stops the corresponding
  publication step. Record optional gaps and current accepted limits without
  marking them passed; never update a manifest to hide a missing asset.
- Formal releases always bump `Y` (`<= 99`, rolling over to `X+1.0.0`) and automatically update `update-manual.json`; `update-stable.json` advances only when `--promote-stable` is explicitly enabled for major updates or urgent hotfixes, while `dev` MuMu test builds bump `Z` without `-dev.N`.

## Completion

Report the changed scope, version/build code, commit, CI runs, candidate/final
APK hashes, MuMu evidence, and the required GitHub URL. For every formal release
report the Gitee index result and actual manual/stable versions separately
from the APK mirror version. Include batch upload/retention details only when
selected. List every unverified item. Append a fact-checked "项目现存问题与下一轮迭代建议"
section synthesized from the PR-stage read-only subagent review (or evaluated
directly from live repo state after publication when subagents are unavailable).
