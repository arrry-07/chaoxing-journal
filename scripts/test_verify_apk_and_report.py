"""Unit tests for scripts/verify_apk_and_report.py."""

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

SCRIPTS_DIR = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import verify_apk_and_report as mod  # noqa: E402


class VerifyApkAndReportTests(unittest.TestCase):
    def test_parse_badging_aapt2_and_aapt_formats(self) -> None:
        aapt2_out = (
            "package: name='com.example.studyassistant.journal' "
            "versionCode='85' versionName='1.8.18'\n"
            "minSdkVersion:'26'\n"
            "targetSdkVersion:'36'\n"
        )
        parsed = mod.parse_badging_output(aapt2_out)
        self.assertEqual(parsed["package_name"], "com.example.studyassistant.journal")
        self.assertEqual(parsed["version_code"], 85)
        self.assertEqual(parsed["version_name"], "1.8.18")
        self.assertEqual(parsed["min_sdk"], 26)
        self.assertEqual(parsed["target_sdk"], 36)
        self.assertFalse(parsed["debuggable"])

        aapt_debug_out = (
            "package: name='com.example.studyassistant.journal' "
            "versionCode='86' versionName='1.8.19'\n"
            "sdkVersion:'26'\n"
            "targetSdkVersion:'36'\n"
            "application-debuggable\n"
        )
        parsed_debug = mod.parse_badging_output(aapt_debug_out)
        self.assertEqual(parsed_debug["min_sdk"], 26)
        self.assertTrue(parsed_debug["debuggable"])

    def test_parse_apksigner_output(self) -> None:
        sample = (
            "Verifies\n"
            "Verified using v1 scheme (JAR signing): false\n"
            "Verified using v2 scheme (APK Signature Scheme v2): true\n"
            "Signer #1 certificate SHA-256 digest: "
            "D36A571510E046DD196D7384F849F82B4FCFF05CE3AFFB334765D5C752265D8A\n"
        )
        v2_ok, signer = mod.parse_apksigner_output(sample)
        self.assertTrue(v2_ok)
        self.assertEqual(signer, mod.DEFAULT_SIGNER_SHA256)

        v2_fail, signer_none = mod.parse_apksigner_output(
            "Verified using v2 scheme (APK Signature Scheme v2): false\n"
        )
        self.assertFalse(v2_fail)
        self.assertIsNone(signer_none)

    def test_parse_expected_version(self) -> None:
        self.assertEqual(mod.parse_expected_version("1.8.19+86"), ("1.8.19", 86))
        self.assertEqual(mod.parse_expected_version("1.8.19"), ("1.8.19", None))
        self.assertEqual(mod.parse_expected_version(None), (None, None))

    def test_inspect_zip_and_abis(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / "ok.apk"
            with zipfile.ZipFile(apk, "w") as zf:
                zf.writestr("AndroidManifest.xml", b"manifest")
                zf.writestr("lib/arm64-v8a/libflutter.so", b"arm64")
                zf.writestr("lib/x86_64/libflutter.so", b"x64")

            entries, crc_ok, abis, errors = mod.inspect_zip_and_abis(
                apk, ["arm64-v8a", "x86_64"]
            )
            self.assertEqual(entries, 3)
            self.assertTrue(crc_ok)
            self.assertEqual(abis, ["arm64-v8a", "x86_64"])
            self.assertEqual(errors, [])

            bad_apk = Path(tmp) / "bad.apk"
            with zipfile.ZipFile(bad_apk, "w") as zf:
                zf.writestr("lib/arm64-v8a/libflutter.so", b"arm64")
                zf.writestr("lib/armeabi-v7a/libfoo.so", b"v7a")

            _, _, _, bad_errors = mod.inspect_zip_and_abis(
                bad_apk, ["arm64-v8a", "x86_64"]
            )
            self.assertTrue(any("unexpected ABI" in e for e in bad_errors))
            self.assertTrue(any("missing Flutter engine in ABI x86_64" in e for e in bad_errors))

    def test_verify_sha256sums_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            sums = Path(tmp) / "SHA256SUMS.txt"
            sums.write_text("a" * 64 + "  chaoxing-journal-1.8.19.apk\n", encoding="utf-8")
            self.assertEqual(
                mod.verify_sha256sums_file(sums, "chaoxing-journal-1.8.19.apk", "a" * 64),
                [],
            )
            self.assertTrue(
                mod.verify_sha256sums_file(sums, "chaoxing-journal-1.8.19.apk", "b" * 64)
            )
            self.assertTrue(
                mod.verify_sha256sums_file(sums, "other.apk", "a" * 64)
            )

    def test_format_markdown_report(self) -> None:
        report = mod.VerificationReport(
            apk_path="C:/tmp/chaoxing-journal-1.8.19.apk",
            apk_name="chaoxing-journal-1.8.19.apk",
            size_bytes=60646402,
            sha256="a" * 64,
            zip_entries=472,
            zip_crc_ok=True,
            abis=["arm64-v8a", "x86_64"],
            abi_ok=True,
            package_name="com.example.studyassistant.journal",
            version_name="1.8.19",
            version_code=86,
            min_sdk=26,
            target_sdk=36,
            debuggable=False,
            zipalign_16k_ok=True,
            v2_signed=True,
            signer_sha256=mod.DEFAULT_SIGNER_SHA256,
            signer_match=True,
            sha256sums_ok=True,
            source_commit="abcdef1",
        )
        md = mod.format_markdown_report(report)
        self.assertIn("`chaoxing-journal-1.8.19.apk`", md)
        self.assertIn("`60,646,402` 字节", md)
        self.assertIn("ARM64/x86_64", md)
        self.assertIn("`d36a5715...`", md)
        self.assertIn("校验结论：全部通过。", md)


if __name__ == "__main__":
    unittest.main()
