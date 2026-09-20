# Paddle Quest — Godot 4 VR demo for Meta Quest 3/3S

jdk := `mise where java@temurin-21`
apk := "build/paddleball.apk"
openxr_vendors := "5.1.0-stable"

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

# --xr-mode off skips OpenXR probing, which otherwise throws a modal
# "no HMD detected" dialog and blocks startup.

# Play flat on the desktop (mouse moves the paddle, Esc quits).
play:
    godot --xr-mode off

# Open the project in the editor.
edit:
    godot -e --xr-mode off

# Headless smoke test: boots the scene, runs the rally loop, exits.
check:
    godot --headless --xr-mode off --quit-after 1200

# Build a debug APK for the headset.
build:
    JAVA_HOME={{jdk}} ANDROID_HOME=$HOME/Android/Sdk \
      godot --headless --xr-mode off --export-debug "Quest" {{apk}}
    @ls -lh {{apk}}

install:
    adb install -r {{apk}}

deploy: build install

log:
    adb logcat -s godot:V GodotOpenXR:V

devices:
    adb devices -l

# Launch the installed app without taking the headset off.
run:
    adb shell monkey -p com.cascadiacollections.paddlequest -c android.intent.category.LAUNCHER 1

uninstall:
    adb uninstall com.cascadiacollections.paddlequest

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
