# Gitee Distribution

Use this reference for update-channel changes, Gitee Release work, optional
batch synchronization, manifest failures, or client fallback behavior.

## Current contract

- Gitee repository: `arrry-07/chaoxing-journal-updates`.
- Client manifests:
  `https://raw.giteeusercontent.com/arrry-07/chaoxing-journal-updates/raw/master/update-stable.json`
  and `update-manual.json`.
- Publishing on GitHub triggers the small manual index update. Stable promotion requires the explicit workflow-dispatch option and authorization. Disclose this coupling before a GitHub-only release; resolve an explicit Gitee write exclusion before publishing. APK URLs point to GitHub until the Gitee batch mirror is verified.
- GitHub Release is mandatory for every formal package. Every published
  Release updates only the small Gitee index; APK bytes remain an optional
  batched mirror.
- The workflow allows `release: published` for `mode=index` and
  `workflow_dispatch` for index, latest, or seed. It must not subscribe to
  schedules, and a Release event must never upload APKs or prune attachments.
- Index mode reads Release metadata, `SHA256SUMS.txt`, and the Tag's pubspec
  version. It does not download/upload APK bytes or alter Gitee attachments.
- Actions verifies and publishes manifests; it does not upload APKs. At a
  chosen batch checkpoint, upload only the latest selected APK once through the
  Gitee web backend from the workstation.
- In batch mode, historical releases are checked for existence and matching
  attachment name. Do not redownload every historical APK. The latest manual
  APK gets one anonymous full download and SHA-256 verification before
  manifests change. Index mode does not inspect or redownload assets.
- Default retention is three APK Releases. Protect stable, manual, and the
  newest required mirror. Older versions remain available from GitHub.
- An unmirrored manifest uses the GitHub release as `apkUrl` and omits
  `backupApkUrl`. A verified Gitee mirror uses Gitee as primary and the
  same-version GitHub asset as backup. Both carry size, SHA-256, package, and
  version identity.

## Upload the latest APK

1. Build a GitHub APK candidate/final artifact and record its size, SHA-256,
   package, version, and signature.
2. Confirm the Gitee Release tag and filename:
   `chaoxing-journal-VERSION.apk`.
3. Before browser upload, ensure the Chrome automation extension has
   file-URL access. If not, ask the user to enable it rather than changing
   browser permissions silently.
4. Create/reuse the Gitee Release and upload only the newest APK. Confirm the
   attachment card shows the expected size and filename.
5. Wait for Gitee's upload state to clear, then submit the Release. Verify the
   public release page exposes the APK.
6. Do not repeat the upload when the attachment already exists unless its
   identity is proven wrong. Do not overwrite historical assets.
7. After the selected Gitee Release is public, confirm GitHub
   `releases/latest` points to the intended batch target. Trigger one
   `workflow_dispatch` with `mode=latest` and `retention=3`.
8. Seed remains a one-time repair operation. Stop and reconcile the release
   selection instead of hand-editing manifests when the target is missing.

## Trigger verification

For a seed or recovery run:

```powershell
gh workflow run gitee-release-sync.yml `
  --repo arrry-07/chaoxing-journal --ref main `
  -f mode=seed -f tags="vOLD1,vOLD2,vCURRENT" -f retention=3
```

Use compact polling:

```powershell
gh run view RUN_ID --repo arrry-07/chaoxing-journal `
  --json status,conclusion,jobs,url
```

Treat seed as a one-time/repair operation. Batch runs use `mode=latest`; do not
use seed to repeat large historical transfers during normal operation.

## Failure routing

- `setup-android` or `sdkmanager` failure: use the runner's preinstalled Android
  SDK path; pin `aapt`/`apksigner` build-tools instead of relying on `PATH` or
  newest version.
- Signature mismatch: verify the public APK hash locally with the pinned tool;
  check output stream and certificate parsing before declaring the APK wrong.
- Upload connection stalls: inspect whether upload is still required by current
  policy. Actions must not be the default APK uploader. If a local web upload
  fails, check browser file permission and release page state.
- Gitee batch download timeout: retry once after reading the run and remote
  asset state. Repeated failure requires a network/rate-limit diagnosis; never
  publish a manifest from partial bytes.
- Missing Gitee Release/attachment: stop before manifest generation and upload
  the exact final APK once.
- Release count above limit: re-list Releases by API; ensure protected stable and
  manual identities remain. Malformed or unknown APK Tags require explicit
  handling before claiming a three-package cap.
- Manifest/raw cache mismatch: wait for the script's bounded verification; do
  not commit a second speculative manifest. Report partial state if propagation
  ultimately fails.
- Git push/Gitee API failure: confirm remote state before retrying; do not expose
  the token in URLs, argv, files, or logs.

## Offline tests

Run when the synchronizer or workflow changes:

```powershell
python scripts/test_gitee_release_sync.py
python scripts/test_gitee_workflow.py
python -m py_compile scripts/gitee_release_sync.py
actionlint .github/workflows/gitee-release-sync.yml
```

Bind tests to observable invariants:

- historical assets produce no full download;
- only latest manual is fully downloaded;
- missing/wrong/multiple APK attachments stop publication;
- same-version note refresh uses a valid lower previous version;
- stable is not replaced by a patch;
- pruning protects stable/manual and does not exceed the cap;
- retries remain idempotent;
- no Token appears in commands or output.

## Final acceptance for a Gitee batch

- `stable` and `manual` public URLs return HTTP 200 with expected identities.
- Latest Gitee APK has the GitHub size and SHA-256.
- Historical attachments are present with exact names; do not claim their bytes
  were rehashed when policy intentionally skipped that download.
- Gitee APK Release count is within the approved limit.
- Both manifests contain Gitee primary and same-version GitHub backup URLs.
- MuMu from the installed previous client checks updates through the Gitee
  manifest and reaches the expected current-version result.
- Record the actual workflow run, release IDs/URLs, manifest values, and any
  remaining external-network limitation.
- For a GitHub-only patch, run/verify index automation but do not run the Gitee
  batch section; record that manual points to GitHub and no APK was uploaded.
