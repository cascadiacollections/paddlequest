# Paddle Quest — Godot 4 VR demo for Meta Quest 3/3S

# just evaluates backticks eagerly at load, so this must not fail on a machine
# without mise - otherwise every recipe dies, including on CI and in the
# container. Falls back to whatever JAVA_HOME is already set to.
jdk := `mise where java@temurin-21 2>/dev/null || echo "${JAVA_HOME:-}"`
apk := "build/paddleball.apk"
apk_release := "build/paddleball-release.apk"
frame_bin := "build/paddlequest.arm64"
openxr_vendors := "5.1.0-stable"
gut_version := "9.7.1"

# With both USB and Wi-Fi transports connected, adb refuses to guess. Set
# ADB_TARGET to a serial or ip:port to pick one, e.g.
#   ADB_TARGET=192.168.1.121:5555 just deploy
device := env_var_or_default("ADB_TARGET", "")
adb := if device == "" { "adb" } else { "adb -s " + device }

# Fetch the OpenXR vendors addon. It is gitignored because it is 82MB of
# prebuilt binaries for every platform; this pulls the pinned release.
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -d addons/godotopenxrvendors ]; then
      echo "godotopenxrvendors already installed"; exit 0
    fi
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/addon.zip" \
      "https://github.com/GodotVR/godot_openxr_vendors/releases/download/{{openxr_vendors}}/godotopenxrvendorsaddon.zip"
    unzip -q "$tmp/addon.zip" -d "$tmp"
    mkdir -p addons
    cp -r "$tmp/asset/addons/godotopenxrvendors" addons/
    echo "installed godotopenxrvendors {{openxr_vendors}}"

    if [ ! -d addons/gut ]; then
      curl -fsSL -o "$tmp/gut.zip" \
        "https://github.com/bitwes/Gut/archive/refs/tags/v{{gut_version}}.zip"
      unzip -q "$tmp/gut.zip" -d "$tmp/gut"
      cp -r "$tmp/gut/Gut-{{gut_version}}/addons/gut" addons/
      echo "installed gut {{gut_version}}"
    fi

# Play flat on the desktop (mouse moves the paddle, Esc quits).
play:
    godot

# Open the project in the editor.
edit:
    godot -e

# Headless smoke test: boots the scene, runs the rally loop, exits.
check:
    godot --headless --quit-after 1200

# Regenerate the paddle mesh from tools/make_paddle.py.
paddle:
    blender --background --python tools/make_paddle.py
    @ls -lh assets/paddle.glb

# Regression suite (GUT), headless.
test:
    godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit -gprefix=test_

# Prove the suite can fail by reintroducing the serve-sag bug.
# Restores via git rather than a temp copy: if this is interrupted mid-run,
# `git checkout -- scripts/ball.gd` always puts the tree back. An earlier
# version used a trap and left a broken file behind when it was killed.
test-mutation:
    #!/usr/bin/env bash
    set -uo pipefail
    if [ -n "$(git status --porcelain scripts/ball.gd)" ]; then
      echo "scripts/ball.gd has uncommitted changes; commit or stash first"
      exit 1
    fi
    trap 'git checkout -- scripts/ball.gd' EXIT INT TERM
    python3 - <<'EOF'
    import re
    p = "scripts/ball.gd"
    s = open(p).read()
    s = re.sub(
        r"linear_velocity = flat\.normalized\(\).*?\n\t\)\n",
        "linear_velocity = (toward - from).normalized() * serve_speed\n",
        s, flags=re.S,
    )
    open(p, "w").write(s)
    EOF
    if just test > /tmp/mutation.log 2>&1; then
      echo "MUTATION SURVIVED - the suite does not cover the serve trajectory"
      exit 1
    fi
    echo "mutation caught, suite has teeth"

# Lint and format check, the same set CI gates on. Needs
# `pip install gdtoolkit==4.5.0 ruff==0.14.0`.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in scripts/*.gd test/*.gd; do
      gdparse "$f" > /dev/null || { echo "failed to parse: $f"; exit 1; }
    done
    echo "all GDScript parses"
    gdformat --check scripts/ test/
    gdlint scripts/ test/
    ruff check tools/
    ruff format --check tools/

# Apply the formatters rather than just checking them.
format:
    gdformat scripts/ test/
    ruff format tools/

# Build a debug APK: bigger and slower, but carries the remote debugger.
build:
    JAVA_HOME={{jdk}} ANDROID_HOME=$HOME/Android/Sdk \
      godot --headless --export-debug "Quest" {{apk}}
    @ls -lh {{apk}}

# Build a release APK. Roughly half the size and without debug overhead;
# this is what you demo. Keystore comes from the environment so nothing
# machine-specific or secret lands in export_presets.cfg.
build-release:
    JAVA_HOME={{jdk}} ANDROID_HOME=$HOME/Android/Sdk \
      GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/.local/share/godot/keystores/debug.keystore}" \
      GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey}" \
      GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android}" \
      godot --headless --export-release "Quest" {{apk_release}}
    @ls -lh {{apk_release}}

deploy-release: build-release
    {{adb}} install -r {{apk_release}}

# What version a build would identify as. CI stamps this automatically.
version:
    @python3 tools/stamp_version.py --check

# Write that version into export_presets.cfg. Only needed for a local build
# you intend to keep or hand to someone - it modifies a tracked file, so
# revert it afterwards rather than committing the result.
stamp-version:
    python3 tools/stamp_version.py

# --- Steam Frame -----------------------------------------------------
# Frame runs SteamOS on ARM, so the standalone build is a Linux arm64
# binary rather than an APK - no Gradle, no SDK, no keystore. The Meta
# vendor plugin is Quest-only and is not part of this preset.
#
# Needs the linux arm64 export template, which ships in the same
# export_templates bundle the Quest build already uses.
build-frame:
    godot --headless --export-release "Steam Frame" {{frame_bin}}
    @ls -lh {{frame_bin}}

build-frame-debug:
    godot --headless --export-debug "Steam Frame" {{frame_bin}}
    @ls -lh {{frame_bin}}

install:
    {{adb}} install -r {{apk}}

deploy: build install

log:
    {{adb}} logcat -s godot:V GodotOpenXR:V

devices:
    adb devices -l

# Launch the installed app without taking the headset off.
run:
    {{adb}} shell monkey -p com.cascadiacollections.paddlequest -c android.intent.category.LAUNCHER 1

uninstall:
    {{adb}} uninstall com.cascadiacollections.paddlequest

# --- Wi-Fi deployment -------------------------------------------------
# One-time, with the headset on USB: flip adb into TCP mode and connect.
# After this the cable can come out and `just deploy` works over the air.
wifi-setup:
    adb tcpip 5555
    @sleep 2
    @echo "Headset IP: $(adb shell ip route | awk '{print $9}')"
    adb connect $(adb shell ip route | awk '{print $9}'):5555

# Reconnect over Wi-Fi in a later session (headset must be awake).
wifi-connect ip:
    adb connect {{ip}}:5555

wifi-off:
    adb disconnect
    adb usb
