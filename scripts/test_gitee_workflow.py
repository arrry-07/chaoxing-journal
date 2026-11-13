#!/usr/bin/env python3
"""Guard the Gitee workflow trigger, privilege, and secret contract."""

from __future__ import annotations

from pathlib import Path
import unittest


WORKFLOW = Path(__file__).resolve().parents[1] / ".github/workflows/gitee-release-sync.yml"


class GiteeWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = WORKFLOW.read_text(encoding="utf-8")

    def test_daily_schedule_and_manual_dispatch_only(self) -> None:
        self.assertIn("schedule:", self.text)
        self.assertIn('cron: "17 19 * * *"', self.text)
        self.assertIn("workflow_dispatch:", self.text)
        self.assertNotIn("release:", self.text)

    def test_dispatch_only_uploads_latest_or_explicit_seed(self) -> None:
        self.assertIn("mode:", self.text)
        self.assertIn("default: daily", self.text)
        self.assertIn("tags:", self.text)
        self.assertIn("retention:", self.text)
        self.assertIn("default: \"3\"", self.text)

    def test_token_is_read_only_from_secret_environment(self) -> None:
        self.assertIn("GITEE_TOKEN: ${{ secrets.GITEE_TOKEN }}", self.text)
        self.assertNotIn("--token", self.text)
        self.assertNotIn("access_token=", self.text)

    def test_workflow_runs_offline_tests_before_network_writes(self) -> None:
        test_position = self.text.index(
            "python3 scripts/test_gitee_release_sync.py"
        )
        write_position = self.text.index(
            "python3 scripts/gitee_release_sync.py"
        )
        self.assertLess(test_position, write_position)

    def test_workflow_has_minimal_permissions(self) -> None:
        self.assertIn("permissions:\n  contents: read", self.text)
        self.assertNotIn("contents: write", self.text)


if __name__ == "__main__":
    unittest.main()
