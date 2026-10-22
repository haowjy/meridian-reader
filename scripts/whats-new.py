#!/usr/bin/env python3
"""Extract the What's New bullets from CHANGELOG.md for a given version and
write them into Resources/WhatsNew.json.

Usage:
    python3 scripts/whats-new.py 1.2.0

The script looks for a `## [1.2.0]` section in CHANGELOG.md. Inside that
section it prefers the `### What's New` subsection (user-facing wording).
If there is no such subsection it falls back to the top-level bullets with
C-number prefixes stripped (e.g. "- C151: foo" → "foo").

The result is merged into Resources/WhatsNew.json under the version key.
"""
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CHANGELOG = REPO / "CHANGELOG.md"
WHATS_NEW = REPO / "Resources" / "WhatsNew.json"


def extract_section(text: str, version: str) -> str | None:
    """Return the body of `## [version]` or `## Unreleased` (for pre-release)."""
    escaped = re.escape(version)
    # Match either ## [X.Y.Z] or ## Unreleased
    pattern = rf"^## \[{escaped}\].*$"
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        # For the workflow: also try Unreleased when building the first release
        if version:
            return None
        pattern = r"^## Unreleased\s*$"
        match = re.search(pattern, text, re.MULTILINE)
        if not match:
            return None

    start = match.end()
    # Find the next ## heading
    next_heading = re.search(r"^## ", text[start:], re.MULTILINE)
    if next_heading:
        return text[start:start + next_heading.start()]
    return text[start:]


def extract_whats_new(section: str) -> list[str]:
    """From a version section, get the What's New bullets."""
    # Prefer ### What's New subsection
    wn_match = re.search(r"^### What's New\s*$", section, re.MULTILINE)
    if wn_match:
        subsection_start = wn_match.end()
        # Until next ### or end
        next_sub = re.search(r"^###? ", section[subsection_start:], re.MULTILINE)
        if next_sub:
            subsection = section[subsection_start:subsection_start + next_sub.start()]
        else:
            subsection = section[subsection_start:]
        return _parse_bullets(subsection)

    # Fallback: top-level bullets with C-numbers stripped
    return _parse_bullets(section, strip_c_numbers=True)


def _parse_bullets(text: str, strip_c_numbers: bool = False) -> list[str]:
    bullets = []
    for line in text.strip().splitlines():
        line = line.strip()
        if line.startswith("- "):
            content = line[2:].strip()
            if strip_c_numbers:
                content = re.sub(r"^C\d+[a-z]?:\s*", "", content)
            if content:
                bullets.append(content)
    return bullets


def main():
    if len(sys.argv) < 2:
        print("Usage: whats-new.py <version>", file=sys.stderr)
        sys.exit(1)

    version = sys.argv[1]
    text = CHANGELOG.read_text()

    section = extract_section(text, version)
    if not section:
        print(f"No section found for version {version} in CHANGELOG.md", file=sys.stderr)
        sys.exit(1)

    bullets = extract_whats_new(section)
    if not bullets:
        print(f"No What's New bullets found for version {version}", file=sys.stderr)
        sys.exit(1)

    # Read existing WhatsNew.json or create it
    if WHATS_NEW.exists():
        data = json.loads(WHATS_NEW.read_text())
    else:
        data = {"versions": {}}

    data["versions"][version] = bullets
    WHATS_NEW.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(bullets)} bullet(s) for {version} to {WHATS_NEW}")
    for b in bullets:
        print(f"  • {b}")


if __name__ == "__main__":
    main()
