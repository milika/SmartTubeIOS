#!/usr/bin/env python3
"""Check Localizable.xcstrings coverage for every language the app declares.

Fails (exit 1) when a declared language is missing a user-visible key or when a
translation drops/reorders printf placeholders. Run from anywhere; used by
`just localization-check` (part of `just ci`).
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "SmartTubeIOS/Sources/SmartTubeIOSCore/Localizable.xcstrings"

# Must stay in sync with CFBundleLocalizations in the app Info.plist files.
# "en" is the source language: its values are the keys themselves.
REQUIRED_LOCALES = [
    "ar", "de", "es", "fr", "hi", "hr", "id", "it",
    "ja", "ko", "pt-BR", "ru", "sr", "tr", "zh-Hans",
]

# Matches the placeholders protected by translate_strings.py.
FORMAT_SPEC_RE = re.compile(r"%(?:\d+\$)?(?:\.\d+)?(?:lld|[diouxXeEfgGs@%])")


def needs_translation(key: str) -> bool:
    """False for the empty key and pure format-specifier keys (e.g. "%lld")."""
    return bool(re.search(r"[A-Za-z\u4e00-\u9fff]", FORMAT_SPEC_RE.sub("", key)))


def specs(text: str) -> list[str]:
    """Placeholder types, ignoring positional indexes so reordering is allowed."""
    found = FORMAT_SPEC_RE.findall(text)
    return sorted(re.sub(r"%(\d+)\$", "%", spec) for spec in found)


def main() -> int:
    data = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings: dict = data["strings"]
    keys = [k for k in strings if needs_translation(k)]

    failures: list[str] = []
    for locale in REQUIRED_LOCALES:
        missing = []
        mangled = []
        for key in keys:
            value = (
                strings[key].get("localizations", {}).get(locale, {})
                .get("stringUnit", {})
                .get("value", "")
            )
            if not value:
                missing.append(key)
                continue
            if specs(key) != specs(value):
                mangled.append((key, value))
        status = "ok" if not missing and not mangled else "FAIL"
        print(f"{locale:8} {len(keys) - len(missing):3}/{len(keys)}  {status}")
        if missing:
            failures.append(f"{locale}: {len(missing)} missing key(s), e.g. {missing[:5]}")
        if mangled:
            failures.append(f"{locale}: {len(mangled)} mangled placeholder(s), e.g. {mangled[:3]}")

    if failures:
        print()
        for failure in failures:
            print(f"error: {failure}", file=sys.stderr)
        return 1
    print(f"\nAll {len(REQUIRED_LOCALES)} languages cover all {len(keys)} translatable keys.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
