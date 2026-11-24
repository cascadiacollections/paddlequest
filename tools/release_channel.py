"""Plan a release. This does not publish one.

    python3 tools/release_channel.py --plan build/release-channel-plan.json
    python3 tools/release_channel.py --publish   # always refused

Dry-run is the only successful path. It exits 0 with no secrets configured
and writes a plan: which artifacts would ship, whether signing is release
or unsigned, and the exact Horizon and Steam commands those secrets would
fill in. Values of secrets are never copied into the plan or onto stdout.

--publish, and RELEASE_CHANNEL_PUBLISH=true, exit 1 before any file is
written. Nothing here creates a GitHub Release, pushes a tag, or uploads
to a store. See docs/release-channel.md.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

import stamp_version

ROOT = Path(__file__).resolve().parent.parent

KEYSTORE_SECRETS = (
    "ANDROID_KEYSTORE_BASE64",
    "ANDROID_KEYSTORE_USER",
    "ANDROID_KEYSTORE_PASSWORD",
)
HORIZON_SECRETS = ("HORIZON_APP_ID", "HORIZON_APP_SECRET")
HORIZON_AGE_GROUP = "HORIZON_AGE_GROUP"
HORIZON_AGE_GROUPS = ("TEENS_AND_ADULTS", "MIXED_AGES", "CHILDREN")
STEAM_SECRETS = (
    "STEAM_USERNAME",
    "STEAM_CONFIG_VDF_BASE64",
    "STEAM_SSFN_FILENAME",
    "STEAM_SSFN_BASE64",
    "STEAM_APP_ID",
    "STEAM_DEPOT_FRAME_ID",
)
# Every value the plan must not echo. HORIZON_AGE_GROUP is a setting, not a
# secret: a legal value may appear in the plan, anything else may not.
SECRET_ENV = KEYSTORE_SECRETS + HORIZON_SECRETS + STEAM_SECRETS

ARTIFACTS = (
    "build/paddleball-release.apk",
    "build/paddlequest.arm64",
    "build/xr-webview-addon.zip",
)
ICON_KEYS = (
    "launcher_icons/main_192x192",
    "launcher_icons/adaptive_foreground_432x432",
    "launcher_icons/adaptive_background_432x432",
    "launcher_icons/adaptive_monochrome_432x432",
)

REFUSAL = (
    "refusing to publish: this tool only plans a release. "
    "It does not create a GitHub Release, push a tag, or upload to "
    "the Horizon Store or Steam. See docs/release-channel.md."
)


def _set(env: dict, name: str) -> bool:
    return bool(env.get(name, "").strip())


def _missing(env: dict, names: tuple) -> list:
    return [name for name in names if not _set(env, name)]


def signing(env: dict) -> dict:
    missing = _missing(env, KEYSTORE_SECRETS)
    if not missing:
        mode = "release"
    elif len(missing) == len(KEYSTORE_SECRETS):
        mode = "unsigned"
    else:
        mode = "incomplete"
    return {"mode": mode, "missing": missing}


def artifact_report(root: Path) -> dict:
    present = {}
    for relative in ARTIFACTS:
        path = root / relative
        present[relative] = path.is_file() and path.stat().st_size > 0
    return present


def launcher_icons(text: str) -> dict:
    found = {}
    for key in ICON_KEYS:
        match = re.search(rf'^{re.escape(key)}="([^"]*)"', text, re.M)
        found[key] = match.group(1) if match else ""
    empty = [key for key, value in found.items() if not value]
    return {
        "explicit": not empty,
        "empty": empty,
        "note": (
            "launcher_icons in export_presets.cfg are filled, so the APK is not "
            "falling back to config/icon."
            if not empty
            else (
                "launcher_icons/* are empty in export_presets.cfg, so the APK "
                "falls back to config/icon (icon.svg). A store listing wants "
                "these four sizes filled in before submission. This plan does "
                "not generate them."
            )
        ),
    }


def horizon_command(version_name: str) -> list:
    return [
        "ovr-platform-util",
        "upload-quest-build",
        "--age-group",
        "$HORIZON_AGE_GROUP",
        "--app-id",
        "$HORIZON_APP_ID",
        "--app-secret",
        "$HORIZON_APP_SECRET",
        "--apk",
        "build/paddleball-release.apk",
        "--channel",
        "ALPHA",
        "--notes",
        f"Paddle Quest {version_name}",
        "--disable-progress-bar",
    ]


def steam_vdf(version_name: str) -> str:
    return (
        '"AppBuild"\n'
        "{\n"
        '\t"AppID" "$STEAM_APP_ID"\n'
        f'\t"Desc" "Paddle Quest {version_name}"\n'
        '\t"ContentRoot" "build"\n'
        '\t"BuildOutput" "build/steam/output"\n'
        '\t"Depots"\n'
        "\t{\n"
        '\t\t"$STEAM_DEPOT_FRAME_ID"\n'
        "\t\t{\n"
        '\t\t\t"FileMapping"\n'
        "\t\t\t{\n"
        '\t\t\t\t"LocalPath" "paddlequest.arm64"\n'
        '\t\t\t\t"DepotPath" "."\n'
        '\t\t\t\t"recursive" "0"\n'
        "\t\t\t}\n"
        "\t\t}\n"
        "\t}\n"
        "}\n"
    )


def steam_command() -> list:
    return [
        "steamcmd",
        "+login",
        "$STEAM_USERNAME",
        "+run_app_build",
        "build/steam/app_build.vdf",
        "+quit",
    ]


def build_plan(env: dict, root: Path, version_code: int, version_name: str) -> dict:
    signed = signing(env)
    age = env.get(HORIZON_AGE_GROUP, "").strip()
    age_ok = age in HORIZON_AGE_GROUPS
    horizon_missing = _missing(env, HORIZON_SECRETS)
    if not age_ok:
        horizon_missing.append(HORIZON_AGE_GROUP)
    steam_missing = _missing(env, STEAM_SECRETS)
    presets = root / "export_presets.cfg"
    icons = launcher_icons(presets.read_text() if presets.is_file() else "")
    return {
        "dry_run": True,
        "executed": [],
        "would_create_release": False,
        "would_push_tag": False,
        "would_upload_store": False,
        "version": {"code": version_code, "name": version_name},
        "signing": signed,
        "artifacts": artifact_report(root),
        "launcher_icons": icons,
        "channels": {
            "github": {
                "status": "dry-run",
                "would_create_release": False,
                "signing_ready": signed["mode"] == "release",
                "assets": list(ARTIFACTS),
                "note": (
                    "A v* tag runs .github/workflows/build.yml, which drafts a "
                    "GitHub Release with these three files and fails unless all "
                    "three keystore secrets are set. This workflow does not call "
                    "gh release create and does not push a tag."
                ),
            },
            "horizon": {
                "status": "dry-run",
                "channel": "ALPHA",
                "ready": not horizon_missing,
                "missing": horizon_missing,
                "age_group": age if age_ok else None,
                "command": horizon_command(version_name),
            },
            "steam": {
                "status": "dry-run",
                "ready": not steam_missing,
                "missing": steam_missing,
                "command": steam_command(),
                "app_build_vdf": steam_vdf(version_name),
            },
        },
    }


def _assert_no_secret_values(plan: dict, env: dict) -> None:
    """A secret that leaked into the plan is a failed dry-run, not a plan."""
    blob = json.dumps(plan)
    for name in SECRET_ENV:
        value = env.get(name, "").strip()
        if len(value) >= 4 and value in blob:
            sys.exit(f"refusing to write the plan: it contains the value of {name}")


def _wants_publish(args: argparse.Namespace) -> bool:
    flag = os.environ.get("RELEASE_CHANNEL_PUBLISH", "").strip().lower()
    return bool(args.publish) or flag in {"1", "true", "yes"}


def main(argv: list | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--plan", type=Path, default=None, help="write the plan JSON here"
    )
    parser.add_argument(
        "--publish",
        action="store_true",
        help="refused; publishing is not implemented",
    )
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--version-code", type=int, default=None)
    parser.add_argument("--version-name", default=None)
    args = parser.parse_args(argv)

    if _wants_publish(args):
        print(REFUSAL, file=sys.stderr)
        return 1

    code = (
        args.version_code
        if args.version_code is not None
        else stamp_version.default_code()
    )
    name = (
        args.version_name
        if args.version_name is not None
        else stamp_version.default_name()
    )
    plan = build_plan(dict(os.environ), args.root, code, name)
    _assert_no_secret_values(plan, dict(os.environ))
    text = json.dumps(plan, indent=2) + "\n"
    if args.plan is not None:
        args.plan.parent.mkdir(parents=True, exist_ok=True)
        args.plan.write_text(text)

    signing_mode = plan["signing"]["mode"]
    ready = []
    if plan["channels"]["github"]["signing_ready"]:
        ready.append("github")
    for channel in ("horizon", "steam"):
        if plan["channels"][channel]["ready"]:
            ready.append(channel)
    present = sum(1 for exists in plan["artifacts"].values() if exists)
    print(
        f"dry-run signing={signing_mode} "
        f"channels={','.join(ready) or 'none'} "
        f"artifacts={present}/{len(ARTIFACTS)}"
    )
    print(text, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
