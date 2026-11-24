"""The release planner never publishes, and never prints a secret."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import release_channel

ROOT = Path(__file__).resolve().parent.parent
CANARY = "canary-secret-value-xyz"
PRESETS = """
[preset.0.options]
version/code=1
version/name="1.0"
launcher_icons/main_192x192=""
launcher_icons/adaptive_foreground_432x432=""
launcher_icons/adaptive_background_432x432=""
launcher_icons/adaptive_monochrome_432x432=""
"""


def _root(icons_filled: bool = False) -> Path:
    root = Path(tempfile.mkdtemp())
    text = PRESETS
    if icons_filled:
        text = text.replace('=""', '="icon.png"')
    (root / "export_presets.cfg").write_text(text)
    return root


def _env_with(values: dict) -> dict:
    env = {name: "" for name in release_channel.SECRET_ENV}
    env[release_channel.HORIZON_AGE_GROUP] = ""
    env.update(values)
    return env


class ReleaseChannelTest(unittest.TestCase):
    def test_unsigned_dry_run_has_nothing_to_execute(self) -> None:
        plan = release_channel.build_plan(_env_with({}), _root(), 7, "v0.0.0-test")
        self.assertTrue(plan["dry_run"])
        self.assertEqual(plan["executed"], [])
        self.assertFalse(plan["would_create_release"])
        self.assertFalse(plan["would_push_tag"])
        self.assertFalse(plan["would_upload_store"])
        self.assertEqual(plan["signing"]["mode"], "unsigned")
        self.assertEqual(
            plan["signing"]["missing"], list(release_channel.KEYSTORE_SECRETS)
        )
        self.assertFalse(plan["channels"]["github"]["would_create_release"])
        self.assertFalse(plan["channels"]["github"]["signing_ready"])
        self.assertFalse(plan["channels"]["horizon"]["ready"])
        self.assertFalse(plan["channels"]["steam"]["ready"])
        self.assertIn("ALPHA", plan["channels"]["horizon"]["command"])
        self.assertIn("$HORIZON_APP_SECRET", plan["channels"]["horizon"]["command"])
        self.assertIn("steamcmd", plan["channels"]["steam"]["command"])
        self.assertIn(
            "$STEAM_DEPOT_FRAME_ID", plan["channels"]["steam"]["app_build_vdf"]
        )
        self.assertTrue(all(not present for present in plan["artifacts"].values()))
        self.assertFalse(plan["launcher_icons"]["explicit"])

    def test_a_partial_keystore_is_incomplete_not_release(self) -> None:
        env = _env_with({"ANDROID_KEYSTORE_BASE64": CANARY})
        plan = release_channel.build_plan(env, _root(), 1, "v1")
        self.assertEqual(plan["signing"]["mode"], "incomplete")
        self.assertIn("ANDROID_KEYSTORE_USER", plan["signing"]["missing"])
        self.assertIn("ANDROID_KEYSTORE_PASSWORD", plan["signing"]["missing"])
        self.assertNotIn(CANARY, json.dumps(plan))

    def test_full_secrets_still_do_not_publish_or_leak(self) -> None:
        env = _env_with({name: CANARY for name in release_channel.SECRET_ENV})
        env[release_channel.HORIZON_AGE_GROUP] = "TEENS_AND_ADULTS"
        plan = release_channel.build_plan(env, _root(), 4, "v1.2.3")
        self.assertEqual(plan["signing"]["mode"], "release")
        self.assertTrue(plan["channels"]["github"]["signing_ready"])
        self.assertTrue(plan["channels"]["horizon"]["ready"])
        self.assertEqual(plan["channels"]["horizon"]["age_group"], "TEENS_AND_ADULTS")
        self.assertTrue(plan["channels"]["steam"]["ready"])
        self.assertEqual(plan["executed"], [])
        self.assertFalse(plan["would_upload_store"])
        blob = json.dumps(plan)
        self.assertNotIn(CANARY, blob)
        self.assertIn("Paddle Quest v1.2.3", plan["channels"]["horizon"]["command"])

    def test_an_unknown_age_group_is_not_ready(self) -> None:
        env = _env_with({name: "x" for name in release_channel.HORIZON_SECRETS})
        env[release_channel.HORIZON_AGE_GROUP] = "EVERYONE"
        plan = release_channel.build_plan(env, _root(), 1, "v1")
        self.assertFalse(plan["channels"]["horizon"]["ready"])
        self.assertIsNone(plan["channels"]["horizon"]["age_group"])
        self.assertIn("HORIZON_AGE_GROUP", plan["channels"]["horizon"]["missing"])
        self.assertNotIn("EVERYONE", json.dumps(plan))

    def test_filled_launcher_icons_are_reported(self) -> None:
        plan = release_channel.build_plan(
            _env_with({}), _root(icons_filled=True), 1, "v1"
        )
        self.assertTrue(plan["launcher_icons"]["explicit"])
        self.assertEqual(plan["launcher_icons"]["empty"], [])

    def test_the_repo_presets_still_have_empty_launcher_icons(self) -> None:
        icons = release_channel.launcher_icons(
            (ROOT / "export_presets.cfg").read_text()
        )
        self.assertFalse(icons["explicit"])
        self.assertEqual(icons["empty"], list(release_channel.ICON_KEYS))

    def test_cli_dry_run_exits_zero_and_writes_a_plan(self) -> None:
        root = _root()
        plan_path = root / "build" / "release-channel-plan.json"
        env = {"PATH": os.environ["PATH"]}
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "release_channel.py"),
                "--root",
                str(root),
                "--plan",
                str(plan_path),
                "--version-code",
                "9",
                "--version-name",
                "v9-test",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn("signing=unsigned", completed.stdout)
        plan = json.loads(plan_path.read_text())
        self.assertEqual(plan["version"], {"code": 9, "name": "v9-test"})
        self.assertEqual(plan["executed"], [])
        presets_after = (root / "export_presets.cfg").read_text()
        self.assertIn("version/code=1", presets_after)

    def test_publish_is_refused_and_writes_nothing(self) -> None:
        root = _root()
        plan_path = root / "build" / "release-channel-plan.json"
        env = {
            "PATH": os.environ["PATH"],
            "ANDROID_KEYSTORE_BASE64": CANARY,
            "ANDROID_KEYSTORE_USER": CANARY,
            "ANDROID_KEYSTORE_PASSWORD": CANARY,
            "RELEASE_CHANNEL_PUBLISH": "true",
        }
        completed = subprocess.run(
            [
                sys.executable,
                str(ROOT / "tools" / "release_channel.py"),
                "--root",
                str(root),
                "--plan",
                str(plan_path),
                "--publish",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("refusing to publish", completed.stderr)
        self.assertNotIn(CANARY, completed.stdout + completed.stderr)
        self.assertFalse(plan_path.exists())

    def test_the_module_does_not_spawn_upload_tools(self) -> None:
        source = Path(release_channel.__file__).read_text()
        # The plan names the commands in strings. It must not have a way to run them.
        for banned in ("import subprocess", "os.system", "Popen"):
            self.assertNotIn(banned, source)

    def test_the_workflow_is_read_only_and_cannot_publish(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "release-channel.yml").read_text()
        self.assertIn("contents: read", workflow)
        self.assertNotIn("contents: write", workflow)
        for banned in (
            "gh release",
            "ovr-platform-util",
            "steamcmd",
            "softprops/action-gh-release",
        ):
            self.assertNotIn(banned, workflow)
        self.assertIn("RELEASE_CHANNEL_PUBLISH", workflow)

    def test_the_doc_names_every_secret_and_the_age_group(self) -> None:
        doc = (ROOT / "docs" / "release-channel.md").read_text()
        for name in release_channel.SECRET_ENV:
            self.assertIn(name, doc)
        self.assertIn(release_channel.HORIZON_AGE_GROUP, doc)
        for age in release_channel.HORIZON_AGE_GROUPS:
            self.assertIn(age, doc)
        self.assertIn("ALPHA", doc)
        self.assertIn("upload-quest-build", doc)


if __name__ == "__main__":
    unittest.main()
