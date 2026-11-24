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
just sounds      # regenerate audio/*.wav from tools/make_sounds.py
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
| Right thumbstick, left/right | Snap turn |
| A or B button | Re-serve immediately |
| Menu button | Open / close the pause menu |

Flat-mode equivalents: mouse moves the paddle, arrow keys strafe and crouch,
PageUp/PageDown move forward and back, Tab/Shift-Tab snap turn, Space
re-serves. Esc quits a flat run; in the headset it opens the menu instead,
since there is nowhere to quit *to*.

### The pause menu

Menu button, or Esc in the headset. Thumbstick to move, trigger or A to
choose. It suspends the rally and locks locomotion, but deliberately does
**not** call `get_tree().paused` - that would stop `XRCamera3D` too and lock
the rendered world to your head, which is the fastest way to make someone
ill. Tracking carries on as normal.

| Row | Does |
|---|---|
| Resume | Closes the menu; the rally is where you left it |
| Recenter | `XRServer.center_on_hmd`, for seated play |
| Comfort vignette | Tunnelling while you move (on by default) |
| Snap turn | Snap vs. smooth turning (snap by default) |
| Seated | Drops the origin so your head still reaches rally height |
| Quit | Leaves the game |

### Comfort

The defaults are the comfortable ones. Someone who needs tunnelling should
not have to find the menu before they can play without feeling ill; someone
who does not can turn it off in a few seconds. Settings persist in
`user://progress.cfg` alongside the high score.

Tunnelling closes a soft vignette in while you are moved or turned
artificially. Peripheral optical flow your inner ear disagrees with is what
makes people ill, so narrowing the periphery exactly while that flow is
happening removes most of it without taking the movement away. **Its
appearance has not been checked in a headset** - `inner_radius` and
`softness` on `shaders/vignette.gdshader` are exported for that pass.

Snap turn rotates about your head rather than the XR origin: in roomscale the
two can be a metre apart, and turning about the origin swings you through an
arc instead of rotating you in place.

Hitting one of the three glowing panels on the front wall is worth bonus
points; it goes dark and reappears elsewhere.

The rally is pitched at roughly 1.25m — chest height rather than head height —
so that the paddle and the ball stay in the headset's field of view together.
Raising `WallTarget` and `ServePoint` pushes the action up out of view.

### The jukebox panel (spike)

A web page on the left wall, drawn by the XR compositor rather than by us.

Everything reusable lives in `addons/xr_webview` — `XRWebPanel`, plus the
Android plugin it needs — so it can be revised, and eventually shipped to
other Godot XR projects, without touching the game. `scripts/jukebox.gd` is
what is true of this court: the video it opens on, the hosts it allows, and
where it hangs. It is wired to the `Jukebox` node under `XROrigin3D`.

**Working on a Quest Pro** (Horizon OS, Godot 4.7.2, vendors 5.1.0): a live
Android WebView draws into a compositor-owned swapchain, plays YouTube with
JavaScript, and answers a controller — taps toggle playback, drags seek the
timeline. It took the Gradle-built shim this spike set out to avoid
(`addons/xr_webview`), and one of the design claims below did not survive
contact with Android at all. See **Where it actually stands**.

The usual way to put a web page in a VR game is to render an Android WebView
to a texture and map it onto a quad. That copies the page every frame and
samples it through the eye buffer, which is why in-game browsers look mushy
next to the system one. It also cannot show DRM-protected content at all,
because protected surfaces never capture.

**This approach does not fix the DRM half, and that was the original premise.**
Measured on a Quest Pro: `protected_content` does make the runtime allocate a
protected swapchain — logcat says `creating as protected resource` — but
nothing we own may fill it. A protected swapchain wants a secure producer, and
asking for a secure `VirtualDisplay` throws `SecurityException: Requires
CAPTURE_SECURE_VIDEO_OUTPUT or an appropriate MediaProjection token`. That
permission is signature-level, so a normal app cannot hold it; without the flag
the panel draws a placeholder instead of the page. Both ways closed. Widevine
would need a browser rendering to the surface directly rather than through a
`VirtualDisplay` — a native Chromium embedding, not GDScript. Leave
`protected_content` off.

