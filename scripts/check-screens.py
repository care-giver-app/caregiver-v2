#!/usr/bin/env python3
"""Check the screen catalogues in docs/PRD.md.

Every exit must name a screen that exists, every screen must be reachable, and
no screen may be a dead end. Reads the ```yaml fences under each "#### Screens"
heading, so the PRD stays the only document.
"""
import re
import sys
from pathlib import Path

PRD = Path(__file__).resolve().parent.parent / "docs" / "PRD.md"
KINDS = {"push", "sheet", "swap", "stays", "tab", "root", "out", "back", "???"}
# Destinations that deliberately leave the app or point outside the catalogue.
EXTERNAL = (
    "the phone",
    "the Settings app",
    "the mail app",
    "the terms",
    "the privacy policy",
    "the screen that raised it",
    "???",
)


def unfold(block):
    """Join YAML folded scalars (`key: >` + indented lines) onto one line."""
    out, lines, i = [], block.splitlines(), 0
    while i < len(lines):
        line = lines[i]
        if m := re.match(r"^(\s*)(-\s+)?(\w+): >-?\s*$", line):
            indent = len(m.group(1)) + (len(m.group(2)) if m.group(2) else 0)
            parts, i = [], i + 1
            while i < len(lines) and (not lines[i].strip() or len(lines[i]) - len(lines[i].lstrip()) > indent):
                parts.append(lines[i].strip())
                i += 1
            prefix = m.group(1) + (m.group(2) or "")
            out.append(f"{prefix}{m.group(3)}: {' '.join(p for p in parts if p)}")
            continue
        out.append(line)
        i += 1
    return "\n".join(out)


def parse(text):
    screens, current = {}, None
    for block in re.findall(r"```yaml\n(.*?)```", text, re.S):
        for line in unfold(block).splitlines():
            if m := re.match(r"^- screen: (.+)$", line):
                current = m.group(1).strip()
                screens[current] = {"exits": [], "kind": None}
            elif m := re.match(r"^  kind: (.+)$", line):
                screens[current]["kind"] = m.group(1).strip()
            elif m := re.match(r"^      to: (.+)$", line):
                screens[current]["exits"].append(("to", m.group(1).strip()))
            elif m := re.match(r"^      as: (.+)$", line):
                screens[current]["exits"].append(("as", m.group(1).strip()))
    return screens


def resolve(dest, names):
    """A destination names a screen if it is that screen, or starts with it."""
    if dest.startswith(EXTERNAL):
        return dest
    hits = [n for n in names if dest == n or dest.startswith(n + ",") or dest.startswith(n + " ")]
    return max(hits, key=len) if hits else None


def main():
    screens = parse(PRD.read_text())
    names = set(screens)
    problems, reached = [], set()

    for name, data in screens.items():
        tos = [v for k, v in data["exits"] if k == "to"]
        ases = [v for k, v in data["exits"] if k == "as"]
        if not tos:
            problems.append(f"dead end: {name!r} has no exits")
        for dest in tos:
            target = resolve(dest, names)
            if target is None:
                problems.append(f"unknown destination: {name!r} -> {dest!r}")
            elif target in names:
                reached.add(target)
        for kind in ases:
            if kind not in KINDS:
                problems.append(f"unknown exit kind: {name!r} uses {kind!r}")

    entry = {"Landing"}
    for name in sorted(names - reached - entry):
        problems.append(f"unreachable: nothing exits to {name!r}")

    opens = len(re.findall(r"\?\?\?", PRD.read_text()))
    print(f"{len(screens)} screens, {sum(len([v for k,v in d['exits'] if k=='to']) for d in screens.values())} exits, {opens} open questions marked ???")
    for problem in problems:
        print(f"  {problem}")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
