#!/usr/bin/env python3
"""Gate newly introduced SwiftLint errors without hiding the existing lint backlog."""
import collections
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def violations(directory):
    result = subprocess.run(
        ["swiftlint", "lint", "--quiet", "--no-cache", "--reporter", "json"],
        cwd=directory, capture_output=True, text=True,
    )
    try:
        records = json.loads(result.stdout)
    except ValueError:
        raise RuntimeError(result.stderr or result.stdout)
    counts = collections.Counter()
    for entry in records:
        if entry["severity"] == "Error":
            relative = str(Path(entry["file"]).resolve().relative_to(directory.resolve()))
            counts[(relative, entry["rule_id"])] += 1
    return counts


def main():
    reference = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    if not reference.strip("0"):
        reference = "HEAD^"
    archive = subprocess.check_output(["git", "archive", reference], cwd=ROOT)
    with tempfile.TemporaryDirectory(prefix="watermelonfin-lint-") as temporary:
        baseline_root = Path(temporary)
        with tarfile.open(fileobj=io.BytesIO(archive)) as source:
            # A baseline needs only ordinary source/config files, never symlinks.
            for member in source:
                path = Path(member.name)
                if member.isfile() and not path.is_absolute() and ".." not in path.parts:
                    source.extract(member, baseline_root)
        baseline = violations(baseline_root)
    current = violations(ROOT)
    regressions = current - baseline
    for (path, rule), count in sorted(regressions.items()):
        print(f"{path}: {count} new SwiftLint error(s): {rule}")
    print(f"SwiftLint: {sum(current.values())} existing errors; {sum(regressions.values())} new errors")
    return bool(regressions)


if __name__ == "__main__":
    sys.exit(main())
