# Godot 4.8 beta 2 device trial

Confirm upstream fixes on a **4.8-beta2** export of this project. These are
not known defects here. The build you ship is still 4.7.2 until that pin
changes. Install the trial APK or Steam Frame binary from `just trial-48`,
not the stable CI artifact.

Run `docs/godot-4.8-beta2-trial.md` first so the editor and the templates are
the pair that was checked (4.8-beta2, commit `cafc17a19`).

## ARM64 launch

- Quest: the APK is arm64-v8a only. Install it, launch, and confirm the court
  appears and tracking comes up. No immediate crash, no black frame with audio
  still playing.
- Steam Frame: the binary is a stripped ARM aarch64 ELF. Launch it on device
  and confirm the same.

## Touch, including clipped and off-screen buttons

Upstream: BaseButton ignores touches outside the visible viewport
(GH-123008). A letterboxed game was activating controls from taps in the
black bars.

This project's pause menu is a `Label3D` driven by the stick and the trigger,
not a `BaseButton`. The jukebox sends its own ray into an Android WebView.
Neither path is the bug that fix addresses.

- On device, confirm the jukebox still takes a tap as a tap and a drag as a
  seek. That is this game's touch path, and it should not regress.
- To check the upstream fix itself: on an Android device whose aspect ratio
  letterboxes the view, put a `BaseButton` at the edge of the visible
  viewport (a throwaway scene is enough; do not change the shipped menu).
  Tap the button, tap in the black bar beside it, and drag from the bar onto
  the button. A tap in the bar must not press it. Repeat on the exported
  build, not only in the desktop editor.

## Multiply blending on the Compatibility renderer

Upstream: multiply blending was too dark in the Compatibility renderer,
including a glow path that could darken the result further with HDR 2D off
(GH-124838). The note on that fix is that it is the Compatibility renderer.
This project ships `renderer/rendering_method=mobile`. A capture on Mobile
does not test this fix. The ball trail is additive (`blend_mode` 1), not
multiply.

On a copy, not on the pin: a 2D sprite with multiply blend over a flat
coloured background, Compatibility renderer, HDR 2D off, glow off and then
glow on. Compare with the same scene exported from 4.7.2. The beta image
should not be the extra-dark result. Do not repaint the art to compensate.

Android can host that temporary export. This repo has no iOS preset, so an
iOS confirmation needs an export preset added for the session and then
removed. Do not add one on the stable pin as part of the trial.

## Save and resume

- Play a rally long enough to store a best score. Turn comfort vignette off
  in the pause menu. Quit from the menu. Relaunch. The best score and the
  vignette setting come back (`user://progress.cfg`).
- Open the pause menu mid-rally and choose Resume. The rally is where it was
  left; tracking was not frozen.

Record the headset, OS build, and whether the binary was the beta trial or
the stable pin. A failure here is a beta regression to report upstream, with
the version string `4.8.beta2.official.cafc17a19`.
