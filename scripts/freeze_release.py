#!/usr/bin/env python3
"""Validate or apply a no-leading-zero release identity without Git writes."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
import re
import sys

VERSION_RE = re.compile(
    r"^(?P<base>(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))"
    r"(?P<dev>-dev\.(?P<dev_number>[1-9]\d*))?\+"
    r"(?P<build>[1-9]\d*)$"
)


class FreezeError(RuntimeError):
    pass


@dataclass(frozen=True)
class ReleaseVersion:
    major: int
    minor: int
    patch: int
    dev: int | None
    build: int

    @property
    def base(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @property
    def name(self) -> str:
        return self.base if self.dev is None else f"{self.base}-dev.{self.dev}"

    @property
    def is_dev(self) -> bool:
        return self.dev is not None

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
            "Version must look like X.Y.Z+build or X.Y.Z-dev.N+build "
            "without leading zeros (for example 1.9.0+121, not 1.9.00+121)."
        )
    base = match.group("base").split(".")
    return ReleaseVersion(
        major=int(base[0]),
        minor=int(base[1]),
        patch=int(base[2]),
        dev=int(match.group("dev_number")) if match.group("dev_number") else None,
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


def _read_version_from_pubspec(text: str) -> str:
    match = re.search(r"^version:\s*(\S+)\s*$", text, re.M)
    if match is None:
        raise FreezeError("pubspec.yaml has no version line.")
    return match.group(1)


def _read_app_version(text: str) -> tuple[str, int]:
    name = re.search(r"static const name = '([^']+)';", text)
    code = re.search(r"static const code = (\d+);", text)
    if name is None or code is None:
        raise FreezeError("app_version.dart identity fields are missing.")
    return name.group(1), int(code.group(1))


def _validate_changelog(root: Path, version: ReleaseVersion) -> None:
    changelog = _paths(root)["changelog"].read_text(encoding="utf-8")
    if f"## {version.name}（{version.build}）" not in changelog:
        raise FreezeError(
            f"CHANGELOG.md is missing '## {version.name}（{version.build}）'. "
            "Write the release notes before freezing."
        )


def _validate_formal_docs(root: Path, version: ReleaseVersion) -> None:
    paths = _paths(root)
    _validate_changelog(root, version)
    readme = paths["readme"].read_text(encoding="utf-8")
    install = paths["install"].read_text(encoding="utf-8")
    if f"{version.name}（{version.build}）" not in readme:
        raise FreezeError("README.md does not mention the frozen release identity.")
    if f"{version.name}+{version.build}" not in install:
        raise FreezeError("Install guide does not mention the frozen release identity.")


def check_release(root: Path, previous: str | None = None) -> tuple[ReleaseVersion, str | None]:
    paths = _paths(root)
    for key in ("pubspec", "app_version"):
        if not paths[key].is_file():
            raise FreezeError(f"Missing required file: {paths[key]}")
    current = parse_version(
        _read_version_from_pubspec(paths["pubspec"].read_text(encoding="utf-8"))
    )
    app_name, app_code = _read_app_version(
        paths["app_version"].read_text(encoding="utf-8")
    )
    if app_name != current.name or app_code != current.build:
        raise FreezeError(
            f"AppVersion mismatch: expected {current.name}+{current.build}, "
            f"got {app_name}+{app_code}."
        )
    level: str | None = None
    if previous:
        previous_version = parse_version(previous)
        _validate_monotonic(previous_version, current)
        level = classify_update(previous_version, current)
    if not current.is_dev:
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
    previous: str | None = None,
) -> tuple[ReleaseVersion, str | None]:
    paths = _paths(root)
    for key in ("pubspec", "app_version"):
        if not paths[key].is_file():
            raise FreezeError(f"Missing required file: {paths[key]}")
    current_text = paths["pubspec"].read_text(encoding="utf-8")
    current = parse_version(_read_version_from_pubspec(current_text))
    new = parse_version(new_raw)
    level: str | None = None
    if previous:
        previous_version = parse_version(previous)
        _validate_monotonic(previous_version, new)
        level = classify_update(previous_version, new)

    app_version_text = paths["app_version"].read_text(encoding="utf-8")
    if not new.is_dev:
        _validate_changelog(root, new)

    readme_text = paths["readme"].read_text(encoding="utf-8") if not new.is_dev else ""
    install_text = (
        paths["install"].read_text(encoding="utf-8") if not new.is_dev else ""
    )
    if not new.is_dev:
        readme_text, readme_count = _replace_release_links(readme_text, current, new)
        install_text, install_count = _replace_release_links(
            install_text,
            current,
            new,
        )
        if readme_count == 0:
            raise FreezeError("README.md has no current release link/title to update.")
        if install_count == 0:
            raise FreezeError(
                "docs/guides/安装与使用.md has no current release link/title to update."
            )
        if f"{new.name}+{new.build}" not in readme_text:
            raise FreezeError("README.md update did not contain the new release identity.")
        if f"{new.name}+{new.build}" not in install_text:
            raise FreezeError("Install guide update did not contain the new release identity.")

    updated_pubspec, count = re.subn(
        r"^version:\s*\S+\s*$",
        f"version: {new.raw}",
        current_text,
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

    paths["pubspec"].write_text(updated_pubspec, encoding="utf-8", newline="\n")
    paths["app_version"].write_text(
        updated_app_version,
        encoding="utf-8",
        newline="\n",
    )
    if not new.is_dev:
        paths["readme"].write_text(readme_text, encoding="utf-8", newline="\n")
        paths["install"].write_text(install_text, encoding="utf-8", newline="\n")
    return new, level


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--apply", action="store_true")
    parser.add_argument("--version")
    parser.add_argument("--previous")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args(argv)
    try:
        if args.check:
            current, level = check_release(args.root, args.previous)
            print(f"[PASS] Current release metadata: {current.raw}")
            if level:
                print(
                    f"Update level: {level} "
                    f"({'patch: Gitee manual only' if level == 'patch' else 'minor/major: sync Gitee stable + manual'})"
                )
            return 0
        if not args.version:
            print("[FAIL] --apply requires --version.", file=sys.stderr)
            return 2
        current, level = apply_release(args.root, args.version, args.previous)
        print(f"[PASS] Applied release metadata: {current.raw}")
        if level:
            print(f"Update level: {level}")
        print("No git commit, tag, push or remote write was performed.")
        return 0
    except FreezeError as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
