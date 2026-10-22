#!/usr/bin/env python3
"""Read release-notes/<version>.md and write its bullets into
Resources/WhatsNew.json.

Usage:
    python3 scripts/whats-new.py 0.1.0

The file must exist and contain at least one bullet (lines starting with
"- "). An optional title line before the first bullet is ignored.

The result is merged into Resources/WhatsNew.json under the version key.
"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RELEASE_NOTES = REPO / "release-notes"
WHATS_NEW = REPO / "Resources" / "WhatsNew.json"


def extract_bullets(text: str) -> list[str]:
    bullets = []
    for line in text.strip().splitlines():
        line = line.strip()
        if line.startswith("- "):
            content = line[2:].strip()
            if content:
                bullets.append(content)
    return bullets


def main():
    if len(sys.argv) < 2:
        print("Usage: whats-new.py <version>", file=sys.stderr)
        sys.exit(1)

    version = sys.argv[1]
    notes_file = RELEASE_NOTES / f"{version}.md"

    if not notes_file.exists():
        print(f"release-notes/{version}.md not found", file=sys.stderr)
        sys.exit(1)

    text = notes_file.read_text()
    if not text.strip():
        print(f"release-notes/{version}.md is empty", file=sys.stderr)
        sys.exit(1)

    bullets = extract_bullets(text)
    if not bullets:
        print(f"No bullets found in release-notes/{version}.md", file=sys.stderr)
        sys.exit(1)

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
