#!/usr/bin/env python3
"""Check publication inputs without reading the computer or attached devices.

This is a review aid, not a proof that arbitrary text has no personal data.
Run from any directory; only this repository is inspected. Diagnostic files
and concrete device IDs are not valid publication inputs. Tests must use
obviously synthetic repeated-character identifiers.
"""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIRS = {".git", ".build", ".swiftpm", "dist", "__pycache__"}
ALLOWED_TOP = {
    ".github", "scripts", "Sources", "Tests", "docs", "Package.swift",
    "Package.resolved", "README.md", "README.zh-TW.md", "PRIVACY.md",
    "SECURITY.md", "LICENSE", ".gitignore",
}
FORBIDDEN_SUFFIXES = {
    ".log", ".logarchive", ".jsonl", ".ips", ".p12", ".pem", ".key",
    ".mobileprovision", ".sqlite", ".sqlite3", ".db", ".ipa", ".dmg",
}
PATTERNS = {
    "device identifier": re.compile(r"(?<![A-Za-z0-9])[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}(?![A-Za-z0-9])"),
    "UUID": re.compile(r"(?<![A-Za-z0-9])[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}(?![A-Za-z0-9])"),
    "home-directory path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+"),
    "private key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE" + r" KEY-----"),
    "GitHub credential": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})"),
    "AWS access key": re.compile(r"AKIA[0-9A-Z]{16}"),
}


def synthetic(value: str) -> bool:
    if value in {"/Users/EXAMPLE", "/home/EXAMPLE", "/Users/example", "/home/example"}:
        return True
    characters = value.replace("-", "").lower()
    return bool(characters) and len(set(characters)) == 1 and characters[0] in "01abcdef"


def inspect(root: Path = ROOT) -> list[str]:
    findings: list[str] = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in SKIP_DIRS for part in relative.parts):
            continue
        if path.is_symlink():
            findings.append(f"{relative}: symlinks are not publication inputs")
            continue
        if relative.parts[0] not in ALLOWED_TOP:
            findings.append(f"{relative}: unexpected publication input")
            continue
        if path.name.startswith(".env") or path.suffix.lower() in FORBIDDEN_SUFFIXES:
            findings.append(f"{relative}: diagnostic, credential, or binary file is not allowed")
            continue
        if path.is_dir():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeError, OSError):
            findings.append(f"{relative}: cannot audit as UTF-8 text")
            continue
        for kind, pattern in PATTERNS.items():
            for match in pattern.finditer(text):
                if not synthetic(match.group()):
                    line = text.count("\n", 0, match.start()) + 1
                    # Do not echo the potentially sensitive matching value.
                    findings.append(f"{relative}:{line}: possible {kind}; review before publication")
    return findings


if __name__ == "__main__":
    issues = inspect()
    if issues:
        print("Publication privacy audit failed:", file=sys.stderr)
        print("\n".join(issues), file=sys.stderr)
        raise SystemExit(1)
    print("Publication privacy audit passed (manual review is still required).")