What does survive is the rest of it, and it is still the reason to build it
this way: text at panel resolution rather than through the eye buffer,
hardware video decode, and nothing on the frame budget.

This uses `OpenXRCompositionLayer.use_android_surface` instead, which asks the
runtime (`XR_KHR_android_surface_swapchain`) for an `android.view.Surface`
backed by the compositor's own swapchain. A `VirtualDisplay` hosts a real,
hardware-accelerated WebView and draws into it, and the compositor samples the
result at panel resolution, once, outside our render loop. Sharp text, working
video decode, nothing on the frame budget.

It was meant to be all GDScript. Implementing `java.lang.Runnable` from a
`Callable` (`JavaClassWrapper.create_sam_callback`) landed in Godot 4.7, and
that removed the last *known* reason to need a Gradle-built plugin. A second
one turned up on the device — `getSettings()` cannot be wrapped at all — so
there is a small Java shim after all, in `addons/xr_webview/android`. Build it
with `just shim`; see below for why it cannot be avoided.

What it costs, and what to look at first in the headset:

- The layer is a flat quad the compositor owns, not geometry. No shaders on
  it, and depth only through hole punch. Hole punch is reported to misbehave
  on some Quest runtimes; if the panel ghosts or punches through things it
  should not, turn `enable_hole_punch` off on the node and accept that it
  draws over the court.
- `XR_KHR_android_surface_swapchain` is implemented inconsistently — the
  Oculus runtime flips the surface under the GL drivers, Pico flips under
  Vulkan. `XRWebPanel.needs_vertical_flip` encodes both. Quest on the mobile
  (Vulkan) renderer, which is what this project ships, needs no flip -
  confirmed on a Quest Pro from the probe page's corner markers.
- Foveation is already off in this project (see `project.godot`) because
  level 2 blacks out the view on this Quest Pro. Composition layers and
  foveation share swapchain setup, so expect to re-test that interaction.

**Input works.** A ray is intersected with the quad's plane and the trigger
becomes `MotionEvent`s dispatched straight at the WebView — no shim needed for
this part, since `MotionEvent` is a framework class GDScript can wrap. Taps
toggle playback, drags seek the timeline, both on the device.

Movement under `touch_slop_px` is swallowed so a press stays a tap. Without
that, hand tremor at 90fps drifted a held press ~140px, which Chromium read as
a scroll: the player showed its controls and nothing was ever clicked.

There is no cursor, and a 3D one cannot work — a composition layer composites
over the eye buffer, so a marker at the ray's hit point draws behind the panel
however close it sits. It has to be drawn inside the page; see issue #19.

`home_url` defaults to a video: Blender's Big Buck Bunny at 4K60 (CC-BY), no
account needed, served through the embed player. Point it anywhere inside
`allowed_hosts` from the inspector.

Navigation is allow-listed (`allowed_hosts`), https-only, and fails closed on
an empty list. This is not paranoia about our own code: a browser in a VR app
is a screen a player can put anything on in front of other people, which is a
store-review problem before it is a moderation one, and a WebView will happily
follow `file://` straight into `user://progress.cfg`.

That allowlist governs where *we* navigate. `setAllowFileAccess(false)` and
`setAllowContentAccess(false)` stop the *page* reaching for `file://` behind
our back, and both are applied now that the shim can reach `WebSettings`. The
allowlist is enforced in Java as well, on `shouldOverrideUrlLoading`, because a
link the page itself follows never passes through GDScript to be checked.

Build without the shim and none of that is in force: the panel still runs, but
with JavaScript off and file access at WebView defaults. `just verify-shim`
reads the APK's dex and fails if the plugin is missing, and CI runs it.

