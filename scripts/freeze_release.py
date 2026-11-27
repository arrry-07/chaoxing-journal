#!/usr/bin/env python3
"""Validate or apply a no-leading-zero release identity without Git writes."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

VERSION_RE = re.compile(
    r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\."
    r"(?P<patch>0|[1-9]\d*)\+(?P<build>[1-9]\d*)$"
)
README_FORMAL_RE = re.compile(
    r"当前正式包为\s*(?P<name>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"
    r"（(?P<build>[1-9]\d*)）"
)
INSTALL_FORMAL_RE = re.compile(
    r"当前正式版本为\s*`?"
    r"(?P<name>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"
    r"\+(?P<build>[1-9]\d*)"
)


class FreezeError(RuntimeError):
    pass


@dataclass(frozen=True)
class ReleaseVersion:
    major: int
    minor: int
    patch: int
    build: int

    @property
    def base(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @property
    def name(self) -> str:
        return self.base

    @property
    def is_dev(self) -> bool:
        return self.patch > 0

    @property
    def base_tuple(self) -> tuple[int, int, int]:
        return (self.major, self.minor, self.patch)

    @property
    def raw(self) -> str:
        return f"{self.name}+{self.build}"


def parse_version(raw: str) -> ReleaseVersion:
    match = VERSION_RE.fullmatch(raw.strip())
    if match is None:
        raise FreezeError(
            "Version must look like X.Y.Z+build without leading zeros or a "
            "-dev.N suffix (for example 1.90.0+123, not 1.90.00+123)."
        )
    return ReleaseVersion(
        major=int(match.group("major")),
        minor=int(match.group("minor")),
        patch=int(match.group("patch")),
        build=int(match.group("build")),
    )


def classify_update(
    previous: ReleaseVersion,
    current: ReleaseVersion,
) -> str:
    if current.major > previous.major:
        return "major"
    if current.minor > previous.minor:
        return "minor"
    return "patch"


def _validate_monotonic(
    previous: ReleaseVersion,
    current: ReleaseVersion,
) -> None:
    if current.base_tuple < previous.base_tuple:
        raise FreezeError(
            f"Version regression: {current.raw} is lower than {previous.raw}."
        )
    if current.build <= previous.build:
        raise FreezeError(
            f"Build code must increase: {current.build} <= {previous.build}."
        )


def _expected_formal_base(previous: ReleaseVersion) -> tuple[int, int, int]:
    if previous.major == 1 and previous.minor == 8:
        return (1, 90, 0)
    if previous.minor >= 99:
        return (previous.major + 1, 0, 0)
    return (previous.major, previous.minor + 1, 0)


def _validate_formal_step(
    previous: ReleaseVersion,
    current: ReleaseVersion,
) -> None:
    expected = _expected_formal_base(previous)
    same_series_patch = (
        current.major == previous.major
        and current.minor == previous.minor
        and current.patch > previous.patch
    )
    if current.base_tuple != expected and not same_series_patch:
        wanted = ".".join(str(part) for part in expected)
        raise FreezeError(
            f"Formal release after {previous.name} must be {wanted} "
            f"(or a patch in {previous.major}.{previous.minor}.x); "
            f"got {current.name}."
        )


def _validate_mode(version: ReleaseVersion, mode: str) -> None:
    if version.minor > 99:
        raise FreezeError(
            f"Minor version Y must be <= 99: {version.name}."
        )
    if mode == "dev":
        if version.patch == 0:
            raise FreezeError(
                f"Dev test packages increment Z: {version.name} has Z == 0. "
                "Use --mode formal for a release freeze."
            )


def _app_root(root: Path) -> Path:
    return root / "study_assistant-1.1.0" / "local_app"


def _paths(root: Path) -> dict[str, Path]:
    app = _app_root(root)
    return {
        "pubspec": app / "pubspec.yaml",
        "app_version": app / "lib" / "src" / "app" / "app_version.dart",
        "changelog": root / "CHANGELOG.md",
        "readme": root / "README.md",
        "install": root / "docs" / "guides" / "安装与使用.md",
    }


def _read_text(path: Path) -> str:
    # newline="" preserves CRLF so rewrites never churn whole files.
    with path.open("r", encoding="utf-8", newline="") as handle:
        return handle.read()


def _write_text(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def _read_version_from_pubspec(text: str) -> str:
    match = re.search(r"^version:[ \t]*(\S+)[ \t]*\r?$", text, re.M)
    if match is None:
        raise FreezeError("pubspec.yaml has no version line.")
    return match.group(1)


def _release_mode(pubspec: str, version: ReleaseVersion, requested: str | None) -> str:
    marks = [mark.strip() for mark in re.findall(r"^# formal-release:([^\r\n]*)", pubspec, re.M)]
    if marks and marks != [version.raw]:
        raise FreezeError("Formal release marker does not match pubspec version.")
    if marks and requested == "dev":
        raise FreezeError("Marked formal candidate cannot be checked as a dev package.")
    return requested or ("formal" if marks or version.patch == 0 else "dev")


def _read_app_version(text: str) -> tuple[str, int]:
    name = re.search(r"static const name = '([^']+)';", text)
    code = re.search(r"static const code = (\d+);", text)
    if name is None or code is None:
        raise FreezeError("app_version.dart identity fields are missing.")
    return name.group(1), int(code.group(1))


def _validate_changelog(root: Path, version: ReleaseVersion) -> None:
    changelog = _read_text(_paths(root)["changelog"])
    if f"## {version.name}（{version.build}）" not in changelog:
        raise FreezeError(
            f"CHANGELOG.md is missing '## {version.name}（{version.build}）'. "
            "Write the release notes before freezing."
        )


def _validate_formal_docs(root: Path, version: ReleaseVersion) -> None:
    paths = _paths(root)
    _validate_changelog(root, version)
    readme = _read_text(paths["readme"])
    install = _read_text(paths["install"])
    if f"{version.name}（{version.build}）" not in readme:
        raise FreezeError("README.md does not mention the frozen release identity.")
    if f"{version.name}+{version.build}" not in install:
        raise FreezeError(
            "Install guide does not mention the frozen release identity."
        )


def _detect_previous_formal(root: Path) -> ReleaseVersion:
    paths = _paths(root)
    for path, pattern in (
        (paths["readme"], README_FORMAL_RE),
        (paths["install"], INSTALL_FORMAL_RE),
    ):
        if not path.is_file():
            continue
        match = pattern.search(_read_text(path))
        if match is not None:
            return parse_version(
                f"{match.group('name')}+{match.group('build')}"
            )
    raise FreezeError(
        "Cannot detect the previous formal release from README.md or "
        "docs/guides/安装与使用.md; pass --previous X.Y.Z+build."
    )


def _check_identity(paths: dict[str, Path], version: ReleaseVersion) -> None:
    app_name, app_code = _read_app_version(_read_text(paths["app_version"]))
    if app_name != version.name or app_code != version.build:
        raise FreezeError(
            f"AppVersion mismatch: expected {version.name}+{version.build}, "
            f"got {app_name}+{app_code}."
        )


def check_release(
    root: Path,
    mode: str | None = None,
    previous: str | None = None,
) -> tuple[ReleaseVersion, str | None]:
    paths = _paths(root)
    for key in ("pubspec", "app_version"):
        if not paths[key].is_file():
            raise FreezeError(f"Missing required file: {paths[key]}")
    pubspec = _read_text(paths["pubspec"])
    current = parse_version(_read_version_from_pubspec(pubspec))
    _check_identity(paths, current)
    effective_mode = _release_mode(pubspec, current, mode)
    _validate_mode(current, effective_mode)
    level: str | None = None
    if previous:
        previous_version = parse_version(previous)
        _validate_monotonic(previous_version, current)
        level = classify_update(previous_version, current)
        if effective_mode == "formal":
            _validate_formal_step(previous_version, current)
    if effective_mode == "formal":
        _validate_formal_docs(root, current)
    return current, level


def _replace_release_links(
    text: str,
    old: ReleaseVersion,
    new: ReleaseVersion,
) -> tuple[str, int]:
    if old.raw == new.raw:
        return text, 1
    replacements = [
        (
            f"下载 Android 安装包：{old.name}+{old.build}",
            f"下载 Android 安装包：{new.name}+{new.build}",
        ),
        (
            f"当前正式包为 {old.name}（{old.build}）",
            f"当前正式包为 {new.name}（{new.build}）",
        ),
        (
            f"当前正式版本为 `{old.name}+{old.build}`",
            f"当前正式版本为 `{new.name}+{new.build}`",
        ),
        (
            f"已经安装：如何升级到 {old.name}？",
            f"已经安装：如何升级到 {new.name}？",
        ),
        (
            f"**{old.name}+{old.build} 已正式发布。**",
            f"**{new.name}+{new.build} 已正式发布。**",
        ),
        (f"[{old.name} 发布页]", f"[{new.name} 发布页]"),
        (f"{old.name} 继续沿用", f"{new.name} 继续沿用"),
        (
            f"releases/download/v{old.name}/chaoxing-journal-{old.name}.apk",
            f"releases/download/v{new.name}/chaoxing-journal-{new.name}.apk",
        ),
        (
            f"releases/tag/v{old.name}",
            f"releases/tag/v{new.name}",
        ),
        (
            f"chaoxing-journal-{old.name}.apk",
            f"chaoxing-journal-{new.name}.apk",
        ),
    ]
    count = 0
    updated = text
    for before, after in replacements:
        if before in updated:
            count += updated.count(before)
            updated = updated.replace(before, after)
    return updated, count


def apply_release(
    root: Path,
    new_raw: str,
    mode: str,
    previous: str | None = None,
) -> tuple[ReleaseVersion, str | None]:
    paths = _paths(root)
    for key in ("pubspec", "app_version"):
        if not paths[key].is_file():
            raise FreezeError(f"Missing required file: {paths[key]}")
    current_text = _read_text(paths["pubspec"])
    current = parse_version(_read_version_from_pubspec(current_text))
    new = parse_version(new_raw)
    _validate_mode(new, mode)
    _validate_monotonic(current, new)

    level: str | None = None
    previous_version: ReleaseVersion | None = None
    readme_text = ""
    install_text = ""
    if mode == "formal":
        previous_version = (
            parse_version(previous)
            if previous
            else _detect_previous_formal(root)
        )
        _validate_monotonic(previous_version, new)
        _validate_formal_step(previous_version, new)
        level = classify_update(previous_version, new)
        _validate_changelog(root, new)
        readme_text = _read_text(paths["readme"])
        install_text = _read_text(paths["install"])
        readme_text, readme_count = _replace_release_links(
            readme_text, previous_version, new
        )
        install_text, install_count = _replace_release_links(
            install_text, previous_version, new
        )
        if readme_count == 0:
            raise FreezeError(
                f"README.md has no {previous_version.raw} release link/title "
                "to update."
            )
        if install_count == 0:
            raise FreezeError(
                "docs/guides/安装与使用.md has no "
                f"{previous_version.raw} release link/title to update."
            )
        if f"{new.name}+{new.build}" not in readme_text:
            raise FreezeError(
                "README.md update did not contain the new release identity."
            )
        if f"{new.name}+{new.build}" not in install_text:
            raise FreezeError(
                "Install guide update did not contain the new release identity."
            )
    elif previous:
        previous_version = parse_version(previous)
        _validate_monotonic(previous_version, new)
        level = classify_update(previous_version, new)

    app_version_text = _read_text(paths["app_version"])
    newline = "\r\n" if "\r\n" in current_text else "\n"
    unmarked_pubspec = re.sub(r"^# formal-release:[^\r\n]*(?:\r?\n|$)", "", current_text, flags=re.M)
    new_version_line = f"version: {new.raw}"
    if mode == "formal":
        new_version_line += f"{newline}# formal-release: {new.raw}"
    updated_pubspec, count = re.subn(
        r"^version:[^\r\n]*",
        new_version_line,
        unmarked_pubspec,
        count=1,
        flags=re.M,
    )
    if count != 1:
        raise FreezeError("Could not replace the pubspec version line.")
    updated_app_version = re.sub(
        r"static const name = '[^']+';",
        f"static const name = '{new.name}';",
        app_version_text,
        count=1,
    )
    updated_app_version = re.sub(
        r"static const code = \d+;",
        f"static const code = {new.build};",
        updated_app_version,
        count=1,
    )
    if f"static const name = '{new.name}';" not in updated_app_version:
        raise FreezeError("Could not update app_version.dart name.")

    _write_text(paths["pubspec"], updated_pubspec)
    _write_text(paths["app_version"], updated_app_version)
    if mode == "formal":
        _write_text(paths["readme"], readme_text)
        _write_text(paths["install"], install_text)
    return new, level


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--check", action="store_true")
    mode_group.add_argument("--apply", action="store_true")
    parser.add_argument("--mode", choices=("dev", "formal"))
    parser.add_argument("--version")
    parser.add_argument("--previous")
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1]
    )
    args = parser.parse_args(argv)
    try:
        if args.check:
            current, level = check_release(args.root, args.mode, args.previous)
            effective_mode = _release_mode(_read_text(_paths(args.root)["pubspec"]), current, args.mode)
            kind = "formal release" if effective_mode == "formal" else "dev test package"
            print(f"[PASS] Current {kind}: {current.raw}")
            if level:
                print(_level_line(level, current, effective_mode))
            return 0
        if not args.mode:
            print(
                "[FAIL] --apply requires --mode dev|formal.",
                file=sys.stderr,
            )
            return 2
        if not args.version:
            print("[FAIL] --apply requires --version.", file=sys.stderr)
            return 2
        current, level = apply_release(
            args.root, args.version, args.mode, args.previous
        )
        print(f"[PASS] Applied release metadata: {current.raw}")
        if level:
            print(_level_line(level, current, args.mode))
        print("No git commit, tag, push or remote write was performed.")
        return 0
    except FreezeError as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1


def _level_line(level: str, current: ReleaseVersion, mode: str | None = None) -> str:
    effective_mode = mode or ("dev" if current.is_dev else "formal")
    if effective_mode == "dev":
        return (
            "Update level: patch (dev test package; publish only "
            "pubspec.yaml + AppVersion, no Gitee manifests)"
        )
    if level == "patch":
        return (
            "Update level: patch (formal release; update-manual.json by "
            "default; update-stable.json only with --promote-stable for an "
            "urgent hotfix)"
        )
    return (
        f"Update level: {level} (formal release; update-manual.json by "
        "default; update-stable.json only with --promote-stable for a major "
        "update)"
    )


if __name__ == "__main__":
    raise SystemExit(main())
