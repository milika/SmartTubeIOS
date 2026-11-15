#!/usr/bin/env python3
"""Automate localization for Localizable.xcstrings.

Fills missing translations for every non-source language using Google's public
translate endpoint (no API key, no third-party package). Chinese (zh-Hans) is
reviewed by hand and should NOT be machine translated; use --fix-lang only when
you really mean to overwrite it.

Usage:
    python3 translate_strings.py [--dry-run] [--fix-lang <code>] [--langs a,b]

Additive by default: existing language/key pairs are left untouched. Format
specifiers (%@, %lld, %.2g, ...) are protected during translation. Requests are
paced (~4/s) because Google rejects bursts.
"""

import json
import re
import sys
import threading
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

XCSTRINGS_PATH = (
    Path(__file__).resolve().parent.parent
    / "SmartTubeIOSCore"
    / "Localizable.xcstrings"
)

# xcstrings lang code → Google translate code
LANG_MAP = {
    "ar": "ar",
    "de": "de",
    "es": "es",
    "fr": "fr",
    "hi": "hi",
    "id": "id",
    "it": "it",
    "ja": "ja",
    "ko": "ko",
    "pt-BR": "pt",
    "ru": "ru",
    "tr": "tr",
    "zh-Hans": "zh-CN",
    "sr": "sr",
    "hr": "hr",
}

# These keys carry no meaningful text to translate
SKIP_KEYS = {"", "%lld", "%lld s"}

FORMAT_SPEC_RE = re.compile(r"%(?:\d+\$)?(?:\.\d+)?(?:lld|[diouxXeEfgGs@%])")

# Symbol-bracket tokens survive every script (they are not letters).
_OPEN = "\u27ea"   # ⟪
_CLOSE = "\u27eb"  # ⟫

_ENDPOINT = "https://translate.googleapis.com/translate_a/single"


def protect_format_specs(text: str) -> tuple[str, list[str]]:
    placeholders: list[str] = []

    def replacer(m: re.Match) -> str:
        idx = len(placeholders)
        placeholders.append(m.group(0))
        return f"{_OPEN}{idx}{_CLOSE}"

    return FORMAT_SPEC_RE.sub(replacer, text), placeholders


def restore_format_specs(text: str, placeholders: list[str]) -> str:
    for idx, spec in enumerate(placeholders):
        text = text.replace(f"{_OPEN}{idx}{_CLOSE}", spec)
    return text


class RateLimiter:
    """One request per `interval` seconds across all threads."""

    def __init__(self, interval: float = 0.22) -> None:
        self._interval = interval
        self._lock = threading.Lock()
        self._next = 0.0

    def wait(self) -> None:
        with self._lock:
            now = time.monotonic()
            if now < self._next:
                time.sleep(self._next - now)
                now = time.monotonic()
            self._next = now + self._interval


_LIMITER = RateLimiter()


def fetch_translation(text: str, target_lang: str) -> str:
    """Translate one string, retrying with backoff. Returns "" on failure."""
    query = urllib.parse.urlencode(
        {"client": "gtx", "sl": "en", "tl": target_lang, "dt": "t", "q": text}
    )
    url = f"{_ENDPOINT}?{query}"
    delay = 1.0
    for attempt in range(5):
        _LIMITER.wait()
        try:
            with urllib.request.urlopen(url, timeout=20) as response:
                payload = json.loads(response.read().decode("utf-8"))
            segments = payload[0]
            result = "".join(seg[0] for seg in segments if seg and seg[0])
            if result.strip():
                return result
        except Exception:
            pass
        time.sleep(delay)
        delay *= 2
    return ""


def translate(text: str, target_lang: str) -> str:
    if not text.strip():
        return text
    protected, placeholders = protect_format_specs(text)
    if not FORMAT_SPEC_RE.sub("", protected).strip():
        return text
    result = fetch_translation(protected, target_lang)
    if not result:
        print(f"    WARNING: translation failed, keeping original: {text[:40]!r}", file=sys.stderr)
        return text
    return restore_format_specs(result, placeholders)


def main() -> int:
    dry_run = "--dry-run" in sys.argv
    fix_lang = None
    if "--fix-lang" in sys.argv:
        idx = sys.argv.index("--fix-lang")
        fix_lang = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
    only_langs = None
    if "--langs" in sys.argv:
        idx = sys.argv.index("--langs")
        only_langs = set(sys.argv[idx + 1].split(",")) if idx + 1 < len(sys.argv) else None

    data = json.loads(XCSTRINGS_PATH.read_text(encoding="utf-8"))
    strings: dict = data["strings"]

    jobs: list[tuple[str, str, str]] = []
    for key, entry in strings.items():
        if key in SKIP_KEYS:
            continue
        locs: dict = entry.setdefault("localizations", {})
        for xc_locale, google_lang in LANG_MAP.items():
            if only_langs and xc_locale not in only_langs:
                continue
            force = fix_lang == xc_locale
            if xc_locale in locs and not force:
                continue
            jobs.append((key, xc_locale, google_lang))

    print(f"{len(jobs)} translations to fill")
    if dry_run:
        for key, locale, _ in jobs[:20]:
            print(f"  [{locale}] {key[:60]!r}")
        print("(dry-run — file not written)")
        return 0

    results: dict[str, dict[str, str]] = {}
    lock = threading.Lock()
    done = 0

    def worker(job: tuple[str, str, str]) -> None:
        nonlocal done
        key, locale, google_lang = job
        value = translate(key, google_lang)
        with lock:
            results.setdefault(locale, {})[key] = value
            done += 1
            if done % 100 == 0:
                print(f"  {done}/{len(jobs)} …", flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(worker, jobs))

    added = 0
    identical = 0
    for locale, mapping in results.items():
        for key, value in mapping.items():
            locs = strings[key].setdefault("localizations", {})
            if key in locs.get(locale, {}).get("stringUnit", {}).get("value", "") and fix_lang != locale:
                continue
            locs[locale] = {"stringUnit": {"state": "translated", "value": value}}
            added += 1
            if value == key:
                identical += 1

    XCSTRINGS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n",
        encoding="utf-8",
    )
    print(f"Done: {added} translations written, {identical} identical to English, {len(jobs) - done} skipped.")
    print(f"Written: {XCSTRINGS_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
