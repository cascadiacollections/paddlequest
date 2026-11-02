#!/usr/bin/env bash
# Opt-in Godot 4.8-beta2 compatibility trial.
#
# The editor, CI, devcontainer and exports stay on the stable pin (GODOT_VERSION
# in .github/workflows/build.yml, which must match .devcontainer/Dockerfile).
# This script downloads the beta editor and its matching export templates into
# its own cache, points that editor at those templates with an isolated
# XDG_DATA_HOME, and runs import / GUT / smoke / export on a copy of the
# project. It never installs a `godot` binary onto PATH and never writes the
# beta back into the stable pin files.
#
# Official release binaries only. Building Godot from source is out of scope,
# so the 4.8 engine-build Python floor (3.9 -> 3.10, GH-122597) is not checked.
#
# Usage:
#   bash tools/godot_48_trial.sh
#   GODOT_TRIAL_SKIP_ANDROID=1 bash tools/godot_48_trial.sh   # no APK
#   GODOT_TRIAL_SKIP_STABLE=1 bash tools/godot_48_trial.sh    # beta only
#
# Android export runs when ANDROID_HOME is set and points at an SDK. The Quest
# preset needs JDK 17+ (this project uses 21) and does not ask for a newer NDK
# or compile SDK than 4.7.2.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRIAL_TAG="4.8-beta2"
TRIAL_REPO="godotengine/godot-builds"
CACHE="${GODOT_TRIAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/paddlequest/godot-trial}"
DOWNLOADS="$CACHE/downloads"
EXPORT_TEMPLATES="$CACHE/export_templates"
REPORT="$CACHE/report.txt"
SEED="$CACHE/seed"

fail=0
note_fail() {
  fail=1
  printf 'FAIL: %s\n' "$*" | tee -a "$REPORT" >&2
}

say() {
  # stderr, not stdout: several helpers print a single token for the caller
  # to capture, and a log line on stdout would become part of that token.
  printf '== %s\n' "$*" | tee -a "$REPORT" >&2
}

# Stable pin is whatever CI already ships. A second hardcoded version here
# would drift from the editor and the container.
read_stable_version() {
  local ci docker
  ci="$(awk '/^[[:space:]]*GODOT_VERSION:[[:space:]]*/ { print $2; exit }' "$ROOT/.github/workflows/build.yml")"
  docker="$(sed -n 's/^ARG GODOT_VERSION=//p' "$ROOT/.devcontainer/Dockerfile" | head -1)"
  if [ -z "$ci" ] || [ -z "$docker" ]; then
    echo "could not read the stable Godot pin" >&2
    exit 1
  fi
  if [ "$ci" != "$docker" ]; then
    echo "stable pin diverges: workflow has $ci, Dockerfile has $docker" >&2
    exit 1
  fi
  printf '%s' "$ci"
}

just_value() {
  sed -n "s/^$1 := \"\\(.*\\)\"/\\1/p" "$ROOT/justfile" | head -1
}

fetch_release() {
  local repo="$1" tag="$2"
  local base="https://github.com/${repo}/releases/download/${tag}"
  local sums="$DOWNLOADS/SHA512-SUMS-${tag}.txt"
  mkdir -p "$DOWNLOADS"
  if [ ! -s "$sums" ]; then
    curl -fsSL -o "$sums" "${base}/SHA512-SUMS.txt"
  fi
  local name
  for name in "Godot_v${tag}_linux.x86_64.zip" "Godot_v${tag}_export_templates.tpz"; do
    if [ -f "$DOWNLOADS/$name" ]; then
      say "checksum $name"
    else
      say "download $name"
      curl -fL --retry 3 --retry-delay 2 -o "$DOWNLOADS/$name.partial" "${base}/${name}"
      mv "$DOWNLOADS/$name.partial" "$DOWNLOADS/$name"
    fi
    (
      cd "$DOWNLOADS"
      grep -E "[[:space:]]${name}$" "$sums" | sha512sum -c -
    )
  done
}

