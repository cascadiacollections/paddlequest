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
just play      # flat on the desktop, mouse moves the paddle
just check     # headless smoke test of the rally loop
just build     # debug APK -> build/paddleball.apk
just deploy    # build + adb install
just log       # adb logcat, filtered
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

## CI and containers

`.github/workflows/build.yml` exports a release APK on every push, caching
Godot and its export templates, and asserts the manifest still declares the
Quest VR entry points before uploading the artifact.

`.devcontainer/` pins Godot 4.7.2, JDK 21 and the Android SDK. It builds and
was verified to produce a working toolchain, but note it cannot help with the
headset half of the loop - deploying and testing still needs local USB.

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