This is the one thing under `scripts/` that knows what headset it is on, which
is a real exception to the claim in **Targets** below. The runtime sniffing is
confined to `needs_vertical_flip`, and it is there because the extension's
implementations genuinely differ, not because the game does.

#### Where it actually stands

From a run on a USB-tethered Quest Pro.

**Proven.** A second composition layer is submitted and composited every
frame — `LCnt=2`, `FPS=90/90`, `Stale=0`, `GPU%` under 1. "Nothing on our
frame budget" holds. The `VirtualDisplay` is created as the system sees it
(`displayId 24, FLAG_PRESENTATION, real 1280 x 720`), Chromium initialises
in-process, and `create_sam_callback` delivers the Runnable to the UI thread.

**Resolved, but only with a shim — `getSettings()` is unreachable from
GDScript.** Since Android P
the WebView implementation lives in its own classloader. `WebSettings` is
abstract and the instance behind it is
`com.android.webview.chromium.ContentSettingsAdapter`, which the app
classloader cannot see. `JavaClassWrapper` wraps a return value by its
concrete class, so the wrap fails, the method never becomes callable, and the
call raises `Invalid call. Nonexistent function 'getSettings'`. Reflection is
no way out — `Method.invoke()` hands the same unwrappable object back across
the same boundary.

That meant no JavaScript, no DOM storage, no autoplay and none of the file
access lockdown. **It took the Gradle-built shim this spike set out to avoid**
— `addons/xr_webview/android`, a 5KB AAR, and that is the honest cost.

The trick is that the unwrappable object never has to cross: `JavaClassWrapper`
only fails on *returning* one, and passing a `WebView` in is fine, because
`android.webkit.WebView` is a framework class the app classloader does see. So
every method takes the WebView and returns void, and `ContentSettingsAdapter`
stays in Java. `WebViewClient` and `WebChromeClient` live there too, for a
different reason: they are classes rather than single-method interfaces, so
`create_sam_callback` cannot stand in for them.

One trap worth repeating, because the build stays green through it: Godot
detects a `.gdap`, writes no entry for it in the export preset, defaults it
off, and exports an APK with the classes absent. The preset needs
`plugins/XRWebView=true`, and the only honest check is the dex.

Two knock-on fixes are in: the settings call now happens last, so its failure
no longer takes `setContentView()` and `show()` with it, and `surface_ready`
is emitted with `call_deferred` because `emit()` is rejected off the Godot
thread.

**Fixed — `XR_ERROR_HANDLE_INVALID` at session start.** Ours, in the scene
file. `OpenXRCompositionLayer.set_android_surface_size()` takes a different
path once `use_android_surface` is already true: it calls `xrUpdateSwapchainFB`
on a swapchain that has not been created yet. The node set the flag before the
size, so that fired every launch. Setting the size first skips the call, and
`test_the_scene_sizes_the_surface_before_it_asks_for_one` pins the order.

Worth saying plainly: the error was probably always cosmetic. `swapchain_size`
is assigned before the failing call, so the later swapchain still comes up at
the right size, and the grey panel is fully explained by the settings abort
above. That is a reading of the engine source, not a measurement.

**Answered — the surface is alive.** `probe_only` drew on the Quest Pro:
`android_surface=ok`, `webview_live=true`, page pixels on the quad, with
`FPS=90/90` and `Stale=0` while the layer was submitted. The corner markers
came up the right way round, so `needs_vertical_flip()` has the Oculus plus
Vulkan case right and no flip is needed here. The deferred signals arrive too.

Three faults hid each other on the way there. The `getSettings()` abort came
first. Then `loadData()` ate the probe page: it URL-decodes its payload, so
`#` opened a fragment and truncated the document at the first hex colour, and
`%` read as an escape. The page drew white, with no exception and nothing in
the log. `rgb()` and flex centring avoid both characters, and a test pins
them, because **any** HTML this panel loads through `loadData()` carries the
same constraint and the same silent failure. Last, the probe scene's own
control quad had no `layer_viewport`: it is an object property serialised as a
`NodePath`, the scene was hand-written rather than saved by the editor, and
the path never resolved - so the simple path sat dark while the exotic one
worked.