install_editor() {
  local tag="$1"
  local dest="$CACHE/editors/$tag"
  if [ ! -x "$dest/godot" ]; then
    rm -rf "$dest"
    mkdir -p "$dest"
    unzip -q -o "$DOWNLOADS/Godot_v${tag}_linux.x86_64.zip" -d "$dest"
    local bin
    bin="$(find "$dest" -maxdepth 1 -type f -name 'Godot_v*' | head -1)"
    if [ -z "$bin" ]; then
      echo "editor zip for $tag has no Godot binary" >&2
      exit 1
    fi
    mv "$bin" "$dest/godot"
    chmod +x "$dest/godot"
  fi
  printf '%s' "$dest/godot"
}

# version.txt is the template build key: Godot installs and looks up templates
# under export_templates/<that key> (GODOT_VERSION_FULL_CONFIG). It is not the
# editor's full "4.x.official.<commit>" string.
install_templates() {
  local tag="$1"
  local key
  key="$(unzip -p "$DOWNLOADS/Godot_v${tag}_export_templates.tpz" templates/version.txt | tr -d '[:space:]')"
  if [ -z "$key" ]; then
    echo "templates for $tag have an empty version.txt" >&2
    exit 1
  fi
  local dest="$EXPORT_TEMPLATES/$key"
  if [ ! -f "$dest/version.txt" ] || [ "$(tr -d '[:space:]' < "$dest/version.txt")" != "$key" ]; then
    say "extract templates for $tag -> $key"
    local tmp
    tmp="$(mktemp -d)"
    unzip -q -o "$DOWNLOADS/Godot_v${tag}_export_templates.tpz" -d "$tmp"
    rm -rf "$dest"
    mkdir -p "$EXPORT_TEMPLATES"
    mv "$tmp/templates" "$dest"
    rm -rf "$tmp"
  fi
  printf '%s' "$key"
}

# Full git hash baked into official editor and template binaries. The short
# hash in `godot --version` is its prefix.
full_commit() {
  local bin="$1" short="$2"
  python3 - "$bin" "$short" <<'PY'
import sys
data = open(sys.argv[1], "rb").read()
short = sys.argv[2].encode()
start = 0
while True:
    i = data.find(short, start)
    if i < 0:
        sys.exit(2)
    chunk = data[i:i + 40]
    try:
        text = chunk.decode()
    except UnicodeDecodeError:
        start = i + 1
        continue
    if len(text) == 40 and all(c in "0123456789abcdef" for c in text):
        sys.stdout.write(text)
        sys.exit(0)
    start = i + 1
PY
}

