# Release Runbook

Read only the phases required by the current release stage. Re-open current
repository files and scripts before copying a command or version.

## 1. Establish the release baseline

- Read root `AGENTS.md`, `docs/ai-workflow/PROJECT_STATE.md`,
  `docs/guides/开发与贡献.md`, the update guide, the current plan, and the last
  matching release review.
- Check `git branch --show-current`, `git rev-parse HEAD`,
  `git status --short --branch`, and `git diff --name-only`.
- Identify unrelated modified and untracked files. Keep them out of the release
  branch, staging area, and documentation unless the current task explicitly
  includes them.
- If the implementation is not yet isolated, create a release branch from the
  intended base. A direct-main workflow fix is acceptable only when the change
  is isolated and external publication cannot alter app bytes.
- Create the release ledger from `SKILL.md`. Update it at phase boundaries, not
  after every shell command.

## 2. Freeze the candidate

- Confirm the included fixes and tests before editing version metadata.
- Search source and remote state for the proposed version and build code:
  `pubspec.yaml`, `AppVersion`, docs, local Tags, GitHub Releases, Gitee
  Releases, and the latest public manifest.
- Update all of: Android version declaration, `AppVersion`, `CHANGELOG.md`,
  `README.md`, installation guide, and release notes.
- Run the metadata and changed-format checks. Record the frozen commit.
- Keep the recorded candidate source stable. A later change requires another
  input review: invalidate affected tests and the APK when build inputs change,
  not every unrelated result.

## 3. Verification matrix

Scale checks using the current repository `docs/ai-workflow/VALIDATION.md`
when present. For a formal release, cover the normal matrix on final integrated
inputs, using applicable original logs and required CI rather than duplicating
the full local matrix at each phase:

- Focused tests for every changed behavior and failure boundary.
- Release metadata, full changed-Dart format, and `dart analyze` /
  `flutter analyze --no-pub`.
- One full Flutter suite; benchmark flags follow current tests and acceptance
  requirements, not an old command snapshot.
- Shanghai and Los Angeles time-zone tests.
- Native checks, Gradle unit tests, instrumented-test compilation, and lint.
- PowerShell manifest tests, Python Gitee synchronizer tests, workflow contract
  tests, and `actionlint` when update distribution changed.
- CI on the final PR head, merged main, and Tag when a formal release exists.

Use `verified-delivery`'s `delivery.py` to reuse evidence only when its recorded
input fingerprint and environment still match. On Windows Chinese-path build
failures, use a clean ASCII export, verify every tracked input by hash, and do
not reuse old `build/` output.

## 4. Build and inspect the APK

- Export the frozen commit to a clean directory. Use the normal entry point,
  locked dependencies, SDK 36/build-tools 36, JDK 17, and the original signing
  material outside the repository.
- Build a two-ABI Release: `arm64-v8a` and `x86_64`.
- Inspect the actual APK, not build logs:
  package `com.example.studyassistant.journal`; canonical version/build code;
  minSdk 26; targetSdk 36; expected Flutter engine ABI; no debugger flag;
  Android Signature Scheme v2 with the established experience certificate;
  ZIP CRC; 16 KiB alignment; exact byte size and SHA-256.
- Name the artifact `chaoxing-journal-VERSION.apk`; generate
  `SHA256SUMS.txt`. Keep candidate and final-main artifacts separate.
- Use `scripts/artifact.py` or the project's current equivalent to avoid
  hand-rolled binary inspection.

## 5. MuMu acceptance

- Discover devices with `adb devices -l`; do not assume the previous serial.
- Select the existing `学习通` MuMu instance, not an unrelated emulator.
- Before install, record `dumpsys package` `versionCode`, `versionName`,
  `firstInstallTime`, and `lastUpdateTime`.
- Install with `adb install -r`; never uninstall or clear app data.
- Verify preserved `firstInstallTime`, login state, course/assignment data,
  MainActivity launch, changed behavior, and the relevant failure path.
- Pull or inspect the installed `base.apk` and compare its SHA-256 with the
  tested artifact.
- Capture only the screenshots needed to prove untestable or visual behavior.
- A connected physical-device acceptance may be stronger evidence, but its
  absence is a disclosed gap according to the current user authorization.

## 6. GitHub publication

- Push the exact release branch if required. Use the project's normal PR policy;
  wait for the latest PR-head checks and do not merge a superseded head.
- Immediately after the release PR is created or updated (whether CI is queued,
  running, or already finished), spawn one read-only `research` subagent
  (`invoke_subagent` with `TypeName: "research"`, no file writes and no
  Flutter/Gradle commands) in the background while continuing CI, merge, APK,
  and MuMu gates. Brief it to inspect `git log` / PR diff scope,
  `docs/ai-workflow/PROJECT_STATE.md`, `docs/ROADMAP.md`,
  `docs/待处理体验反馈.md`, and relevant modules, and return 3–6 evidence-backed
  items split into: (1) concrete existing issues, tech debt, workflow
  friction, or verification gaps (citing file paths, symbols, or feedback IDs),
  and (2) practical next-iteration recommendations ordered by value, scope,
  and prerequisites.
- After merge, verify main CI and that app inputs match the intended commit.
- Create an annotated Tag only after the final main identity is fixed. Do not
  move or overwrite a Tag.
- If any final-main build input changed, build the formal APK from final main.
  Reuse an intact verified candidate only after proving equality of all build
  inputs, including version, parameters, signing configuration, and any
  revision-derived metadata. Source-tree equality alone is insufficient.
  Bind identity/signature/ABI/hash and MuMu evidence to the exact final bytes;
  unchanged device/scenario evidence can be reused after checking current
  state, while changed state requires the affected scenarios again.
- Create a draft GitHub Release with APK, checksum, and release notes. Download
  the draft asset using authorized access and verify size, SHA-256, GitHub digest, ZIP, and
  signature before publication.
- Publish without overwriting older Releases. Verify `releases/latest` and the
  applicable update path and anonymous full asset download after publication.
  Verify the resulting Gitee small-index run; a failure must be disclosed and
  prevents claiming dual-channel completion, not the already-verified GitHub
  publication. Do not upload APK mirror bytes unless a batch is in scope.

## 7. Close the record

- Write one review with commit/Tag/CI IDs, toolchain, artifact hashes, MuMu
  first-install evidence, and the required GitHub URL. Report the Gitee index
  result and actual manual/stable versions separately from the APK mirror
  version; batch details apply only when selected. List unverified limits.
- Update `PROJECT_STATE.md` without overwriting parallel task notes.
- Commit release documentation separately only if the Tag must remain on the
  application commit. Record that the docs commit does not move the Tag.
- Fact-check the PR-stage `research` subagent's report against final published
  `main` and this release's actual outcome (discarding anything already
  resolved or unsupported by evidence), then present the
  "项目现存问题与下一轮迭代建议" section together with the final release report.

## Known time sinks

- Rediscovering paths or versions already stated in current docs: use the
  release ledger and query only live remote occupancy.
- Repeated full suites after isolated docs/workflow edits: reuse matching
  evidence or run the affected suite.
- Long-output `gh run watch` polling: use compact `gh run view --json` status
  checks at meaningful intervals.
- Pushing a fix, watching CI, then adding a one-line style/docs fix repeatedly:
  batch fixes and let superseded intermediate runs be canceled.
- Repeatedly downloading the same APK for metadata: use small API/HEAD checks
  for interim status. Keep the required draft and public full-byte download
  verification; HEAD is not a substitute, and CI does not verify downloads
  unless that exact remote artifact and digest are covered by its real job.