**Answered since — a real page, and input.** With the shim in the build,
JavaScript, DOM storage and autoplay all work, and the YouTube embed plays on
the layer. Two more faults were in the way. A top-level request to `/embed/`
comes back as "Error 153" — the player wants a `Referer` and an embedding
origin, so the panel serves its own document and puts the player in an iframe.
And the video arrived cropped to its top-left quarter: `density_dpi` is 320, so
a 1280x720 surface is a 640x360 CSS viewport, and an iframe sized in pixels is
twice the panel. It is sized in `vw`/`vh` now.

**Closed — DRM.** Not a gap to fill but a dead end, measured both ways; see the
top of this section.

**Still unproven.** Hole punch — the working configuration is `sort_order`
overlay without it, so the caveat further up is neither confirmed nor refuted.
The foveation interaction. Keyboard input, which rules out search, and search
is most of what a jukebox is. And `xr-webview-addon.zip`, which is only built
on a `v*` tag and has never been produced. Tracked in issue #19.

To pick this up: `just probe` puts the two quads and the state readout in
front of you, and clearing `probe_only` in the inspector switches the
surface-fed quad to `home_url` once the settings can actually be applied.

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
pair with. A/X bind together as the lower pair and B/Y as the upper, so the
re-serve buttons land in the same place under the thumb on both devices.
Frame's Menu button is right-hand only, with the left controller's View
button bound to the same action.

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

## Impact sounds

`audio/paddle.wav`, `audio/wall.wav` and `audio/floor.wav` are generated too:
`just sounds` rebuilds them from `tools/make_sounds.py`, which uses only the
Python standard library. Each is a few decaying sine partials plus a short
seeded noise burst, so the output is byte-for-byte reproducible and CI fails
if the committed files drift from the generator.

`scripts/ball.gd` plays them through one `AudioStreamPolyphonic`, so a fast
rally layers impacts rather than cutting them off, and picks the sample by
surface: paddle, front wall, floor, and the wall sample lower and quieter for
the side walls, ceiling and back wall. Pitch and level ride the impact speed,
with a little random spread on top so repeated hits at the same speed do not
sound like one sample being retriggered.

## CI and containers

`.github/workflows/build.yml` exports a release APK on every push, caching
Godot and its export templates, and asserts the manifest still declares the
Quest VR entry points before uploading the artifact.

`.devcontainer/` pins Godot 4.7.2, JDK 21 and the Android SDK. It builds and
was verified to produce a working toolchain, but note it cannot help with the
headset half of the loop - deploying and testing still needs local USB.

Godot 4.8 beta 2 is an opt-in trial, not the pin. `just trial-48` (or the
**Godot 4.8 beta 2 trial** workflow, which is `workflow_dispatch` only) imports,
tests and exports a copy of the project on 4.8-beta2 with matching templates,
and compares sizes with the stable pin. It does not replace `godot` on `PATH`.
Results and the device checklist are in `docs/godot-4.8-beta2-trial.md`.

Pushing a tag matching `v*` drafts a GitHub Release with both builds
attached, using the `gh` CLI the runner already ships. It is a draft, so a
human decides when it goes out. A tagged build **fails** rather than warns
if `ANDROID_KEYSTORE_BASE64` (and the user and password secrets beside it)
is not configured: a throwaway-signed APK cannot update any install but its
own, which is fine for a branch build nobody installs and not fine for
something published under a version number.

`.github/workflows/release-channel.yml` plans that Release, a Horizon ALPHA
upload, and a Steam Frame depot upload. The plan runs with no secrets: it
writes a `release-channel-plan` artifact and does not create a release, push
a tag, or upload to a store. The secret names, the keystore command, and the
store commands are in `docs/release-channel.md`. Issue #13 stays open until
those secrets exist and the uploads are actually run.

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
