# Paddle Quest — Godot 4 VR demo for Meta Quest 3/3S

# just evaluates backticks eagerly at load, so this must not fail on a machine
# without mise - otherwise every recipe dies, including on CI and in the
# container. Falls back to whatever JAVA_HOME is already set to.
jdk := `mise where java@temurin-21 2>/dev/null || echo "${JAVA_HOME:-}"`
apk := "build/paddleball.apk"
apk_release := "build/paddleball-release.apk"
openxr_vendors := "5.1.0-stable"

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

# Play flat on the desktop (mouse moves the paddle, Esc quits).
play:
    godot

# Open the project in the editor.
edit:
    godot -e

# Headless smoke test: boots the scene, runs the rally loop, exits.
check:
    godot --headless --quit-after 1200

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