check_provenance() {
  local label="$1" bin="$2" key="$3"
  local editor_version short editor_commit template_commit
  editor_version="$("$bin" --version | tr -d '[:space:]')"
  say "$label editor: $editor_version"
  say "$label template build key: $key"
  if [[ "$editor_version" != "$key.official."* ]]; then
    note_fail "$label editor version $editor_version does not match template key $key"
    return
  fi
  short="${editor_version##*.}"
  if ! editor_commit="$(full_commit "$bin" "$short")"; then
    note_fail "$label editor binary has no commit hash starting $short"
    return
  fi
  if ! template_commit="$(full_commit "$EXPORT_TEMPLATES/$key/linux_release.arm64" "$short")"; then
    note_fail "$label linux_release.arm64 template has no commit hash starting $short"
    return
  fi
  say "$label editor commit: $editor_commit"
  say "$label template commit: $template_commit"
  if [ "$editor_commit" != "$template_commit" ]; then
    note_fail "$label editor commit $editor_commit != template commit $template_commit"
  else
    say "$label provenance: editor, template key and template binary agree"
  fi
  python3 - "$label" "$EXPORT_TEMPLATES/$key" <<'PY' | tee -a "$REPORT" >&2
import io, sys, zipfile
from pathlib import Path
label, root = sys.argv[1], Path(sys.argv[2])

def emit(size, name):
    print(f"LIB {label} {size} {name}")

emit((root / "linux_release.arm64").stat().st_size, "template/linux_release.arm64")
emit((root / "linux_debug.arm64").stat().st_size, "template/linux_debug.arm64")

def zip_members(blob, wanted):
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        for info in z.infolist():
            if info.filename in wanted:
                emit(info.file_size, info.filename)

src = zipfile.ZipFile(root / "android_source.zip")
for member in (
    "libs/release/godot-lib.template_release.aar",
    "libs/debug/godot-lib.template_debug.aar",
):
    wanted = {
        "jni/arm64-v8a/libgodot_android.so",
        "jni/arm64-v8a/libc++_shared.so",
    }
    # Prefix the aar role so release and debug don't collide in the report.
    role = "release" if "release" in member else "debug"
    data = src.read(member)
    with zipfile.ZipFile(io.BytesIO(data)) as aar:
        for info in aar.infolist():
            if info.filename in wanted:
                emit(info.file_size, f"android/{role}/{info.filename}")

ios = zipfile.ZipFile(root / "ios.zip")
for name in (
    "libgodot.ios.release.xcframework/ios-arm64/libgodot.a",
    "libgodot.ios.debug.xcframework/ios-arm64/libgodot.a",
):
    emit(ios.getinfo(name).file_size, f"ios/{name}")

gradle = src.read("config.gradle").decode()
wrapper = src.read("gradle/wrapper/gradle-wrapper.properties").decode()
keys = (
    "androidGradlePlugin",
    "compileSdk",
    "minSdk",
    "targetSdk",
    "buildTools",
    "javaVersion",
    "ndkVersion",
    "openxrLoaderVersion",
    "openxrVendorsVersion",
)
print(f"TOOLCHAIN {label}")
# Only the versions map. Matching the key anywhere also prints the helper
# functions that mention minSdk and targetSdk.
for line in gradle.splitlines():
    stripped = line.strip()
    if any(stripped.startswith(k) for k in keys):
        print("  " + stripped.rstrip(","))
for line in wrapper.splitlines():
    if line.startswith("distributionUrl="):
        print("  " + line.strip())
PY
}

prepare_seed() {
  local vendors gut
  vendors="$(just_value openxr_vendors)"
  gut="$(just_value gut_version)"
  if [ -z "$vendors" ] || [ -z "$gut" ]; then
    echo "could not read addon pins from the justfile" >&2
    exit 1
  fi
  say "project copy (vendors $vendors, gut $gut)"
  rm -rf "$SEED"
  mkdir -p "$SEED"
  tar -C "$ROOT" \
    --exclude .git \
    --exclude .godot \
    --exclude build \
    --exclude addons/gut \
    --exclude addons/godotopenxrvendors \
    -cf - . | tar -C "$SEED" -xf -

  local addon_cache="$CACHE/addons"
  mkdir -p "$addon_cache"
  if [ ! -d "$addon_cache/godotopenxrvendors" ]; then
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/addon.zip" \
      "https://github.com/GodotVR/godot_openxr_vendors/releases/download/${vendors}/godotopenxrvendorsaddon.zip"
    unzip -q "$tmp/addon.zip" -d "$tmp"
    mv "$tmp/asset/addons/godotopenxrvendors" "$addon_cache/godotopenxrvendors"
    rm -rf "$tmp"
  fi
  if [ ! -d "$addon_cache/gut" ]; then
    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/gut.zip" \
      "https://github.com/bitwes/Gut/archive/refs/tags/v${gut}.zip"
    unzip -q "$tmp/gut.zip" -d "$tmp"
    mv "$tmp/Gut-${gut}/addons/gut" "$addon_cache/gut"
    rm -rf "$tmp"
  fi
  mkdir -p "$SEED/addons"
  cp -a "$addon_cache/godotopenxrvendors" "$SEED/addons/"
  cp -a "$addon_cache/gut" "$SEED/addons/"

  if [ -n "${ANDROID_HOME:-}" ] && [ "${GODOT_TRIAL_SKIP_ANDROID:-}" != "1" ]; then
    say "build xr_webview shim"
    (
      cd "$SEED/addons/xr_webview/android"
      JAVA_HOME="$JAVA_HOME" ANDROID_HOME="$ANDROID_HOME" GRADLE_USER_HOME="$CACHE/gradle" \
        ./gradlew assembleRelease --console=plain
    )
    mkdir -p "$SEED/android/plugins"
    cp "$SEED/addons/xr_webview/android/build/outputs/aar/xr-webview-release.aar" "$SEED/android/plugins/"
    cp "$SEED/addons/xr_webview/android/XRWebView.gdap" "$SEED/android/plugins/"
  fi
}

