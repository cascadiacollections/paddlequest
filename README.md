# Paddle Quest

A solo wall-bounce paddle-ball demo for Meta Quest 3 / 3S, built with Godot 4.7 and OpenXR.

Your right controller is the paddle. Serve, keep the ball off the back of the court,
and every clean return off the front wall extends the rally and speeds the ball up.

## Requirements

Already set up on this machine, listed for a fresh clone:

- Godot **4.7.2** with matching export templates
- JDK **21** (Godot's Gradle build does not support JDK 25) — `mise install java@temurin-21`
- Android SDK at `~/Android/Sdk`
- A debug keystore at `~/.local/share/godot/keystores/debug.keystore`
- `addons/godotopenxrvendors` — [OpenXR vendors plugin](https://github.com/GodotVR/godot_openxr_vendors) 5.1.0-stable (Godot 4.6+),
  not checked in. Run **`just setup`** after cloning to fetch it.

The export preset enables the **Meta** vendor plugin and Quest 3 support only. The generic
Khronos loader also boots on a modern Quest, but the Meta path is what gets you the
vendor loader and the `com.oculus.intent.category.VR` launch category.

## Commands

```bash
just play        # flat on the desktop, mouse moves the paddle
just check       # headless smoke test of the rally loop
just build       # debug APK -> build/paddleball.apk
just deploy      # build + adb install
just log         # adb logcat, filtered
just build-frame # Steam Frame binary -> build/paddlequest.arm64
just version     # what version a build would identify as
```

`--xr-mode off` is passed for desktop runs on purpose: without it Godot probes for a
headset, fails, and blocks startup on a modal "no HMD detected" dialog.

## Controls

| Input | Action |
|---|---|
| Right controller | Paddle |
| Left thumbstick, left/right | Strafe (clamped to the court) |
| Left thumbstick, down / up | Crouch / stand |
| Right thumbstick, up / down | Move forward / back |
| A, B or Menu button | Re-serve immediately |

Flat-mode equivalents: mouse moves the paddle, arrow keys strafe and crouch,
PageUp/PageDown move forward and back, Space re-serves, Esc quits.

Hitting one of the three glowing panels on the front wall is worth bonus
points; it goes dark and reappears elsewhere.

The rally is pitched at roughly 1.25m — chest height rather than head height —
so that the paddle and the ball stay in the headset's field of view together.
Raising `WallTarget` and `ServePoint` pushes the action up out of view.

## Headset setup for development

Applied over adb, verified on a Quest Pro (OS 51503870024400340):

```bash
# Stop the headset sleeping the moment it leaves your head, which drops adb
# mid-deploy. screen_off_timeout is already 24h; this is the lever that matters.
adb shell settings put global stay_on_while_plugged_in 7   # revert with 0

# 256 KiB of logcat is about six seconds of Godot output.
adb logcat -G 16M                                          # resets on reboot
```

Wireless deploys work but cost ~48s against ~6s over USB, because the headset
associates to the 2.4GHz band. Worth moving it to 5GHz before relying on it.

With both USB and Wi-Fi transports connected, adb will not guess which to use:

```bash
ADB_TARGET=192.168.1.121:5555 just deploy
```

Things that do **not** work, despite appearing in most guides: the
`debug.oculus.cpuLevel` / `gpuLevel` / `foveation.level` properties accept any
value you hand them, including nonsense, without the runtime honouring them.
The `com.oculus.vrpowermanager.prox_close` broadcast returns `result=0` with no
receiver. Treat all of those as removed.

## Targets

| Target | Preset | Output | Notes |
|---|---|---|---|
| Quest 3 / 3S / Pro | `Quest` (Android, arm64) | `.apk` | Meta vendor plugin, Gradle build, needs a keystore |
| Steam Frame | `Steam Frame` (Linux, arm64) | single ELF binary | SteamOS on ARM; no vendor plugin, no JDK, no SDK |

Steam Frame runs a VR build of SteamOS on ARM and accepts either a Linux
arm64 or an Android arm64 build. This project uses **Linux arm64**: it is the
SteamOS-native path and it avoids carrying a second Android preset that
differs from the Quest one only in having the Meta plugin switched off. The
`linux_release.arm64` template ships in the same `export_templates` bundle the
Quest build already needs.

The game scripts are engine-generic - nothing under `scripts/` knows which
headset it is on. Everything device-specific lives in `export_presets.cfg`,
`openxr_action_map.tres`, and `PROFILE_GRIPS` in `scripts/paddle.gd`.

### Per-device grip offsets

OpenXR defines the grip pose relative to the physical controller, so a
differently shaped controller puts the hand somewhere else relative to the
blade. `scripts/paddle.gd` resolves its offset from the bound interaction
profile, via the `profile_changed` signal on `XRController3D`.

The Touch numbers are measured. **The Steam Frame entry is not** - it
currently inherits the Touch values so the paddle lands in roughly the right
place, and wants a pass with the headset on. This does not look broken when
it is wrong; the paddle just sits slightly off in the hand.

Frame is also asymmetric in a way Touch is not: A, B, X and Y all live on the
right controller and the left gets a dpad, so there is no left-hand X/Y to
pair with. A/X bind together as the lower pair and B/Y as the upper, which
keeps "any face button re-serves" true on both devices.

## Frame pacing

Physics runs at 90Hz. The headsets do not agree: Quest Pro is 90, Quest 3
offers 120, Steam Frame offers 72/80/90/120 and an experimental 144. No tick
rate divides all of those, so rather than chase the display,
`physics/common/physics_interpolation` is on and the renderer runs at whatever
the compositor paces it at.

Two things to know about that:

- `XRCamera3D` and `XRNode3D` force their own interpolation mode to OFF in
  their constructors, so head and controller tracking is unaffected.
- Interpolation costs up to one physics frame of latency on the paddle, which
  is hand-held. That trade is **not yet verified on hardware.**

### Measuring it

There is no recorded frame budget for this project yet, which means every
performance claim here is inference. Before optimizing anything further,
capture a 60-second rally on-device and write the numbers down:

```bash
adb shell dumpsys SurfaceFlinger --latency   # or use OVR Metrics Tool
```

Foveation is the largest unclaimed win and is currently off - see
`xr/openxr/foveation_level` in `project.godot` for why. Steam Frame has eye
tracking and a completely different driver stack, so it is worth re-testing
there rather than assuming the Godot-side path is broken generally.

## The paddle mesh

`assets/paddle.glb` is generated, not hand-modelled - `just paddle` rebuilds it
from `tools/make_paddle.py` with Blender headless, so the shape is a diff
rather than a binary someone has to open a GUI to change.

The axis mapping is the fiddly part and is asserted rather than assumed:
Blender is Z-up, glTF and Godot are Y-up, and the exporter maps Blender
(X, Y, Z) to glTF (X, Z, -Y). The blade therefore has to be thin along
Blender's Y so its face normal lands on Godot's Z, with the handle running out
along Blender -Y to reach the hand at Godot +Z. Verified by loading the result
and checking its AABB: X +/-0.17, Y +/-0.19, Z -0.014 to 0.209.

Collision stays a plain box. A convex hull of the blade would catch the handle
and the ball would bounce off the grip.

## CI and containers

`.github/workflows/build.yml` exports a release APK on every push, caching
Godot and its export templates, and asserts the manifest still declares the
Quest VR entry points before uploading the artifact.

`.devcontainer/` pins Godot 4.7.2, JDK 21 and the Android SDK. It builds and
was verified to produce a working toolchain, but note it cannot help with the
headset half of the loop - deploying and testing still needs local USB.

Every build is stamped with a version derived from the run number and
`git describe` (`tools/stamp_version.py`); before that, every build this
project produced called itself version 1, and two of those cannot coexist
anywhere that keys on version code. Release signing takes an
`ANDROID_KEYSTORE_BASE64` secret when one is configured and falls back to a
throwaway key otherwise, with a warning in the log - a throwaway-signed APK
sideloads fine but cannot update an install made by any other build.

## Licensing

Code and the project's own assets are MIT; see `LICENSE`.

`ASSETS.md` records where every binary in the repository came from and what
licence it carries. New third-party assets must be **CC0 or CC-BY only** -
the custom "free" licences on TurboSquid, CGTrader and Free3D generally
forbid redistribution, which is exactly what committing one here does.

## How it fits together

| File | Role |
|---|---|
| `scenes/main.tscn` | Court, XR rig, ball, paddle, score label |
| `scripts/game.gd` | Rally state, serving, miss handling, score readout |
| `scripts/ball.gd` | Bounce physics, swing transfer, speed floor and ceiling |
| `scripts/paddle.gd` | Drives the kinematic paddle from the controller; samples swing velocity |
| `scripts/locomotion.gd` | Strafe, crouch and forward motion on the XR origin |
| `scripts/targets.gd` | Bonus panels on the front wall that relocate when hit |
| `scripts/xr_boot.gd` | Brings up OpenXR, falls back to flat rendering |

Two details that are easy to get wrong in VR and are handled deliberately:

- The paddle is an `AnimatableBody3D` whose transform is written in `_physics_process`
  rather than being parented to the controller. Parenting renders in the right place but
  leaves the collider behind.
- A kinematic body reports zero velocity, so `paddle.gd` samples its own world position
  across frames to derive a swing velocity. Without it a hard swing and a gentle tap
  send the ball at exactly the same speed.
- The serve is aimed ballistically rather than straight at `WallTarget`. At this
  gravity the ball drops most of a metre crossing the court, which had the whole
  rally arriving around knee height and below the wall targets entirely.
- A ball bouncing straight up and down never reaches the front wall or the miss zone,
  so the rally can neither score nor end. `ball.gd` keeps a floor on horizontal speed,
  and `game.gd` re-serves after `stall_timeout` seconds without a scoring hit.
