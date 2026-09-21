"""Stamp a build version into the Android export preset.

    python3 tools/stamp_version.py [--code N] [--name STR] [--check]

export_presets.cfg ships version/code=1 and version/name="1.0", and nothing
ever changed them, so every build this project has produced identifies as
version 1. Two of them cannot coexist anywhere that keys on version code -
a device refuses the sideload, a store refuses the upload.

This rewrites those two fields in place. CI runs it before exporting; the
modified file is not meant to be committed, which is what --check is for.

Defaults, when the flags are not given:
  code  $GITHUB_RUN_NUMBER, else the commit count on HEAD
  name  git describe --tags --always, else 0.0.0-<short sha>

Only the Android preset carries a version. The Linux/Steam Frame preset has
no such fields, so it is left alone.
"""

import argparse
import os
import re
import subprocess
import sys

PRESETS = os.path.join(os.path.dirname(os.path.dirname(__file__)), "export_presets.cfg")
SECTION = "[preset.0.options]"


def _git(*args: str) -> str:
    try:
        return subprocess.run(
            ["git", *args], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def default_code() -> int:
    run = os.environ.get("GITHUB_RUN_NUMBER", "").strip()
    if run.isdigit() and int(run) > 0:
        return int(run)
    count = _git("rev-list", "--count", "HEAD")
    return int(count) if count.isdigit() and int(count) > 0 else 1


def default_name() -> str:
    described = _git("describe", "--tags", "--always")
    if described:
        return described
    sha = _git("rev-parse", "--short", "HEAD")
    return f"0.0.0-{sha}" if sha else "0.0.0"


def stamp(text: str, code: int, name: str) -> str:
    """Rewrite version/code and version/name inside the Android preset only."""
    start = text.index(SECTION)
    # Up to the next section header, so a later preset is never touched.
    nxt = text.find("\n[", start + len(SECTION))
    end = len(text) if nxt == -1 else nxt
    body = text[start:end]

    body, n_code = re.subn(r"^version/code=.*$", f"version/code={code}", body, flags=re.M)
    body, n_name = re.subn(
        r"^version/name=.*$", f'version/name="{name}"', body, flags=re.M
    )
    if n_code != 1 or n_name != 1:
        sys.exit(
            f"expected exactly one version/code and version/name in {SECTION}, "
            f"found {n_code} and {n_name}"
        )
    return text[:start] + body + text[end:]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--code", type=int, default=None)
    ap.add_argument("--name", default=None)
    ap.add_argument(
        "--check",
        action="store_true",
        help="report the version that would be stamped and write nothing",
    )
    args = ap.parse_args()

    code = args.code if args.code is not None else default_code()
    name = args.name if args.name is not None else default_name()
    if code < 1:
        sys.exit(f"version code must be a positive integer, got {code}")

    original = open(PRESETS).read()
    if SECTION not in original:
        sys.exit(f"{SECTION} not found in {PRESETS}")

    updated = stamp(original, code, name)
    if args.check:
        print(f"would stamp version code {code}, name {name}")
        return

    open(PRESETS, "w").write(updated)
    print(f"stamped version code {code}, name {name}")


if __name__ == "__main__":
    main()