engine_env() {
  # Each run gets its own HOME so a beta editor cannot rewrite the stable
  # editor's config. Templates for every version live next to each other
  # under that HOME; Godot selects the subdirectory named by its own build
  # key, so a 4.7 editor cannot pick up the beta templates as its own.
  local home="$1"
  shift
  mkdir -p "$home/.config" "$home/.cache" "$home/.local/share/godot"
  HOME="$home" \
    XDG_CONFIG_HOME="$home/.config" \
    XDG_CACHE_HOME="$home/.cache" \
    XDG_DATA_HOME="$home/.local/share" \
    GRADLE_USER_HOME="$CACHE/gradle" \
    JAVA_HOME="$JAVA_HOME" \
    ANDROID_HOME="${ANDROID_HOME:-}" \
    GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${KEYSTORE:-}" \
    GODOT_ANDROID_KEYSTORE_DEBUG_USER="${KEY_USER:-}" \
    GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${KEY_PASS:-}" \
    GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${KEYSTORE:-}" \
    GODOT_ANDROID_KEYSTORE_RELEASE_USER="${KEY_USER:-}" \
    GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${KEY_PASS:-}" \
    "$@"
}

link_templates() {
  local home="$1"
  mkdir -p "$home/.local/share/godot"
  ln -sfn "$EXPORT_TEMPLATES" "$home/.local/share/godot/export_templates"
}

run_logged() {
  local log="$1"
  shift
  set +e
  "$@" >"$log" 2>&1
  last_ec=$?
  set -e
}

scan_script_errors() {
  local log="$1"
  if grep -E "SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Nonexistent function|Nonexistent signal" "$log"; then
    return 1
  fi
  return 0
}

