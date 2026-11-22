#!/usr/bin/env python3
"""Unit tests for scripts/check_repo_safety.py."""

from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import check_repo_safety as mod  # noqa: E402


class CheckRepoSafetyTests(unittest.TestCase):
    def test_blocked_paths_are_rejected(self) -> None:
        blocked = [
            "dist/chaoxing-journal.apk",
            "dist/chaoxing-journal.apk.idsig",
            "build/app.aab",
            "keys/release.jks",
            "keys/upload.keystore",
            "study_assistant-1.1.0/local_app/android/key.properties",
            "study_assistant-1.1.0/local_app/android/local.properties",
            "config/cookies.json",
            "tmp/session.json",
            "tmp/session_cookies.json",
            "tmp/credentials.json",
            ".env",
            "sub/.env.local",
            "artifacts/release/app.txt",
            "ARTIFACTS/WindowsUpper/app.txt",
            "docs/feedback/raw.md",
            "Docs/Feedback/windows-case.md",
            "scripts/demo-video/clip.mp4",
            "docs/Gemini的迭代优化方案/note.md",
            "backup/FlutterSecureStorage.xml",
            "backup/FlutterSharedPreferences.xml",
        ]
        for path in blocked:
            self.assertTrue(mod.check_path(path), f"expected block for {path}")

        allowed = [
            "study_assistant-1.1.0/local_app/lib/main.dart",
            "docs/ai-workflow/PROJECT_STATE.md",
            "scripts/verify_local_gate.py",
        ]
        for path in allowed:
            self.assertEqual(mod.check_path(path), [])

    def test_oversized_blob_allows_only_font_allowlist(self) -> None:
        oversize = mod.MAX_BLOB_BYTES + 1
        self.assertTrue(mod.check_blob_size("assets/other.bin", oversize))
        self.assertEqual(
            mod.check_blob_size(
                "study_assistant-1.1.0/local_app/assets/type/LXGWWenKaiScreen.ttf",
                26 * 1024 * 1024,
            ),
            [],
        )
        self.assertEqual(mod.check_blob_size("assets/small.png", 1024), [])

    def test_secret_patterns_catch_high_confidence_secrets_without_false_positives(
        self,
    ) -> None:
        private_key = "-----BEGIN " + "PRIVATE KEY-----"
        keystore_pw = "store" + "Password=supersecret"
        gh_token = "gh" + "p_" + "A" * 24
        session_cookie = "Cookie: JSESSION" + "ID=" + "x" * 30
        vc3_cookie = "v" + "c3=" + "a%2Fb+c%3D" * 4

        for line in (private_key, keystore_pw, gh_token, session_cookie, vc3_cookie):
            self.assertTrue(
                mod.check_lines("lib/sample.dart", [(1, line)]),
                f"expected secret hit for {line[:12]}",
            )

        clean_lines = [
            (1, "antispider=cleared; route=mooc1"),
            (2, "storePassword keystoreProperties['storePassword']"),
            (3, "final token = 'enc=synthetic';"),
        ]
        self.assertEqual(mod.check_lines("test/fixture.dart", clean_lines), [])

    def test_git_staged_and_range_scans_catch_and_allow_appropriately(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
            subprocess.run(
                ["git", "config", "user.email", "test@example.com"],
                cwd=repo,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Test"],
                cwd=repo,
                check=True,
            )

            clean_file = repo / "README.md"
            clean_file.write_text("# Clean repo\n", encoding="utf-8")
            subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
            self.assertEqual(mod.scan_staged(repo), [])
            subprocess.run(
                ["git", "commit", "-m", "init"],
                cwd=repo,
                check=True,
                capture_output=True,
            )
            base = subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=repo, text=True
            ).strip()

            # Stage a blocked directory file and secret line.
            secret_file = repo / "docs" / "feedback" / "leak.txt"
            secret_file.parent.mkdir(parents=True, exist_ok=True)
            secret_file.write_text("gh" + "p_" + "B" * 24 + "\n", encoding="utf-8")
            subprocess.run(["git", "add", "-f", "docs/feedback/leak.txt"], cwd=repo, check=True)
            staged_hits = mod.scan_staged(repo)
            self.assertTrue(any("blocked-directory" in h for h in staged_hits))
            self.assertTrue(any("github-personal-access-token" in h for h in staged_hits))

            subprocess.run(
                ["git", "commit", "-m", "bad"],
                cwd=repo,
                check=True,
                capture_output=True,
            )
            range_hits = mod.scan_range(repo, f"{base}..HEAD")
            self.assertTrue(any("blocked-directory" in h for h in range_hits))
            self.assertTrue(any("github-personal-access-token" in h for h in range_hits))

    def test_merge_commit_and_unpushed_new_branch_are_scanned(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repo, check=True)

            (repo / "README.md").write_text("# Base\n", encoding="utf-8")
            subprocess.run(["git", "add", "README.md"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "init"], cwd=repo, check=True, capture_output=True)
            base = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()

            # Simulate remote ref at base so --not --remotes excludes base.
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", base], cwd=repo, check=True)

            # Create a side branch with an evil commit buried before a clean tip commit.
            subprocess.run(["git", "checkout", "-b", "feature"], cwd=repo, check=True, capture_output=True)
            (repo / "leak.txt").write_text("v" + "c3=" + "Z%2B/" * 10 + "\n", encoding="utf-8")
            subprocess.run(["git", "add", "leak.txt"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "buried secret"], cwd=repo, check=True, capture_output=True)
            (repo / "clean.txt").write_text("clean tip\n", encoding="utf-8")
            subprocess.run(["git", "add", "clean.txt"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "clean tip"], cwd=repo, check=True, capture_output=True)

            # scan_unpushed must catch the secret in HEAD~1 even though HEAD is clean.
            unpushed_hits = mod.scan_unpushed(repo, "HEAD")
            self.assertTrue(any("long-session-cookie" in h for h in unpushed_hits))

            # Switch back to main, add a clean commit, then merge --no-ff and inject a blocked file
            # during merge resolution (no commit on either branch had it before the merge commit).
            subprocess.run(["git", "checkout", "main"], cwd=repo, check=True, capture_output=True)
            (repo / "main.txt").write_text("main work\n", encoding="utf-8")
            subprocess.run(["git", "add", "main.txt"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "main commit"], cwd=repo, check=True, capture_output=True)
            before_merge = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()

            subprocess.run(
                ["git", "merge", "--no-ff", "--no-commit", "feature"],
                cwd=repo,
                check=True,
                capture_output=True,
            )
            (repo / "cookies.json").write_text('{"cookie": "x"}\n', encoding="utf-8")
            subprocess.run(["git", "add", "-f", "cookies.json"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "merge feature"], cwd=repo, check=True, capture_output=True)

            # Scanning ONLY the merge commit must detect both the merge-introduced blocked file
            # and the secret brought in via the merge!
            merge_hits = mod.scan_range(repo, f"{before_merge}..HEAD")
            self.assertTrue(any("blocked-file" in h and "cookies.json" in h for h in merge_hits))
            self.assertTrue(any("long-session-cookie" in h for h in merge_hits))


if __name__ == "__main__":
    unittest.main()
