# XR Web Panel

An Android WebView drawn by the XR compositor rather than rendered to a texture. For Godot 4.7+ on Quest and other OpenXR Android runtimes.

Sharp text, hardware video decode, DRM-capable, and nothing on the render loop — measured at 90/90 FPS with no stale frames on a Quest Pro, with the layer submitted every frame.

## Why not render to a texture

The usual way to get a web page into a VR game is WebView → texture → quad. That copies the whole page every frame, samples it through the eye buffer — which is why in-game browsers look mushy next to the system one — and cannot show DRM-protected content at all, because protected surfaces never capture.

`OpenXRCompositionLayer.use_android_surface` asks the runtime, through `XR_KHR_android_surface_swapchain`, for an `android.view.Surface` backed by the compositor's own swapchain. A `VirtualDisplay` hosts a real, hardware-accelerated WebView and draws into it, and the compositor samples the result at panel resolution, once, outside your render loop.

## Install

1. Copy `addons/xr_webview/` into your project.
2. Put the Android plugin where the exporter can see it:

   ```
   mkdir -p android/plugins
   cp addons/xr_webview/android/XRWebView.gdap android/plugins/
   cp addons/xr_webview/android/xr-webview-release.aar android/plugins/
   ```

   Enabling the addon in Project Settings does this for you. `res://android/plugins` is the only directory the Android exporter scans, and it is engine-generated, so the files cannot simply live in the addon.

   Release builds ship a prebuilt AAR. To build it yourself: `cd addons/xr_webview/android && ./gradlew assembleRelease`, which needs JDK 17–21 and `ANDROID_HOME`.

3. **Enable the plugin in your Android export preset.** Add to `export_presets.cfg` under the Android preset's `[preset.N.options]`:

   ```
   plugins/XRWebView=true
   ```

   This step is easy to miss and fails silently: Godot detects the plugin, writes no preset entry, defaults it to off, and exports successfully with the class absent. The panel then loads every page with JavaScript disabled and nothing says why. Verify by reading the dex, not by trusting a green build:

   ```
   unzip -p build/your.apk classes.dex | grep -c XRWebViewBridge
   ```

4. Add `android.permission.INTERNET` to the preset's `permissions/custom_permissions`.

## Use

Add an `XRWebPanel` as a child of `XROrigin3D` — composition layers are posed against the XR reference space, so keeping them under the origin makes their transform read as world coordinates.

In the scene, **set `android_surface_size` before `use_android_surface`**. Setting the size once the flag is already true takes a different path that calls `xrUpdateSwapchainFB` on a swapchain which does not exist yet, and fails at session start with `XR_ERROR_HANDLE_INVALID`.

```gdscript
extends XRWebPanel

func _init() -> void:
    allowed_hosts = ["example.com"]
    home_url = "https://example.com/"
    probe_only = false
```

| Property | Default | Notes |
| --- | --- | --- |
| `home_url` | `""` | Loaded once the surface is live |
| `allowed_hosts` | `[]` | Fail-closed: empty allows nothing. Suffix-matched on a dot boundary |
| `allow_autoplay` | `true` | Media may start without a gesture — a VR panel has no cursor to tap with |
| `probe_only` | `true` | Draws a built-in test page instead of navigating. Turn off to use `home_url` |
| `use_iframe_embed` | `true` | Serve `home_url` in an iframe on a page of our own rather than navigating to it |
| `embed_base_url` | — | The origin that page claims. Must be a real `https` URL |
| `density_dpi` | `320` | Device pixel ratio 2, so a 1280×720 surface is a 640×360 CSS viewport |

Signals: `surface_ready`, `navigation_blocked(url)`.

## Embedding players that check who is embedding them

YouTube answers a top-level request to `/embed/` with **Error 153** — no `Referer`, no embedding origin, no player. Leave `use_iframe_embed` on: the panel then serves its own document with `embed_base_url` as its origin and puts the player in an iframe, which is the embedding route YouTube's terms describe.

## Input

The panel lives on a `VirtualDisplay` no finger will ever touch, so touches are manufactured: `MotionEvent.obtain()` builds one and `dispatchTouchEvent()` hands it to the WebView. This needs neither the Android plugin nor the `INJECT_EVENTS` permission — `MotionEvent` is a framework class, and dispatching into your own view hierarchy is not system-wide injection.

Point a ray at the quad, convert the hit to panel coordinates, and send:

```gdscript
var local := panel.to_local(raycast.get_collision_point())
var uv := panel.local_to_uv(local)          # 0..1 across the quad, y flipped for the page
panel.tap(uv)                               # or send_touch(ACTION_DOWN/MOVE/UP, uv)
```

`tap()` is a press and release at one point, which a page reads as a click. A drag is `ACTION_DOWN`, any number of `ACTION_MOVE`s, then `ACTION_UP`. Send `ACTION_CANCEL` when the ray leaves the panel mid-drag, or the page waits for an `UP` that never comes. `send_touch()` returns `false` for a uv off the panel rather than clamping it to the border.

The quad has no collision shape of its own — give it an `Area3D` with a matching `BoxShape3D`, or intersect the ray with the quad's plane yourself.

## Debugging

Everything logs to logcat under the `XRWebView` tag, including the page's own JS console, which is the only window into a panel that cannot be inspected any other way:

```
adb logcat -s XRWebView:V godot:V
```

Start with `probe_only = true`. It draws a page needing no JavaScript, no network and no settings, so anything that appears proves the surface itself is alive. Its corner markers double as a flip test — `TOP LEFT` appearing bottom-right means `needs_vertical_flip()` is wrong for your runtime and renderer pair.

Blank panel, in the order worth checking: the plugin is not in the APK (see step 3); the layer is behind geometry (`sort_order`, or `enable_hole_punch`, which misbehaves on some Quest runtimes — turn it off and let the panel draw as an overlay); or the page never rendered.

## Known limits

- **`loadData()` cannot carry `#` or `%`.** It URL-decodes its payload, so `#` truncates the document at that point and `%` reads as an escape — silently, with a blank panel and nothing in the log. Applies to any HTML passed to the panel this way.
- **Hole punch is untested here.** The verified configuration is `sort_order` overlay without it.
- **Foveation interacts with composition layers** through shared swapchain setup and has not been exercised.

## Verified on

Quest Pro (`seacliff`), Horizon OS, Oculus runtime 207.218.0, Godot 4.7.2, `godot_openxr_vendors` 5.1.0, Vulkan mobile renderer. `needs_vertical_flip()` returns `false` for Oculus + Vulkan, confirmed by the probe page's corner markers.

## License

MIT, same as the project it was extracted from.