run_project() {
  local label="$1" bin="$2" key="$3"
  local work="$CACHE/work/$label"
  local home="$CACHE/home/$label"
  rm -rf "$work" "$home"
  mkdir -p "$CACHE/work" "$CACHE/home"
  cp -a "$SEED" "$work"
  link_templates "$home"
  say "$label import ($key)"
  local log="$work/import.log"
  run_logged "$log" engine_env "$home" "$bin" --headless --path "$work" --import
  say "$label import exit $last_ec (134 is the known headless teardown abort)"
  if ! find "$work/.godot/imported" -type f 2>/dev/null | grep -q .; then
    note_fail "$label import produced no resources"
    tail -n 40 "$log" | tee -a "$REPORT" >&2 || true
    return
  fi
  say "$label imported $(find "$work/.godot/imported" -type f | wc -l) resources"
  if ! scan_script_errors "$log"; then
    note_fail "$label import log has script errors"
  fi
  if ! diff -q "$SEED/project.godot" "$work/project.godot" >/dev/null; then
    say "$label project.godot changed in the trial copy only:"
    diff -u "$SEED/project.godot" "$work/project.godot" | tee -a "$REPORT" || true
  else
    say "$label project.godot unchanged"
  fi
  if ! diff -q "$SEED/export_presets.cfg" "$work/export_presets.cfg" >/dev/null; then
    say "$label export_presets.cfg changed in the trial copy only:"
    diff -u "$SEED/export_presets.cfg" "$work/export_presets.cfg" | tee -a "$REPORT" || true
  fi

  say "$label regression suite"
  log="$work/gut.log"
  run_logged "$log" engine_env "$home" "$bin" --headless --path "$work" \
    -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit -gprefix=test_
  say "$label gut exit $last_ec"
  if ! grep -q "All tests passed" "$log"; then
    note_fail "$label regression suite failed"
    tail -n 80 "$log" | tee -a "$REPORT" >&2 || true
  fi
  if grep -q "Ignoring script" "$log"; then
    note_fail "$label GUT skipped a test script"
    grep "Ignoring script" "$log" | tee -a "$REPORT" >&2 || true
  fi
  local expected actual
  expected="$(find "$work/test" -maxdepth 1 -name 'test_*.gd' | wc -l | tr -d ' ')"
  actual="$(sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\r$//' "$log" \
    | sed -nE 's/^[[:space:]]*Scripts[[:space:]]+([0-9]+)[[:space:]]*$/\1/p' \
    | tail -1)"
  say "$label test scripts on disk: ${expected}, scripts GUT ran: ${actual:-none}"
  if [ -z "$actual" ] || [ "$expected" != "$actual" ]; then
    note_fail "$label expected $expected test scripts, GUT ran ${actual:-none}"
  fi

  say "$label smoke"
  log="$work/smoke.log"
  run_logged "$log" engine_env "$home" "$bin" --headless --path "$work" --quit-after 1200
  say "$label smoke exit $last_ec"
  if ! scan_script_errors "$log"; then
    note_fail "$label smoke test has script errors"
    grep -E "SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Nonexistent" "$log" | tee -a "$REPORT" >&2 || true
  fi

  mkdir -p "$work/build"
  say "$label export Steam Frame"
  log="$work/export-frame.log"
  run_logged "$log" engine_env "$home" "$bin" --headless --path "$work" \
    --export-release "Steam Frame" "$work/build/paddlequest.arm64"
  say "$label steam frame export exit $last_ec"
  if [ ! -s "$work/build/paddlequest.arm64" ]; then
    note_fail "$label Steam Frame export produced no binary"
    tail -n 40 "$log" | tee -a "$REPORT" >&2 || true
  else
    local desc
    desc="$(file -b "$work/build/paddlequest.arm64")"
    say "$label steam frame: $(stat -c %s "$work/build/paddlequest.arm64") bytes ($desc)"
    if ! grep -q "ARM aarch64" <<<"$desc"; then
      note_fail "$label Steam Frame binary is not ARM aarch64: $desc"
    fi
  fi

  if [ -z "${ANDROID_HOME:-}" ] || [ "${GODOT_TRIAL_SKIP_ANDROID:-}" = "1" ]; then
    say "$label Quest APK skipped (no ANDROID_HOME, or GODOT_TRIAL_SKIP_ANDROID=1)"
    return
  fi
  say "$label export Quest APK"
  log="$work/export-apk.log"
  # Install and export stay one invocation. Split apart, the install command
  # has nothing left to make Godot quit and the editor sits in the project.
  run_logged "$log" engine_env "$home" "$bin" --headless --path "$work" \
    --install-android-build-template \
    --export-release "Quest" "$work/build/paddleball-release.apk"
  say "$label apk export exit $last_ec"
  if [ ! -s "$work/build/paddleball-release.apk" ]; then
    note_fail "$label Quest export produced no APK"
    tail -n 60 "$log" | tee -a "$REPORT" >&2 || true
    return
  fi
  say "$label apk: $(stat -c %s "$work/build/paddleball-release.apk") bytes"
  if ! python3 - "$label" "$work/build/paddleball-release.apk" <<'PY' | tee -a "$REPORT" >&2
import sys, zipfile
label, path = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(path) as z:
    sos = [i for i in z.infolist() if i.filename.endswith(".so")]
    if not sos:
        sys.exit(1)
    for info in sos:
        print(f"PACKAGED {label} {info.file_size} {info.compress_size} {info.filename}")
PY
  then
    note_fail "$label APK contains no native libraries"
  fi
  local count
  count="$(unzip -p "$work/build/paddleball-release.apk" 'classes*.dex' | grep -ac XRWebViewBridge || true)"
  if [ "$count" -eq 0 ]; then
    note_fail "$label APK dex has no XRWebViewBridge"
  else
    say "$label XRWebViewBridge dex references: $count"
  fi
  local aapt2 tree
  aapt2="$(find "$ANDROID_HOME/build-tools" -name aapt2 -type f | sort | tail -1)"
  if [ -n "$aapt2" ]; then
    if ! tree="$("$aapt2" dump xmltree --file AndroidManifest.xml "$work/build/paddleball-release.apk" 2>"$work/aapt.err")"; then
      note_fail "$label aapt2 could not read the manifest"
    elif ! grep -q "com.oculus.intent.category.VR" <<<"$tree" || ! grep -q "questpro" <<<"$tree"; then
      note_fail "$label manifest is missing Quest VR entry points"
    else
      say "$label manifest declares Quest VR entry points"
    fi
  fi
}

