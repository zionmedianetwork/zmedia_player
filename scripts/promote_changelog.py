#!/usr/bin/env python3
"""Close the CHANGELOG's [Unreleased] section as a released version.

The release workflow used to *prepend* an auto-generated list of commit subjects
under a new `## [X.Y.Z]` heading and leave the hand-written `## [Unreleased]`
section untouched. That gave the changelog two sources of truth for the same
release: the curated notes stayed under "Unreleased" forever while the version
entry held only terse commit subjects. The repo still carries the scars — a
commit titled "docs(changelog): retitle the stray Unreleased section to [0.2.0]",
and the manual CHANGELOG surgery visible in the v0.3.0 bump PR (#78).

This script promotes instead of prepending:

    ## [Unreleased]          ->    ## [Unreleased]
    <curated notes>                                    <- fresh and empty
                                   ## [0.4.0] - 2026-09-02
                                   <curated notes>     <- same notes, now released

If the [Unreleased] section is empty, the generated commit notes are used as the
body instead, so a release cut without curated notes still says something.

It also stops guessing where the preamble ends. The previous implementation
rebuilt the header and appended `tail -n +8 CHANGELOG.md`, hard-coding "the
header is exactly 7 lines" — one added line of preamble would have silently
eaten or duplicated content. Sections are located by their `## [` headings.
"""

from __future__ import annotations

import argparse
import datetime as _datetime
import re
import sys
from pathlib import Path

HEADING = re.compile(r"^## \[([^\]]+)\]")
UNRELEASED = "Unreleased"


def find_headings(lines: list[str]) -> list[tuple[int, str]]:
    """Every `## [Name]` heading as (line index, name)."""
    return [(i, m.group(1)) for i, line in enumerate(lines) if (m := HEADING.match(line))]


def section_bounds(lines: list[str], index: int) -> tuple[int, int]:
    """Half-open [start, end) line range of the section whose heading is at `index`."""
    for i in range(index + 1, len(lines)):
        if HEADING.match(lines[i]):
            return index, i
    return index, len(lines)


def promote(text: str, version: str, date: str, fallback: str) -> str:
    lines = text.splitlines()
    headings = find_headings(lines)

    if any(name == version for _, name in headings):
        raise SystemExit(
            f"already has a [{version}] section — refusing to add a second one."
        )

    unreleased = next((i for i, name in headings if name == UNRELEASED), None)

    if unreleased is None:
        # No [Unreleased] section at all: insert the new version above the most
        # recent existing release, or at the end of the preamble if there is none.
        insert_at = headings[0][0] if headings else len(lines)
        body = fallback.strip("\n").splitlines() or ["_No changes recorded._"]
        block = [f"## [{UNRELEASED}]", "", f"## [{version}] - {date}", "", *body, ""]
        lines[insert_at:insert_at] = block
        return "\n".join(lines) + "\n"

    start, end = section_bounds(lines, unreleased)
    body = lines[start + 1 : end]

    # Trim blank lines at both ends of the body.
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()

    if not body:
        body = fallback.strip("\n").splitlines() or ["_No changes recorded._"]

    replacement = [
        f"## [{UNRELEASED}]",
        "",
        f"## [{version}] - {date}",
        "",
        *body,
        "",
    ]
    lines[start:end] = replacement
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Version being released, e.g. 0.4.0")
    parser.add_argument("--changelog", default="CHANGELOG.md", type=Path)
    parser.add_argument(
        "--fallback-notes",
        type=Path,
        help="Markdown file used as the section body when [Unreleased] is empty.",
    )
    parser.add_argument("--date", help="Release date (YYYY-MM-DD). Defaults to today (UTC).")
    parser.add_argument(
        "--stdout",
        action="store_true",
        help="Print the result instead of rewriting the file (for local checks).",
    )
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?", args.version):
        raise SystemExit(f"Invalid version: {args.version}")

    date = args.date or _datetime.datetime.now(_datetime.timezone.utc).strftime("%Y-%m-%d")
    fallback = ""
    if args.fallback_notes and args.fallback_notes.exists():
        fallback = args.fallback_notes.read_text()

    try:
        result = promote(args.changelog.read_text(), args.version, date, fallback)
    except SystemExit as exc:
        raise SystemExit(f"{args.changelog}: {exc}") from exc

    if args.stdout:
        sys.stdout.write(result)
    else:
        args.changelog.write_text(result)
        print(f"✅ CHANGELOG.md: [Unreleased] closed as [{args.version}] - {date}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
