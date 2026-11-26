# Godot 4.8 beta 2 trial

Opt-in check of this project on Godot 4.8 beta 2. The editor, CI and exports
stay on the stable pin.

## Pin

| Where | What |
|---|---|
| `.github/workflows/build.yml` | `GODOT_VERSION: 4.7.2` |
| `.devcontainer/Dockerfile` | `ARG GODOT_VERSION=4.7.2` |
| `project.godot` | `config/features` includes `4.7` |
| README requirements | Godot 4.7.2 with matching templates |

4.7.2 is the latest 4.x stable (GitHub `godotengine/godot` releases, 1 Nov 2026).
3.6.3-stable is the current 3.x line and is not this project's pin. Nothing
here bumps 4.7.2.

## How to run it

```bash
just trial-48
```

That is `tools/godot_48_trial.sh`. It downloads the official 4.8-beta2 editor
and export templates into `~/.cache/paddlequest/godot-trial`, checks them
against the published SHA-512 sums, and runs import, the GUT suite, the smoke
run and both release exports on a copy of the project. With
`GODOT_TRIAL_SKIP_STABLE` unset it does the same exports on the stable pin so
the sizes are like-for-like. `ANDROID_HOME` must be set for the Quest APK;
without it the script still does the Linux arm64 export.

The script reads the stable version from the workflow and refuses to run if
the Dockerfile pin disagrees. It does not put a `godot` binary on `PATH`, and
it checks at the end that `project.godot`, `export_presets.cfg`, the workflow
and the devcontainer are unmodified.

CI: **Godot 4.8 trial** (`godot-4.8-trial.yml`, version input), `workflow_dispatch` only. It is not part of
`build.yml` and does not gate pull requests.

This trial uses the official binaries. It does not compile Godot, so it does
not check the engine-build Python floor (3.9 to 3.10, GH-122597). That check
belongs on a from-source build, which this path does not do.

## Provenance

Measured 1 Nov 2026 from the official zips. The template build key is the
contents of `version.txt`, which is the directory Godot looks up
(`GODOT_VERSION_FULL_CONFIG`). The editor's `--version` string is that key
plus `.official.` and the short commit. The full commit is the 40-character
hash in both the editor binary and `linux_release.arm64`.

| | 4.7.2 stable | 4.8-beta2 |
|---|---|---|
| Editor | `4.7.2.stable.official.ed1daf0bf` | `4.8.beta2.official.cafc17a19` |
| Template build key | `4.7.2.stable` | `4.8.beta2` |
| Commit in editor and template | `ed1daf0bf001b61586d9930840f2f1394092c079` | `cafc17a192acf67903910a68aeb3c076c0907a4b` |
| Pairing | editor, key and template binary agree | editor, key and template binary agree |

Host toolchain the Android template declares (same values the export actually
used: JDK 21 on the machine, Java 17 bytecode, SDK 36, build-tools 36.1.0):

| | 4.7.2 stable | 4.8-beta2 |
|---|---|---|
| Android Gradle Plugin | 8.6.1 | 8.13.2 |
| Gradle wrapper | 8.11.1 | 8.14.5 |
| compileSdk / minSdk / targetSdk | 36 / 24 / 36 | 36 / 24 / 36 |
| build-tools | 36.1.0 | 36.1.0 |
| Java | 17 | 17 |
| NDK | 29.0.14206865 | 29.0.14206865 |
| OpenXR loader (template) | 1.1.53 | 1.1.63 |

No new JDK, SDK, NDK or build-tools requirement versus the stable template.
AGP and the Gradle wrapper moved inside the template; the export downloaded
them. The project's shim stays on AGP 8.6.1 / Gradle 8.11.1, matching the
stable template, and the prebuilt AAR still landed in both APKs.

`openxrVendorsVersion` in the template config is `4.3.0-stable` on 4.7.2 and
`5.2.0-rc1-SNAPSHOT` on 4.8-beta2. The APK did not take that coordinate: both
exports packaged the project's pinned `godotopenxrvendors` 5.1.0-stable, and
`libgodotopenxrvendors.so` is byte-identical.

