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
| A, B or Menu button | Re-serve immediately |

Flat-mode equivalents: mouse moves the paddle, arrow keys strafe and crouch,
Space re-serves, Esc quits.

The rally is pitched at roughly 1.25m — chest height rather than head height —
so that the paddle and the ball stay in the headset's field of view together.
Raising `WallTarget` and `ServePoint` pushes the action up out of view.

## How it fits together

| File | Role |
|---|---|
| `scenes/main.tscn` | Court, XR rig, ball, paddle, score label |
| `scripts/game.gd` | Rally state, serving, miss handling, score readout |
| `scripts/ball.gd` | Bounce physics, swing transfer, speed floor and ceiling |
| `scripts/paddle.gd` | Drives the kinematic paddle from the controller; samples swing velocity |
| `scripts/locomotion.gd` | Left-stick strafe and crouch on the XR origin |
| `scripts/xr_boot.gd` | Brings up OpenXR, falls back to flat rendering |

Two details that are easy to get wrong in VR and are handled deliberately:

- The paddle is an `AnimatableBody3D` whose transform is written in `_physics_process`
  rather than being parented to the controller. Parenting renders in the right place but
  leaves the collider behind.
- A kinematic body reports zero velocity, so `paddle.gd` samples its own world position
  across frames to derive a swing velocity. Without it a hard swing and a gentle tap
  send the ball at exactly the same speed.
- A ball bouncing straight up and down never reaches the front wall or the miss zone,
  so the rally can neither score nor end. `ball.gd` keeps a floor on horizontal speed,
  and `game.gd` re-serves after `stall_timeout` seconds without a scoring hit.