assert_repo_untouched() {
  local dirty
  dirty="$(git -C "$ROOT" status --porcelain -- project.godot export_presets.cfg .github/workflows/build.yml .devcontainer/Dockerfile .devcontainer/devcontainer.json)"
  if [ -n "$dirty" ]; then
    note_fail "trial wrote into the stable pin files:"
    printf '%s\n' "$dirty" | tee -a "$REPORT" >&2
  else
    say "stable pin files untouched"
  fi
}

main() {
  mkdir -p "$CACHE"
  : >"$REPORT"
  if [ -z "${JAVA_HOME:-}" ]; then
    if ! command -v java >/dev/null; then
      echo "java is required to build the Android shim and export the APK" >&2
      exit 1
    fi
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
    export JAVA_HOME
  fi
  local stable_version stable_tag
  stable_version="$(read_stable_version)"
  stable_tag="${stable_version}-stable"
  say "stable pin: ${stable_version} (workflow and devcontainer)"
  say "trial: ${TRIAL_TAG} from ${TRIAL_REPO}, official binaries, not a source build"
  say "Python floor: not checked. GH-122597 (3.9 -> 3.10) applies when compiling the engine; this trial does not compile it."
  say "cache: $CACHE"

  fetch_release "$TRIAL_REPO" "$TRIAL_TAG"
  local beta_bin beta_key
  beta_bin="$(install_editor "$TRIAL_TAG")"
  beta_key="$(install_templates "$TRIAL_TAG")"
  check_provenance "beta" "$beta_bin" "$beta_key"

  local stable_bin="" stable_key=""
  if [ "${GODOT_TRIAL_SKIP_STABLE:-}" != "1" ]; then
    fetch_release "godotengine/godot" "$stable_tag"
    stable_bin="$(install_editor "$stable_tag")"
    stable_key="$(install_templates "$stable_tag")"
    check_provenance "stable" "$stable_bin" "$stable_key"
  fi

  if [ -n "${ANDROID_HOME:-}" ] && [ "${GODOT_TRIAL_SKIP_ANDROID:-}" != "1" ]; then
    KEY_USER="androiddebugkey"
    KEY_PASS="android"
    KEYSTORE="$CACHE/debug.keystore"
    if [ ! -f "$KEYSTORE" ]; then
      keytool -keyalg RSA -genkeypair -alias "$KEY_USER" \
        -keypass "$KEY_PASS" -storepass "$KEY_PASS" \
        -dname "CN=Android Debug,O=Android,C=US" -validity 10000 \
        -keystore "$KEYSTORE"
    fi
    say "throwaway keystore: $KEYSTORE (same key for both exports)"
  fi

  prepare_seed
  run_project "beta" "$beta_bin" "$beta_key"
  if [ -n "$stable_bin" ]; then
    run_project "stable" "$stable_bin" "$stable_key"
  fi
  assert_repo_untouched

  say "summary"
  grep -E '^(== |LIB |PACKAGED |TOOLCHAIN|  )' "$REPORT" | tee /dev/stderr >/dev/null || true
  if [ "$fail" -ne 0 ]; then
    say "trial finished with failures"
    exit 1
  fi
  say "trial finished clean"
}

main "$@"