## Export sizes

Same project copy, same throwaway keystore, same presets. Quest is arm64-v8a
only, native libraries stored uncompressed (`compress_native_libraries` is
off). Both exports include GUT because the trial, like CI, installs it before
export and the preset exports all resources. The delta is the engine, not the
addon.

| Artifact | 4.7.2 stable | 4.8-beta2 | beta − stable |
|---|---:|---:|---:|
| Quest release APK | 84,991,031 | 78,721,805 | −6,269,226 (−7.4%) |
| Steam Frame `paddlequest.arm64` | 68,710,168 | 70,667,672 | +1,957,504 (+2.8%) |

Packaged native libraries inside the APK (`lib/arm64-v8a`, uncompressed size
equals compressed size):

| Library | 4.7.2 stable | 4.8-beta2 | beta − stable |
|---|---:|---:|---:|
| `libgodot_android.so` | 71,114,944 | 64,818,536 | −6,296,408 |
| `libopenxr_loader.so` | 1,656,736 | 1,662,216 | +5,480 |
| `libc++_shared.so` | 1,374,336 | 1,374,336 | 0 (identical) |
| `libgodotopenxrvendors.so` | 3,898,192 | 3,898,192 | 0 (identical) |

The APK shrink tracks `libgodot_android.so`. There is no Quest package-size
regression. The Steam Frame binary grew by almost exactly the growth of the
`linux_release.arm64` template (67,079,432 → 69,036,184, +1,956,752). Both
binaries are stripped ARM aarch64. The beta one is a PIE linked for GNU/Linux
3.7.0; the stable one is a non-PIE linked for GNU/Linux 5.15.0.

Template libraries that this project does not export, for the same commits.
There is no iOS preset, so these are not game packages:

| Library | 4.7.2 stable | 4.8-beta2 | beta − stable |
|---|---:|---:|---:|
| `linux_release.arm64` | 67,079,432 | 69,036,184 | +1,956,752 |
| `libgodot.ios.release` arm64 `.a` | 188,887,256 | 170,340,024 | −18,547,232 |

## Headless results

Both engines, exit 0, on a copy of the tree. `project.godot` and
`export_presets.cfg` were not rewritten. 62 resources imported. GUT ran all
14 `test_*.gd` files and reported all tests passed. The smoke run had no
`SCRIPT ERROR`, parse error or invalid call. No GDScript change was required.

Both exports produced a non-empty artifact. Each Quest APK has
`XRWebViewBridge` in the dex (2 references) and a manifest with
`com.oculus.intent.category.VR` and `questpro`. `godotopenxrvendors` 5.1.0
(`compatibility_minimum` 4.6) loaded far enough to package its arm64 library
on 4.8-beta2.

Log lines that are not script breakages:

- OpenXR fails to enumerate extensions and the game runs flat. Same on both
  engines; this machine has no runtime. The stable CI smoke treats that as
  success.
- `xr/openxr/extensions/hand_tracking` is missing. Same warning on both
  engines, from the vendors addon, before any game script runs.
- Steam Frame export on both engines logs `Cannot set object script` while
  packing a GUT scene (`gut_loader_the_scene`). The binary is still written.
  Pre-existing, not a 4.8 break.
- 4.8-beta2 only, after the APK gradle build has already finished:
  `EditorSettings not instantiated yet` for
  `export/android/shutdown_adb_on_exit`. The APK was complete (exit 0, dex
  and manifest checks passed). Editor teardown, not a game script.

## What still needs a person

Headless cannot boot a headset. The device checklist is
`docs/godot-4.8-beta2-device-trial.md`. Install a trial build, not the stable
CI artifact. This repo has no iOS preset, and the shipped renderer is Mobile,
so the Compatibility-renderer multiply check and any iOS pass are not things
this trial could export.
