#!/usr/bin/env python3
"""Guard the site release-dispatch trigger, privilege, and secret contract."""

from __future__ import annotations

from pathlib import Path
import unittest


WORKFLOW = (
    Path(__file__).resolve().parents[1]
    / ".github"
    / "workflows"
    / "site-release-dispatch.yml"
)


class SiteDispatchWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = WORKFLOW.read_text(encoding="utf-8")

    def test_only_published_release_or_manual_dispatch(self) -> None:
        self.assertNotIn("schedule:", self.text)
        self.assertNotIn("cron:", self.text)
        self.assertIn("release:\n    types: [published]", self.text)
        self.assertIn("workflow_dispatch:", self.text)
        self.assertIn("required: true", self.text)
        self.assertIn("type: string", self.text)

    def test_workflow_has_minimal_permissions(self) -> None:
        self.assertIn("permissions:\n  contents: read", self.text)
        self.assertNotIn("contents: write", self.text)

    def test_tag_input_is_not_directly_interpolated_into_shell(self) -> None:
        self.assertNotIn("${{ inputs.tag }}", self.text)
        self.assertIn("RELEASE_TAG:", self.text)
        self.assertIn("|| inputs.tag }}", self.text)
        self.assertIn("tag = os.environ.get(\"RELEASE_TAG\", \"\")", self.text)

    def test_token_is_read_from_secret_environment_only(self) -> None:
        self.assertIn(
            "SITE_DISPATCH_TOKEN: ${{ secrets.SITE_DISPATCH_TOKEN }}",
            self.text,
        )
        self.assertIn(
            'token = os.environ.get("SITE_DISPATCH_TOKEN", "")',
            self.text,
        )
        self.assertNotIn("print(token", self.text)
        self.assertNotIn("--token", self.text)

    def test_missing_token_skips_successfully(self) -> None:
        skip_index = self.text.index('if not token:')
        exit_index = self.text.index("sys.exit(0)", skip_index)
        self.assertLess(skip_index, exit_index)
        self.assertIn("is not configured", self.text)

    def test_formal_tag_regex_and_dispatch_contract(self) -> None:
        self.assertIn(
            r're.fullmatch(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"',
            self.text,
        )
        self.assertIn(
            "https://api.github.com/repos/arrry-07/chaoxing-journal-site/dispatches",
            self.text,
        )
        self.assertIn('"event_type": "chaoxing-release-published"', self.text)
        self.assertIn('"source_repo": "arrry-07/chaoxing-journal"', self.text)
        self.assertIn("response.status != 204", self.text)
        self.assertIn("Authorization", self.text)


if __name__ == "__main__":
    unittest.main()
