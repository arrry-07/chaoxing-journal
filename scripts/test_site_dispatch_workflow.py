#!/usr/bin/env python3
"""Guard the site release-dispatch trigger, privilege, and secret contract."""

from __future__ import annotations

import contextlib
from io import StringIO
import json
import os
from pathlib import Path
import textwrap
import unittest
from unittest import mock


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

    # --- Behaviour of the inline dispatch script -------------------------

    def _inline_python(self) -> str:
        start = self.text.index("python3 - <<'PY'")
        body_start = self.text.index("\n", start) + 1
        end = self.text.index("\n          PY", body_start)
        return textwrap.dedent(self.text[body_start:end])

    def _run_inline(
        self,
        env: dict[str, str],
        urlopen: mock.Mock | None = None,
    ) -> tuple[int, str]:
        urlopen = urlopen or mock.Mock()
        stdout = StringIO()
        code = 0
        with (
            mock.patch.dict(os.environ, env, clear=True),
            mock.patch("urllib.request.urlopen", urlopen),
            contextlib.redirect_stdout(stdout),
        ):
            try:
                exec(
                    compile(self._inline_python(), "site-dispatch.py", "exec"),
                    {},
                )
            except SystemExit as error:
                code = error.code if isinstance(error.code, int) else 1
        return code, stdout.getvalue()

    def _ok_response(self) -> mock.Mock:
        response = mock.Mock()
        response.status = 204
        handle = mock.MagicMock()
        handle.__enter__.return_value = response
        return handle

    def test_inline_script_skips_without_token(self) -> None:
        urlopen = mock.Mock()
        code, output = self._run_inline(
            {"RELEASE_TAG": "v1.9.0", "RELEASE_DRAFT": "false"},
            urlopen,
        )
        self.assertEqual(0, code)
        self.assertIn("is not configured", output)
        urlopen.assert_not_called()

    def test_inline_script_skips_draft_and_prerelease(self) -> None:
        for env in (
            {"SITE_DISPATCH_TOKEN": "t", "RELEASE_TAG": "v1.9.0", "RELEASE_DRAFT": "true"},
            {
                "SITE_DISPATCH_TOKEN": "t",
                "RELEASE_TAG": "v1.9.0",
                "RELEASE_DRAFT": "false",
                "RELEASE_PRERELEASE": "true",
            },
        ):
            urlopen = mock.Mock()
            code, output = self._run_inline(env, urlopen)
            self.assertEqual(0, code)
            self.assertIn("Draft or prerelease", output)
            urlopen.assert_not_called()

    def test_inline_script_rejects_invalid_tag(self) -> None:
        for tag in ("v1.9.00", "v1.90.00", "1.9.0", "1.90.0", "v1.9.0-rc.1", ""):
            urlopen = mock.Mock()
            code, output = self._run_inline(
                {
                    "SITE_DISPATCH_TOKEN": "t",
                    "RELEASE_TAG": tag,
                    "RELEASE_DRAFT": "false",
                },
                urlopen,
            )
            self.assertEqual(1, code, tag)
            self.assertIn("Invalid formal release tag", output)
            urlopen.assert_not_called()

    def test_inline_script_posts_release_payload(self) -> None:
        urlopen = mock.MagicMock(return_value=self._ok_response())
        code, output = self._run_inline(
            {
                "SITE_DISPATCH_TOKEN": "secret-token",
                "RELEASE_TAG": "v1.90.0",
                "RELEASE_DRAFT": "false",
                "RELEASE_PRERELEASE": "false",
                "RELEASE_URL": "https://github.com/arrry-07/chaoxing-journal/releases/tag/v1.90.0",
            },
            urlopen,
        )
        self.assertEqual(0, code)
        self.assertIn("[PASS] Dispatched v1.90.0", output)
        self.assertNotIn("secret-token", output)
        request = urlopen.call_args.args[0]
        self.assertEqual(
            "https://api.github.com/repos/arrry-07/chaoxing-journal-site/dispatches",
            request.full_url,
        )
        self.assertEqual("POST", request.get_method())
        self.assertEqual(
            "Bearer secret-token", request.get_header("Authorization")
        )
        payload = json.loads(request.data.decode("utf-8"))
        self.assertEqual("chaoxing-release-published", payload["event_type"])
        self.assertEqual("v1.90.0", payload["client_payload"]["tag"])
        self.assertEqual(
            "arrry-07/chaoxing-journal",
            payload["client_payload"]["source_repo"],
        )

    def test_inline_script_fails_on_non_204(self) -> None:
        response = mock.Mock()
        response.status = 500
        handle = mock.MagicMock()
        handle.__enter__.return_value = response
        code, output = self._run_inline(
            {
                "SITE_DISPATCH_TOKEN": "t",
                "RELEASE_TAG": "v1.9.0",
                "RELEASE_DRAFT": "false",
            },
            mock.MagicMock(return_value=handle),
        )
        self.assertEqual(1, code)
        self.assertIn("HTTP 500", output)


if __name__ == "__main__":
    unittest.main()
